[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$outputDirectory = [string]$config.output_dir
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$statusPath = Join-Path $outputDirectory 'perf01_status.json'
$processPath = Join-Path $outputDirectory 'perf01_processes.json'
$failure = ''
$logcatProcess = $null
$childProcesses = @()

function Quote-Perf01Argument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return ([char]34 + $Value + [char]34)
}

function Write-Perf01Status {
    param(
        [Parameter(Mandatory = $true)][string]$State,
        [string]$ErrorText = ''
    )
    $status = [ordered]@{
        state = $State
        updated_utc = Get-Perf01HostUtc
        serial = [string]$config.serial
        pid_at_start = [int]$config.pid
        surface_at_start = [string]$config.surface
        output_directory = $outputDirectory
        controller_pid = $PID
        logcat_pid = if ($null -ne $logcatProcess) { $logcatProcess.Id } else { $null }
        sampler_pids = @($childProcesses | ForEach-Object { $_.Id })
        error = $ErrorText
    }
    $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}

try {
    $stopFile = [string]$config.stop_file
    if (Test-Path -LiteralPath $stopFile) {
        Remove-Item -LiteralPath $stopFile -Force
    }
    $clearLog = @(& $config.adb -s $config.serial logcat -b all -c 2>&1 | ForEach-Object { "$_" })
    $clearLog | Set-Content -LiteralPath (Join-Path $outputDirectory 'perf01_logcat_clear.txt') -Encoding UTF8
    $clearCommand = "dumpsys SurfaceFlinger --latency-clear '$($config.surface)'"
    $clearLatency = Invoke-Perf01RemoteLines -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Command $clearCommand
    $clearLatency | Set-Content -LiteralPath (Join-Path $outputDirectory 'perf01_surface_clear.txt') -Encoding UTF8

    $powershell = Join-Path $PSHOME 'powershell.exe'
    $logcatArgs = "-s $($config.serial) logcat -b all -v threadtime"
    $logcatProcess = Start-Process -FilePath ([string]$config.adb) -ArgumentList $logcatArgs -RedirectStandardOutput (Join-Path $outputDirectory 'perf01_logcat.log') -RedirectStandardError (Join-Path $outputDirectory 'perf01_logcat_error.log') -WindowStyle Hidden -PassThru

    $samplerNames = @(
        'perf01-sample-surface.ps1',
        'perf01-sample-guest.ps1',
        'perf01-sample-host-gpu.ps1',
        'perf01-sample-host-cpu.ps1',
        'perf01-sample-memory.ps1'
    )
    foreach ($samplerName in $samplerNames) {
        $samplerPath = Join-Path $PSScriptRoot $samplerName
        $childArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' + (Quote-Perf01Argument $samplerPath) + ' -ConfigPath ' + (Quote-Perf01Argument $ConfigPath)
        $child = Start-Process -FilePath $powershell -ArgumentList $childArgs -RedirectStandardOutput (Join-Path $outputDirectory ($samplerName + '.out.log')) -RedirectStandardError (Join-Path $outputDirectory ($samplerName + '.err.log')) -WindowStyle Hidden -PassThru
        $childProcesses += $child
    }

    $processInfo = [ordered]@{
        controller_pid = $PID
        logcat_pid = $logcatProcess.Id
        sampler_pids = @($childProcesses | ForEach-Object { $_.Id })
        sampler_names = $samplerNames
    }
    $processInfo | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $processPath -Encoding UTF8
    Write-Perf01Status -State 'running'

    $duration = [int]$config.duration_seconds
    $started = [DateTime]::UtcNow
    while (-not (Test-Perf01StopRequested -StopFile ([string]$config.stop_file))) {
        if ($duration -gt 0 -and ([DateTime]::UtcNow - $started).TotalSeconds -ge $duration) {
            break
        }
        Start-Sleep -Milliseconds 500
    }
} catch {
    $failure = $_.Exception.Message
    Add-Content -LiteralPath (Join-Path $outputDirectory 'perf01_controller_error.log') -Value ((Get-Perf01HostUtc) + [char]9 + "$_") -Encoding UTF8
} finally {
    try {
        if (-not (Test-Path -LiteralPath ([string]$config.stop_file))) {
            'stop' | Set-Content -LiteralPath ([string]$config.stop_file) -Encoding ASCII
        }
    } catch {}
    foreach ($child in $childProcesses) {
        try {
            if (-not $child.HasExited) {
                [void]$child.WaitForExit(8000)
            }
            if (-not $child.HasExited) {
                Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    if ($null -ne $logcatProcess) {
        try {
            if (-not $logcatProcess.HasExited) {
                [void]$logcatProcess.WaitForExit(3000)
            }
            if (-not $logcatProcess.HasExited) {
                Stop-Process -Id $logcatProcess.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    try {
        $finalCommand = "dumpsys SurfaceFlinger --latency '$($config.surface)'"
        $finalLatency = Invoke-Perf01RemoteLines -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Command $finalCommand
        $finalLatency | Set-Content -LiteralPath (Join-Path $outputDirectory 'perf01_surface_final.txt') -Encoding UTF8
    } catch {
        Add-Content -LiteralPath (Join-Path $outputDirectory 'perf01_controller_error.log') -Value ((Get-Perf01HostUtc) + [char]9 + "final surface: $_") -Encoding UTF8
    }
    $finalPid = ''
    try { $finalPid = Get-Perf01TargetPid -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Package ([string]$config.package) } catch {}
    $finalRoot = ''
    try { $finalRoot = (Invoke-Perf01RemoteLines -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Command 'su -c id') -join ' ' } catch {}
    $finalDevices = @()
    try { $finalDevices = @(& $config.adb devices 2>&1 | ForEach-Object { "$_" }) } catch {}
    $state = if ($failure) { 'failed' } else { 'stopped' }
    $finalStatus = [ordered]@{
        state = $state
        updated_utc = Get-Perf01HostUtc
        serial = [string]$config.serial
        pid_at_start = [int]$config.pid
        pid_at_stop = "$finalPid"
        surface_at_start = [string]$config.surface
        output_directory = $outputDirectory
        controller_pid = $PID
        logcat_pid = if ($null -ne $logcatProcess) { $logcatProcess.Id } else { $null }
        sampler_pids = @($childProcesses | ForEach-Object { $_.Id })
        root_at_stop = $finalRoot
        adb_devices_at_stop = $finalDevices
        error = $failure
    }
    $finalStatus | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
