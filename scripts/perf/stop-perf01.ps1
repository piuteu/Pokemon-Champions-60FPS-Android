[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SessionDirectory
)

$ErrorActionPreference = 'Stop'
$sessionDirectory = (Resolve-Path -LiteralPath $SessionDirectory).Path
$configPath = Join-Path $sessionDirectory 'perf01_config.json'
$statusPath = Join-Path $sessionDirectory 'perf01_status.json'
$processPath = Join-Path $sessionDirectory 'perf01_processes.json'
$stopFile = Join-Path $sessionDirectory 'perf01.stop'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "PERF-01 config not found: $configPath"
}
'stop' | Set-Content -LiteralPath $stopFile -Encoding ASCII

$deadline = [DateTime]::UtcNow.AddSeconds(30)
$status = $null
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $statusPath) {
        try { $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json } catch {}
        if ($null -ne $status -and $status.state -in @('stopped','failed')) {
            break
        }
    }
    Start-Sleep -Milliseconds 500
}

if ($null -eq $status -or $status.state -notin @('stopped','failed')) {
    $pids = @()
    if (Test-Path -LiteralPath $processPath) {
        try {
            $processInfo = Get-Content -LiteralPath $processPath -Raw | ConvertFrom-Json
            $pids += @($processInfo.sampler_pids)
            $pids += @($processInfo.logcat_pid)
            $pids += @($processInfo.controller_pid)
        } catch {}
    }
    foreach ($processId in $pids) {
        if ("$processId" -match '^\d+$') {
            Stop-Process -Id ([int]$processId) -Force -ErrorAction SilentlyContinue
        }
    }
    $status = [pscustomobject]@{ state = 'forced_stop_timeout' }
}

Write-Output "PERF-01 stopped: $sessionDirectory"
Write-Output "status: $($status.state)"
Write-Output "surface: $(Join-Path $sessionDirectory 'perf01_surface.csv')"
Write-Output "guest_cpu: $(Join-Path $sessionDirectory 'perf01_guest_cpu.csv')"
Write-Output "host_gpu: $(Join-Path $sessionDirectory 'perf01_host_gpu.csv')"
Write-Output "host_cpu: $(Join-Path $sessionDirectory 'perf01_host_cpu.csv')"
Write-Output "memory: $(Join-Path $sessionDirectory 'perf01_memory.csv')"
Write-Output "logcat: $(Join-Path $sessionDirectory 'perf01_logcat.log')"
