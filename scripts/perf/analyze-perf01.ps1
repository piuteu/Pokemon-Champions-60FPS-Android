[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SessionDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')
$sessionDirectory = (Resolve-Path -LiteralPath $SessionDirectory).Path
$surfacePath = Join-Path $sessionDirectory 'perf01_surface.csv'
if (-not (Test-Path -LiteralPath $surfacePath -PathType Leaf)) {
    throw "Surface capture not found: $surfacePath"
}

$surfaceRows = @(Import-Csv -LiteralPath $surfacePath)
$validRows = @(
    $surfaceRows | Where-Object {
        "$($_.actual_valid)" -eq 'True' -and "$($_.actual_present_ns)" -match '^\d+$'
    }
)
$uniqueRows = @(
    $validRows |
        Group-Object -Property actual_present_ns |
        ForEach-Object { $_.Group | Select-Object -First 1 } |
        Sort-Object { [int64]$_.actual_present_ns }
)

$intervalPath = Join-Path $sessionDirectory 'perf01_surface_intervals.csv'
$intervalLines = New-Object System.Collections.Generic.List[string]
[void]$intervalLines.Add('frame_index,previous_present_ns,actual_present_ns,interval_ms,fps,below_55,below_50,below_45,below_40,host_utc')
$intervals = New-Object System.Collections.Generic.List[object]
for ($i = 1; $i -lt $uniqueRows.Count; $i++) {
    $previous = [int64]$uniqueRows[$i - 1].actual_present_ns
    $actual = [int64]$uniqueRows[$i].actual_present_ns
    $delta = $actual - $previous
    if ($delta -le 0) {
        continue
    }
    $intervalMs = $delta / 1000000.0
    $fps = 1000.0 / $intervalMs
    $item = [pscustomobject]@{
        frame_index = $i
        previous_present_ns = $previous
        actual_present_ns = $actual
        interval_ms = [math]::Round($intervalMs, 4)
        fps = [math]::Round($fps, 4)
        below_55 = ($fps -lt 55)
        below_50 = ($fps -lt 50)
        below_45 = ($fps -lt 45)
        below_40 = ($fps -lt 40)
        host_utc = $uniqueRows[$i].host_utc
    }
    [void]$intervals.Add($item)
    $fields = foreach ($value in @($item.frame_index,$item.previous_present_ns,$item.actual_present_ns,$item.interval_ms,$item.fps,$item.below_55,$item.below_50,$item.below_45,$item.below_40,$item.host_utc)) {
        '"' + (("$value").Replace('"', '""')) + '"'
    }
    [void]$intervalLines.Add(($fields -join ','))
}
$intervalLines.ToArray() | Set-Content -LiteralPath $intervalPath -Encoding UTF8

function Get-Perf01NumericValues {
    param(
        [object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Property
    )
    $values = New-Object System.Collections.Generic.List[double]
    foreach ($row in $Rows) {
        try { [void]$values.Add([double]$row.$Property) } catch {}
    }
    return @($values)
}

function Get-Perf01Stats {
    param(
        [object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$Property
    )
    $values = @(Get-Perf01NumericValues -Rows $Rows -Property $Property)
    if ($values.Count -eq 0) {
        return [ordered]@{ count = 0; min = $null; max = $null; average = $null }
    }
    return [ordered]@{
        count = $values.Count
        min = [math]::Round(([double]($values | Measure-Object -Minimum).Minimum), 3)
        max = [math]::Round(([double]($values | Measure-Object -Maximum).Maximum), 3)
        average = [math]::Round(([double]($values | Measure-Object -Average).Average), 3)
    }
}

$intervalRows = $intervals.ToArray()
$fpsValues = @(Get-Perf01NumericValues -Rows $intervalRows -Property 'fps')
$intervalValues = @(Get-Perf01NumericValues -Rows $intervalRows -Property 'interval_ms')
$hitchRows = @($intervals | Where-Object { $_.fps -lt 55 })
$hitchPath = Join-Path $sessionDirectory 'perf01_hitch_windows.csv'
$hitchLines = New-Object System.Collections.Generic.List[string]
[void]$hitchLines.Add('frame_index,host_utc,interval_ms,fps,severity')
foreach ($item in $hitchRows) {
    $severity = if ($item.fps -lt 40) { 'below_40' } elseif ($item.fps -lt 45) { 'below_45' } elseif ($item.fps -lt 50) { 'below_50' } else { 'below_55' }
    $fields = foreach ($value in @($item.frame_index,$item.host_utc,$item.interval_ms,$item.fps,$severity)) {
        '"' + (("$value").Replace('"', '""')) + '"'
    }
    [void]$hitchLines.Add(($fields -join ','))
}
$hitchLines.ToArray() | Set-Content -LiteralPath $hitchPath -Encoding UTF8

$logcatPath = Join-Path $sessionDirectory 'perf01_logcat.log'
$logcatText = if (Test-Path -LiteralPath $logcatPath) { Get-Content -LiteralPath $logcatPath -Raw } else { '' }
$targetPid = 0
try {
    $targetPid = [int]((Get-Content -LiteralPath (Join-Path $sessionDirectory 'perf01_config.json') -Raw | ConvertFrom-Json).pid)
} catch {}
$targetLogcatLines = @(
    $logcatText -split '\r?\n' |
        Where-Object { $targetPid -gt 0 -and $_ -match ('^\d\d-\d\d\s+\d\<build-dir>' + $targetPid + '\s') }
)
$targetLogcatText = $targetLogcatLines -join [char]10
$eventCounts = [ordered]@{
    target_pid_logcat_lines = $targetLogcatLines.Count
    gc = ([regex]::Matches($targetLogcatText, '(?im)\bGC\b|WaitForGcToComplete|Concurrent mark sweep')).Count
    loading_or_asset = ([regex]::Matches($targetLogcatText, '(?im)scene|loading|asset|shader|texture|addressable|decompress')).Count
    graphics = ([regex]::Matches($targetLogcatText, '(?im)Surface|EGL|Vulkan|OpenGL|GLES|GPU')).Count
    crash_or_anr = ([regex]::Matches($targetLogcatText, '(?im)FATAL EXCEPTION|AndroidRuntime|ANR in|SIGSEGV|Fatal signal|crash')).Count
    pcfps = ([regex]::Matches($targetLogcatText, '(?im)PCFPS|pcfps')).Count
}
$eventLines = foreach ($key in $eventCounts.Keys) { "$key=$($eventCounts[$key])" }
$eventLines | Set-Content -LiteralPath (Join-Path $sessionDirectory 'perf01_logcat_event_counts.txt') -Encoding UTF8

$guestRows = @()
$guestPath = Join-Path $sessionDirectory 'perf01_guest_cpu.csv'
if (Test-Path -LiteralPath $guestPath) { $guestRows = @(Import-Csv -LiteralPath $guestPath) }
$gpuRows = @()
$gpuPath = Join-Path $sessionDirectory 'perf01_host_gpu.csv'
if (Test-Path -LiteralPath $gpuPath) { $gpuRows = @(Import-Csv -LiteralPath $gpuPath) }
$hostRows = @()
$hostPath = Join-Path $sessionDirectory 'perf01_host_cpu.csv'
if (Test-Path -LiteralPath $hostPath) { $hostRows = @(Import-Csv -LiteralPath $hostPath) }
$memoryRows = @()
$memoryPath = Join-Path $sessionDirectory 'perf01_memory.csv'
if (Test-Path -LiteralPath $memoryPath) { $memoryRows = @(Import-Csv -LiteralPath $memoryPath) }

$summary = [ordered]@{
    session_directory = $sessionDirectory
    surface_samples = $surfaceRows.Count
    valid_surface_samples = $validRows.Count
    unique_present_timestamps = $uniqueRows.Count
    interval_count = $intervals.Count
    min_fps = if ($fpsValues.Count) { [math]::Round(([double]($fpsValues | Measure-Object -Minimum).Minimum), 3) } else { $null }
    max_interval_ms = if ($intervalValues.Count) { [math]::Round(([double]($intervalValues | Measure-Object -Maximum).Maximum), 3) } else { $null }
    frame_interval_stats_ms = Get-Perf01Stats -Rows $intervalRows -Property 'interval_ms'
    fps_stats = Get-Perf01Stats -Rows $intervalRows -Property 'fps'
    below_55_count = @($intervals | Where-Object { $_.fps -lt 55 }).Count
    below_50_count = @($intervals | Where-Object { $_.fps -lt 50 }).Count
    below_45_count = @($intervals | Where-Object { $_.fps -lt 45 }).Count
    below_40_count = @($intervals | Where-Object { $_.fps -lt 40 }).Count
    guest_thread_cpu_pct = Get-Perf01Stats -Rows $guestRows -Property 'thread_cpu_pct'
    host_gpu_util_pct = Get-Perf01Stats -Rows $gpuRows -Property 'gpu_util_pct'
    host_gpu_memory_util_pct = Get-Perf01Stats -Rows $gpuRows -Property 'memory_util_pct'
    host_cpu_total_pct = Get-Perf01Stats -Rows $hostRows -Property 'host_cpu_total_pct'
    hd_player_cpu_pct = Get-Perf01Stats -Rows $hostRows -Property 'hd_player_cpu_pct'
    guest_pss_kb = Get-Perf01Stats -Rows $memoryRows -Property 'guest_pss_kb'
    guest_rss_kb = Get-Perf01Stats -Rows $memoryRows -Property 'guest_rss_kb'
    logcat_event_counts = $eventCounts
    note = 'This is correlation data; classification requires scene/camera action labels from the user and timestamp-aligned review.'
}
$summaryPath = Join-Path $sessionDirectory 'perf01_surface_summary.json'
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

Write-Output "Analysis complete: $sessionDirectory"
Write-Output "Intervals: $intervalPath"
Write-Output "Hitches: $hitchPath"
Write-Output "Summary: $summaryPath"
Get-Content -LiteralPath $summaryPath
