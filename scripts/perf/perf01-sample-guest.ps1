[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$outputDirectory = [string]$config.output_dir
$csvPath = Join-Path $outputDirectory 'perf01_guest_cpu.csv'
$rawPath = Join-Path $outputDirectory 'perf01_guest_top.log'
if (-not (Test-Path -LiteralPath $csvPath)) {
    'host_utc,host_unix_ms,tid,pid,thread_cpu_pct,thread_cpu_time,thread_name,proc_state,proc_vmrss_kb,voluntary_ctxt_switches,nonvoluntary_ctxt_switches' | Set-Content -LiteralPath $csvPath -Encoding UTF8
}

while (-not (Test-Perf01StopRequested -StopFile ([string]$config.stop_file))) {
    $hostUtc = Get-Perf01HostUtc
    $hostMs = Get-Perf01UnixMilliseconds
    try {
        $targetPid = [int]$config.pid
        $statusLines = Invoke-Perf01RemoteLines -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Command "cat /proc/$targetPid/status"
        $stateLine = $statusLines | Where-Object { $_ -match '^State:' } | Select-Object -First 1
        $vmrssLine = $statusLines | Where-Object { $_ -match '^VmRSS:' } | Select-Object -First 1
        $voluntaryLine = $statusLines | Where-Object { $_ -match '^voluntary_ctxt_switches:' } | Select-Object -First 1
        $nonvoluntaryLine = $statusLines | Where-Object { $_ -match '^nonvoluntary_ctxt_switches:' } | Select-Object -First 1
        $state = if ($stateLine) { ($stateLine -replace '^State:\s*','').Trim() } else { '' }
        $vmrss = if ($vmrssLine) { (($vmrssLine -replace '^VmRSS:\s*','').Trim() -replace '\s+.*$','') } else { '' }
        $voluntary = if ($voluntaryLine) { ($voluntaryLine -replace '^voluntary_ctxt_switches:\s*','').Trim() } else { '' }
        $nonvoluntary = if ($nonvoluntaryLine) { ($nonvoluntaryLine -replace '^nonvoluntary_ctxt_switches:\s*','').Trim() } else { '' }
        $topCommand = "top -H -b -n 1 -p $targetPid -m 64 -o TID,PID,CPU,TIME+,NAME"
        $topLines = Invoke-Perf01RemoteLines -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Command $topCommand
        Add-Content -LiteralPath $rawPath -Value ((Get-Perf01HostUtc) + [char]9 + ($topLines -join [char]10)) -Encoding UTF8
        foreach ($line in $topLines) {
            if ($line -match '^\s*(\d+)\s+(\d+)\s+([0-9.]+)\s+(\S+)\s+(.+?)\s*$') {
                Write-Perf01CsvRow -Path $csvPath -Values @($hostUtc,$hostMs,$Matches[1],$Matches[2],$Matches[3],$Matches[4],$Matches[5].Trim(),$state,$vmrss,$voluntary,$nonvoluntary)
            }
        }
    } catch {
        Write-Perf01SamplerError -OutputDirectory $outputDirectory -Sampler 'guest' -ErrorRecord $_
    }
    Start-Sleep -Milliseconds 500
}
