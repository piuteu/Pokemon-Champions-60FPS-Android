[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$outputDirectory = [string]$config.output_dir
$csvPath = Join-Path $outputDirectory 'perf01_memory.csv'
if (-not (Test-Path -LiteralPath $csvPath)) {
    'host_utc,host_unix_ms,guest_pid,guest_pss_kb,guest_rss_kb,guest_vmrss_kb,guest_rss_anon_kb,hd_player_pids,hd_player_working_set_bytes,hd_player_private_bytes,host_available_memory_bytes,error' | Set-Content -LiteralPath $csvPath -Encoding UTF8
}

while (-not (Test-Perf01StopRequested -StopFile ([string]$config.stop_file))) {
    $hostUtc = Get-Perf01HostUtc
    $hostMs = Get-Perf01UnixMilliseconds
    $pss = ''
    $rss = ''
    $vmrss = ''
    $rssAnon = ''
    $hdPids = ''
    $hdWorking = ''
    $hdPrivate = ''
    $available = ''
    $errorText = ''
    try {
        $targetPid = [int]$config.pid
        $memLines = Invoke-Perf01RemoteLines -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Command "dumpsys meminfo $targetPid"
        $memText = $memLines -join [char]10
        if ($memText -match 'TOTAL PSS:\s*(\d+).*?TOTAL RSS:\s*(\d+)') {
            $pss = $Matches[1]
            $rss = $Matches[2]
        }
        $statusLines = Invoke-Perf01RemoteLines -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Command "cat /proc/$targetPid/status"
        $vmrssLine = $statusLines | Where-Object { $_ -match '^VmRSS:' } | Select-Object -First 1
        $rssAnonLine = $statusLines | Where-Object { $_ -match '^RssAnon:' } | Select-Object -First 1
        if ($vmrssLine -match '(\d+)') { $vmrss = $Matches[1] }
        if ($rssAnonLine -match '(\d+)') { $rssAnon = $Matches[1] }
    } catch {
        $errorText = $_.Exception.Message
    }
    try {
        $processes = @(Get-Process -Name 'HD-Player' -ErrorAction SilentlyContinue)
        $hdPids = ($processes.Id -join ';')
        $hdWorking = ($processes | Measure-Object -Property WorkingSet64 -Sum).Sum
        $hdPrivate = ($processes | Measure-Object -Property PrivateMemorySize64 -Sum).Sum
        $availableCounter = Get-Counter '\Memory\Available Bytes' -SampleInterval 1 -MaxSamples 1
        $available = [math]::Round([double](($availableCounter.CounterSamples | Select-Object -First 1).CookedValue), 0)
    } catch {
        if ($errorText) {
            $errorText = $errorText + '; ' + $_.Exception.Message
        } else {
            $errorText = $_.Exception.Message
        }
    }
    Write-Perf01CsvRow -Path $csvPath -Values @($hostUtc,$hostMs,$config.pid,$pss,$rss,$vmrss,$rssAnon,$hdPids,$hdWorking,$hdPrivate,$available,$errorText)
    Start-Sleep -Seconds 1
}
