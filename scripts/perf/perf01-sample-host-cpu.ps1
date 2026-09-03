[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$outputDirectory = [string]$config.output_dir
$csvPath = Join-Path $outputDirectory 'perf01_host_cpu.csv'
if (-not (Test-Path -LiteralPath $csvPath)) {
    'host_utc,host_unix_ms,host_cpu_total_pct,hd_player_cpu_pct,hd_player_pids,hd_player_count,counter_error' | Set-Content -LiteralPath $csvPath -Encoding UTF8
}

while (-not (Test-Perf01StopRequested -StopFile ([string]$config.stop_file))) {
    $hostUtc = Get-Perf01HostUtc
    $hostMs = Get-Perf01UnixMilliseconds
    $totalCpu = ''
    $hdCpu = ''
    $counterError = ''
    try {
        $totalCounter = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
        $totalSample = $totalCounter.CounterSamples | Select-Object -First 1
        $totalCpu = [math]::Round([double]$totalSample.CookedValue, 2)
        $hdCounter = Get-Counter '\Process(HD-Player*)\% Processor Time' -SampleInterval 1 -MaxSamples 1
        $hdSamples = @($hdCounter.CounterSamples | Where-Object { $_.Path -like '*HD-Player*' })
        if ($hdSamples.Count -gt 0) {
            $hdCpu = [math]::Round([double](($hdSamples | Measure-Object -Property CookedValue -Sum).Sum), 2)
        } else {
            $hdCpu = 0
        }
    } catch {
        $counterError = $_.Exception.Message
    }
    try {
        $processes = @(Get-Process -Name 'HD-Player' -ErrorAction SilentlyContinue)
        $pids = ($processes.Id -join ';')
        $count = $processes.Count
    } catch {
        $pids = ''
        $count = 0
    }
    Write-Perf01CsvRow -Path $csvPath -Values @($hostUtc,$hostMs,$totalCpu,$hdCpu,$pids,$count,$counterError)
    if (Test-Perf01StopRequested -StopFile ([string]$config.stop_file)) {
        break
    }
}
