[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$outputDirectory = [string]$config.output_dir
$csvPath = Join-Path $outputDirectory 'perf01_host_gpu.csv'
if (-not (Test-Path -LiteralPath $csvPath)) {
    'host_utc,host_unix_ms,gpu_index,gpu_name,driver_version,memory_total_mib,gpu_util_pct,memory_util_pct,sm_clock_mhz,memory_clock_mhz,memory_used_mib,power_draw_w' | Set-Content -LiteralPath $csvPath -Encoding UTF8
}

$smi = (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue).Source
while (-not (Test-Perf01StopRequested -StopFile ([string]$config.stop_file))) {
    $hostUtc = Get-Perf01HostUtc
    $hostMs = Get-Perf01UnixMilliseconds
    try {
        if (-not $smi) {
            throw 'nvidia-smi.exe is not available'
        }
        $query = @(& $smi '--query-gpu=index,name,driver_version,memory.total,utilization.gpu,utilization.memory,clocks.sm,clocks.mem,memory.used,power.draw' '--format=csv,noheader,nounits' 2>&1 | ForEach-Object { "$_" })
        foreach ($line in $query) {
            $fields = $line -split '\s*,\s*'
            if ($fields.Count -ge 10 -and $fields[0] -match '^\d+$') {
                Write-Perf01CsvRow -Path $csvPath -Values @($hostUtc,$hostMs,$fields[0],$fields[1],$fields[2],$fields[3],$fields[4],$fields[5],$fields[6],$fields[7],$fields[8],$fields[9])
            }
        }
    } catch {
        Write-Perf01SamplerError -OutputDirectory $outputDirectory -Sampler 'host_gpu' -ErrorRecord $_
    }
    Start-Sleep -Milliseconds 200
}
