[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$outputDirectory = [string]$config.output_dir
$csvPath = Join-Path $outputDirectory 'perf01_surface.csv'
if (-not (Test-Path -LiteralPath $csvPath)) {
    'host_utc,host_unix_ms,snapshot_id,refresh_period_ns,desired_present_ns,actual_present_ns,frame_ready_ns,actual_valid' | Set-Content -LiteralPath $csvPath -Encoding UTF8
}

$snapshotId = 0
while (-not (Test-Perf01StopRequested -StopFile ([string]$config.stop_file))) {
    $hostUtc = Get-Perf01HostUtc
    $hostMs = Get-Perf01UnixMilliseconds
    $rowsToWrite = New-Object System.Collections.Generic.List[string]
    try {
        $command = "dumpsys SurfaceFlinger --latency '$($config.surface)'"
        $lines = @(Invoke-Perf01RemoteLines -AdbPath ([string]$config.adb) -Serial ([string]$config.serial) -Command $command)
        $refresh = ''
        if ($lines.Count -gt 0 -and $lines[0] -match '^\s*\d+\s*$') {
            $refresh = $lines[0].Trim()
        }
        foreach ($line in $lines | Select-Object -Skip 1) {
            if ($line -match '^\s*(-?\d+)\s+(-?\d+)\s+(-?\d+)\s*$') {
                $snapshotId++
                $desired = $Matches[1]
                $actual = $Matches[2]
                $ready = $Matches[3]
                $valid = ([int64]$actual -gt 0 -and [int64]$actual -lt 9000000000000000000)
                $fields = foreach ($value in @($hostUtc,$hostMs,$snapshotId,$refresh,$desired,$actual,$ready,$valid)) {
                    '"' + (("$value").Replace('"', '""')) + '"'
                }
                [void]$rowsToWrite.Add(($fields -join ','))
            }
        }
    } catch {
        Write-Perf01SamplerError -OutputDirectory $outputDirectory -Sampler 'surface' -ErrorRecord $_
    }
    if ($rowsToWrite.Count -gt 0) {
        Add-Content -LiteralPath $csvPath -Value $rowsToWrite.ToArray() -Encoding UTF8
    }
    Start-Sleep -Milliseconds 500
}
