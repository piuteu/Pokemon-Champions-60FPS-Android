[CmdletBinding()]
param(
    [string]$Root = '.',
    [switch]$RequireConfig
)

$ErrorActionPreference = 'Stop'
$rootPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path)
$allowedName = 'piuteu'
$allowedEmail = 'piuteu@users.noreply.github.com'
$violations = 0

$configName = ((git -C $rootPath config --local --get user.name 2>$null) -join '').Trim()
$configEmail = ((git -C $rootPath config --local --get user.email 2>$null) -join '').Trim()
$configPresent = -not [string]::IsNullOrWhiteSpace($configName) -or
    -not [string]::IsNullOrWhiteSpace($configEmail)

if ($RequireConfig -and
    ($configName -ne $allowedName -or $configEmail -ne $allowedEmail)) {
    $violations++
}
elseif ($configPresent -and
    ($configName -ne $allowedName -or $configEmail -ne $allowedEmail)) {
    $violations++
}

if ($RequireConfig) {
    $authorIdent = ((git -C $rootPath var GIT_AUTHOR_IDENT 2>$null) -join '').Trim()
    $committerIdent = ((git -C $rootPath var GIT_COMMITTER_IDENT 2>$null) -join '').Trim()
    $identPattern = '^' + [regex]::Escape($allowedName) + ' <' +
        [regex]::Escape($allowedEmail) + '> \d+ [+-]\d{4}$'
    if ($authorIdent -notmatch $identPattern) { $violations++ }
    if ($committerIdent -notmatch $identPattern) { $violations++ }
}

$commits = @(git -C $rootPath rev-list --all)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enumerate reachable commits'
}

foreach ($commit in $commits) {
    $identity = ((git -C $rootPath show -s --format='%an%x09%ae%x09%cn%x09%ce' $commit 2>$null) -join '').Trim()
    $fields = $identity -split ([char]9)
    if ($fields.Count -ne 4 -or
        $fields[0] -ne $allowedName -or
        $fields[1] -ne $allowedEmail -or
        $fields[2] -ne $allowedName -or
        $fields[3] -ne $allowedEmail) {
        $violations++
    }
}

if ($violations -gt 0) {
    'GIT_IDENTITY_CHECK_FAIL violations={0} reachable_commits={1}' -f $violations, $commits.Count
    exit 1
}

'GIT_IDENTITY_CHECK_PASS reachable_commits={0}' -f $commits.Count
