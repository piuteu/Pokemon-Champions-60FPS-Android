[CmdletBinding()]
param(
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputDirectory = Join-Path $repoRoot 'build\perf'
if (-not $OutputPath) {
    $OutputPath = Join-Path $outputDirectory 'perf01_preflight.txt'
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null

$report = New-Object System.Collections.Generic.List[string]
function Add-ReportLine {
    param([string]$Text)
    [void]$report.Add($Text)
}

$adb = Get-Perf01AdbPath
$package = 'jp.pokemon.pokemonchampions'
Add-ReportLine "PERF-01 preflight: $(Get-Perf01HostUtc)"
Add-ReportLine "adb=$adb"
Add-ReportLine "package=$package"
Add-ReportLine "adb devices:"
(@(& $adb devices 2>&1 | ForEach-Object { "$_" })) | ForEach-Object {
    Add-ReportLine "  $_"
}

try {
    $serial = Get-Perf01Serial -AdbPath $adb
    Add-ReportLine "selected_serial=$serial"
    $release = (Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'getprop ro.build.version.release') -join ' '
    $sdk = (Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'getprop ro.build.version.sdk') -join ' '
    $abi = (Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'getprop ro.product.cpu.abi') -join ' '
    $abilist = (Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'getprop ro.product.cpu.abilist') -join ' '
    $bridge = (Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'getprop ro.dalvik.vm.native.bridge') -join ' '
    $rootId = (Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'su -c id') -join ' '
    Add-ReportLine "android_release=$release"
    Add-ReportLine "android_sdk=$sdk"
    Add-ReportLine "primary_abi=$abi"
    Add-ReportLine "abi_list=$abilist"
    Add-ReportLine "native_bridge=$bridge"
    Add-ReportLine "root_id=$rootId"

    $targetPid = Get-Perf01TargetPid -AdbPath $adb -Serial $serial -Package $package
    $surface = Get-Perf01UnitySurface -AdbPath $adb -Serial $serial -Package $package
    Add-ReportLine "target_pid=$targetPid"
    Add-ReportLine "unity_surface=$surface"

    $taskLines = Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command "ls -1 /proc/$targetPid/task | wc -l"
    Add-ReportLine "task_count=$($taskLines -join ' ')"
    $stat = Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command "cat /proc/$targetPid/stat"
    Add-ReportLine "proc_stat_available=$([bool]($stat -match '^\s*\d+\s'))"
    $topHelp = Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'top --help'
    Add-ReportLine "top_help_available=$([bool]($topHelp -match 'top'))"
    $latency = Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command "dumpsys SurfaceFlinger --latency '$surface'"
    Add-ReportLine "surface_latency_header=$($latency | Select-Object -First 1)"
    Add-ReportLine "surface_latency_rows=$(@($latency | Select-Object -Skip 1 | Where-Object { $_ -match '^\s*\d+\s+\d+\s+\d+\s*$' }).Count)"
    $perfettoHelp = Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'perfetto --help'
    Add-ReportLine "perfetto_available=$([bool]($perfettoHelp -match 'Usage: perfetto'))"
    $perfettoQuery = Invoke-Perf01RemoteLines -AdbPath $adb -Serial $serial -Command 'perfetto --query'
    Add-ReportLine "perfetto_query_available=$([bool]($perfettoQuery -match 'surfaceflinger'))"
} catch {
    Add-ReportLine "guest_probe_error=$($_.Exception.Message)"
}

$smi = (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue).Source
if ($smi) {
    Add-ReportLine "nvidia_smi=$smi"
    Add-ReportLine "nvidia_smi_version=$((@(& $smi --version 2>&1) -join ' '))"
    $gpuQuery = @(& $smi '--query-gpu=index,name,driver_version,memory.total,utilization.gpu,utilization.memory,clocks.sm,clocks.mem,memory.used,power.draw' '--format=csv,noheader,nounits' 2>&1)
    Add-ReportLine "nvidia_query=$($gpuQuery -join ' | ')"
} else {
    Add-ReportLine 'nvidia_smi=missing'
}

try {
    $counter = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1
    Add-ReportLine "windows_processor_counter=available"
    Add-ReportLine "windows_processor_sample=$($counter.CounterSamples[0].CookedValue)"
} catch {
    Add-ReportLine "windows_processor_counter=error: $($_.Exception.Message)"
}

try {
    $processes = @(Get-Process -Name 'HD-Player' -ErrorAction Stop)
    Add-ReportLine "hd_player_pids=$($processes.Id -join ',')"
    Add-ReportLine "hd_player_working_set=$($processes | Measure-Object -Property WorkingSet64 -Sum | Select-Object -ExpandProperty Sum)"
} catch {
    Add-ReportLine "hd_player=not_found_or_unreadable: $($_.Exception.Message)"
}

$report | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Preflight report: $OutputPath"
Get-Content -LiteralPath $OutputPath
