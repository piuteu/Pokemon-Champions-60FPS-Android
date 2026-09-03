[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build'
$moduleRoot = Join-Path $buildRoot 'pcfps_zygisk_auto_bootstrap'
$moduleZygisk = Join-Path $moduleRoot 'zygisk'
$modulePayload = Join-Path $moduleRoot 'payload'
$moduleProp = Join-Path $repoRoot 'bootstrap\auto-bootstrap-module.prop'
$bootstrap = Join-Path $buildRoot 'libpcfps_zygisk_auto_bootstrap_x86_64.so'
$payload = Join-Path $buildRoot 'libpcfps_runtime.so'
$zip = Join-Path $buildRoot 'pcfps_zygisk_auto_bootstrap.zip'

foreach ($required in @($moduleProp, $bootstrap, $payload)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required build artifact not found: $required"
    }
}

New-Item -ItemType Directory -Force -Path $moduleZygisk, $modulePayload | Out-Null
Copy-Item -LiteralPath $moduleProp -Destination (Join-Path $moduleRoot 'module.prop') -Force
Copy-Item -LiteralPath $bootstrap -Destination (Join-Path $moduleZygisk 'x86_64.so') -Force
Copy-Item -LiteralPath $payload -Destination (Join-Path $modulePayload 'libpcfps_runtime.so') -Force

if (Test-Path -LiteralPath $zip -PathType Leaf) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $moduleRoot '*') -DestinationPath $zip -CompressionLevel Optimal

Write-Output "Module directory: $moduleRoot"
Write-Output "Module ZIP: $zip"
Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $moduleRoot 'zygisk\x86_64.so'), `
    (Join-Path $moduleRoot 'payload\libpcfps_runtime.so'), `
    $zip | Format-Table -AutoSize
