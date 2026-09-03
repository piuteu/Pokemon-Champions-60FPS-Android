[CmdletBinding()]
param(
    [Alias('NdkRoot')][string]$RequestedNdkRoot = '',
    [switch]$UnblockNdk
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$compilerRelativePath = 'toolchains\llvm\prebuilt\windows-x86_64\bin\x86_64-linux-android33-clang++.cmd'
$readelfRelativePath = 'toolchains\llvm\prebuilt\windows-x86_64\bin\llvm-readelf.exe'
$ndkCandidates = New-Object 'System.Collections.Generic.List[string]'
if (-not [string]::IsNullOrWhiteSpace($RequestedNdkRoot)) {
    [void]$ndkCandidates.Add($RequestedNdkRoot)
}
foreach ($environmentName in @('ANDROID_NDK_HOME', 'ANDROID_NDK_ROOT')) {
    $environmentValue = [Environment]::GetEnvironmentVariable($environmentName)
    if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
        [void]$ndkCandidates.Add($environmentValue)
    }
}
if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $sdkNdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk\ndk'
    if (Test-Path -LiteralPath $sdkNdkRoot -PathType Container) {
        Get-ChildItem -LiteralPath $sdkNdkRoot -Directory | Sort-Object Name -Descending |
            ForEach-Object { [void]$ndkCandidates.Add($_.FullName) }
    }
}
$driveRoot = [IO.Path]::GetPathRoot($repoRoot)
if (-not [string]::IsNullOrWhiteSpace($driveRoot)) {
    $commonAndroidRoot = Join-Path $driveRoot 'Android'
    if (Test-Path -LiteralPath $commonAndroidRoot -PathType Container) {
        Get-ChildItem -LiteralPath $commonAndroidRoot -Directory | Sort-Object Name -Descending |
            ForEach-Object { [void]$ndkCandidates.Add($_.FullName) }
    }
}
$ndkRoot = $null
foreach ($candidate in $ndkCandidates) {
    try {
        $candidatePath = (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
    } catch {
        continue
    }
    if (Test-Path -LiteralPath (Join-Path $candidatePath $compilerRelativePath) -PathType Leaf) {
        $ndkRoot = $candidatePath
        break
    }
}
if ($null -eq $ndkRoot) {
    throw 'Android NDK not found. Pass -NdkRoot <android-ndk> or set ANDROID_NDK_HOME/ANDROID_NDK_ROOT.'
}
$compiler = Join-Path $ndkRoot $compilerRelativePath
$readelf = Join-Path $ndkRoot $readelfRelativePath
$source = Join-Path $repoRoot 'bootstrap\pcfps_zygisk_bootstrap.cpp'
$outputDirectory = Join-Path $repoRoot 'build'
$output = Join-Path $outputDirectory 'libpcfps_zygisk_auto_bootstrap_x86_64.so'

if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "x86_64 clang++ compiler not found: $compiler"
}
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Source file not found: $source"
}

# Windows Mark-of-the-Web mitigation is opt-in because recursively walking an
# entire NDK is expensive. It remains idempotent and scoped to this NDK.
if ($UnblockNdk) {
    Get-ChildItem -LiteralPath $ndkRoot -Recurse -File | Unblock-File
}

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

& $compiler `
    -target x86_64-linux-android33 `
    -std=c++17 `
    -O2 `
    -fPIC `
    -shared `
    -static-libstdc++ `
    -pthread `
    -Wall `
    -Wextra `
    -Wpedantic `
    $source `
    -o $output `
    -llog `
    -ldl

if ($LASTEXITCODE -ne 0) {
    throw "x86_64 bootstrap build failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
    throw "Bootstrap output not found: $output"
}

Write-Output "Built: $output"
Write-Output ((Get-FileHash -Algorithm SHA256 -LiteralPath $output).Hash.ToLowerInvariant())
if (Test-Path -LiteralPath $readelf -PathType Leaf) {
    & $readelf -h $output | Select-String 'Class:|Machine:'
    & $readelf -Ws $output | Select-String 'zygisk_module_entry'
}
