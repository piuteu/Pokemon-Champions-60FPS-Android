[CmdletBinding()]
param(
    [string]$Serial = '',
    [int]$DurationSeconds = 0
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'perf01-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$outputRoot = Join-Path $repoRoot 'build\perf'
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
$adb = Get-Perf01AdbPath
$package = 'jp.pokemon.pokemonchampions'
$selectedSerial = Get-Perf01Serial -AdbPath $adb -PreferredSerial $Serial
$targetPid = Get-Perf01TargetPid -AdbPath $adb -Serial $selectedSerial -Package $package
$surface = Get-Perf01UnitySurface -AdbPath $adb -Serial $selectedSerial -Package $package

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$sessionDirectory = Join-Path $outputRoot ('perf01_' + $stamp)
$index = 1
while (Test-Path -LiteralPath $sessionDirectory) {
    $sessionDirectory = Join-Path $outputRoot ('perf01_' + $stamp + '_' + $index.ToString('000'))
    $index++
}
New-Item -ItemType Directory -Force -Path $sessionDirectory | Out-Null
$configPath = Join-Path $sessionDirectory 'perf01_config.json'
$stopFile = Join-Path $sessionDirectory 'perf01.stop'
$config = [ordered]@{
    adb = $adb
    serial = $selectedSerial
    package = $package
    pid = $targetPid
    surface = $surface
    output_dir = $sessionDirectory
    stop_file = $stopFile
    duration_seconds = $DurationSeconds
    started_utc = Get-Perf01HostUtc
}
$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $configPath -Encoding UTF8

$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$controller = Join-Path $PSScriptRoot 'perf01-capture.ps1'
$quote = [char]34
$controllerArgs = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' + $quote + $controller + $quote + ' -ConfigPath ' + $quote + $configPath + $quote
$controllerProcess = Start-Process -FilePath $powershell -ArgumentList $controllerArgs -RedirectStandardOutput (Join-Path $sessionDirectory 'perf01_controller.out.log') -RedirectStandardError (Join-Path $sessionDirectory 'perf01_controller.err.log') -WindowStyle Hidden -PassThru
$controllerPidPath = Join-Path $sessionDirectory 'perf01_controller.pid'
$controllerProcess.Id | Set-Content -LiteralPath $controllerPidPath -Encoding ASCII

$statusPath = Join-Path $sessionDirectory 'perf01_status.json'
$deadline = [DateTime]::UtcNow.AddSeconds(15)
$status = $null
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $statusPath) {
        try { $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json } catch {}
        if ($null -ne $status -and $status.state -in @('running','failed','stopped')) {
            break
        }
    }
    Start-Sleep -Milliseconds 250
}

Write-Output "PERF-01 session: $sessionDirectory"
Write-Output "serial: $selectedSerial"
Write-Output "target_pid: $targetPid"
Write-Output "unity_surface: $surface"
Write-Output "controller_pid: $($controllerProcess.Id)"
if ($null -ne $status) {
    Write-Output "status: $($status.state)"
    if ($status.error) { Write-Output "error: $($status.error)" }
} else {
    Write-Output 'status: starting'
}
Write-Output "config: $configPath"
