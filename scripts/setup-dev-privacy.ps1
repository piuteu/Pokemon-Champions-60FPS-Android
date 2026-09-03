[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '..')
)

$ErrorActionPreference = 'Stop'
$rootPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path)

& git -C $rootPath config --local user.name 'piuteu'
if ($LASTEXITCODE -ne 0) { throw 'Unable to configure local user.name' }
& git -C $rootPath config --local user.email 'piuteu@users.noreply.github.com'
if ($LASTEXITCODE -ne 0) { throw 'Unable to configure local user.email' }
& git -C $rootPath config --local core.hooksPath '.githooks'
if ($LASTEXITCODE -ne 0) { throw 'Unable to configure local core.hooksPath' }

$name = ((git -C $rootPath config --local --get user.name 2>$null) -join '').Trim()
$email = ((git -C $rootPath config --local --get user.email 2>$null) -join '').Trim()
$hooks = ((git -C $rootPath config --local --get core.hooksPath 2>$null) -join '').Trim()
if ($name -ne 'piuteu' -or
    $email -ne 'piuteu@users.noreply.github.com' -or
    $hooks -ne '.githooks') {
    throw 'Repository-local privacy configuration did not verify'
}

'DEV_PRIVACY_SETUP_PASS hooks_path={0}' -f $hooks
