[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '..'),
    [string]$DisallowedUsername = $env:PCFPS_PRIVACY_LOCAL_USERNAME,
    [switch]$TrackedOnly,
    [switch]$MetadataOnly
)

$ErrorActionPreference = 'Stop'
$rootPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).Path).TrimEnd('\')
$patterns = [ordered]@{
    email = '(?i)(?<![A-Za-z0-9._%+\-])[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}(?![A-Za-z0-9._%+\-])'
    windows_profile_path = '(?i)\b[A-Z]:\\Users\\[^\\\s"''<>]+'
    unix_profile_path = '(?i)/(?:Users|home)/[^/\s"''<>]+'
    absolute_windows_path = '(?i)\b[A-Z]:\\(?:[^\\\s"''<>]+\\)+[^\\\s"''<>]*'
    private_ip = '(?<!\d)(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})(?!\d)'
    secret_or_auth = '(?i)(?:authorization\s*:\s*(?:bearer\s+)?\S+|\bbearer\s+[A-Za-z0-9._\-]+|(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|secret)\s*[=:]\s*[^\s,;]+)'
    private_key = '(?i)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'
}

$findings = [System.Collections.Generic.List[object]]::new()
if ($MetadataOnly) {
    $files = @()
}
elseif ($TrackedOnly) {
    $relativePaths = @(git -C $rootPath ls-files | ForEach-Object {
        ([string]$_).Trim([char]0xFEFF, [char]0x0D, [char]0x0A, [char]0x20, [char]0x09)
    })
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate tracked files'
    }
    $files = @($relativePaths | ForEach-Object {
        Join-Path $rootPath $_
    })
}
else {
    $files = @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force)
}
$textFileCount = 0

foreach ($file in $files) {
    if ($TrackedOnly) {
        $fullName = [string]$file
        if (-not [System.IO.File]::Exists($fullName)) {
            throw 'Tracked file is missing'
        }
    }
    else {
        $fullName = $file.FullName
    }

    $relative = [System.IO.Path]::GetRelativePath($rootPath, $fullName).Replace('\', '/')
    if ($relative -like '.git/*' -or $relative -eq '.git' -or
        $relative -like 'build/*') {
        continue
    }

    $bytes = [System.IO.File]::ReadAllBytes($fullName)
    if ($bytes -contains [byte]0) {
        continue
    }

    try {
        $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    }
    catch {
        continue
    }

    $textFileCount++
    $lines = $text -split '\r?\n'
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = $lines[$lineIndex]
        foreach ($category in $patterns.Keys) {
            foreach ($match in [regex]::Matches($line, $patterns[$category])) {
                if ($category -eq 'email' -and
                    $match.Value -match '(?i)@users\.noreply\.github\.com$') {
                    continue
                }
                $findings.Add([pscustomobject]@{
                    File = $relative
                    Line = $lineIndex + 1
                    Category = $category
                })
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($DisallowedUsername) -and
            $line.IndexOf($DisallowedUsername, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $findings.Add([pscustomobject]@{
                File = $relative
                Line = $lineIndex + 1
                Category = 'configured_local_username'
            })
        }
    }
}

if ($MetadataOnly) {
    $metadataFindings = [System.Collections.Generic.List[object]]::new()

    function Get-MetadataRefIdentifier {
        param([string]$Value)

        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $digest = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value))
            return ([System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant())
        }
        finally {
            $hasher.Dispose()
        }
    }

    function Add-MetadataFinding {
        param(
            [string]$Identifier,
            [string]$Category
        )

        $metadataFindings.Add([pscustomobject]@{
            Identifier = $Identifier
            Category = $Category
        }) | Out-Null
    }

    function Add-MetadataText {
        param(
            [string]$Text,
            [string]$Identifier,
            [string]$Context
        )

        foreach ($line in ($Text -split '\r?\n')) {
            foreach ($category in $patterns.Keys) {
                foreach ($match in [regex]::Matches($line, $patterns[$category])) {
                    if ($category -eq 'email' -and
                        $match.Value -match '(?i)@users\.noreply\.github\.com$') {
                        continue
                    }
                    Add-MetadataFinding -Identifier $Identifier -Category ('{0}/{1}' -f $Context, $category)
                }
            }
        }
    }

    $reachableCommits = @(git -C $rootPath rev-list --all)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate reachable commits'
    }
    foreach ($commit in $reachableCommits) {
        $commitRaw = git -C $rootPath cat-file commit $commit 2>$null | Out-String
        $messageMatch = [regex]::Match($commitRaw, '\r?\n\r?\n([\s\S]*)$')
        if ($messageMatch.Success) {
            Add-MetadataText -Text $messageMatch.Groups[1].Value -Identifier ('commit:' + $commit) -Context 'commit_message'
        }
    }

    $branchRefs = @(git -C $rootPath for-each-ref --format='%(refname)' refs/heads refs/remotes)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate branch refs'
    }
    foreach ($branchRef in $branchRefs) {
        $identifier = 'ref-id:' + (Get-MetadataRefIdentifier ([string]$branchRef))
        Add-MetadataText -Text ([string]$branchRef) -Identifier $identifier -Context 'branch_name'
    }

    $tagRefs = @(git -C $rootPath for-each-ref --format='%(refname)%09%(objectname)' refs/tags)
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to enumerate tag refs'
    }
    $annotatedTagCount = 0
    foreach ($tagRef in $tagRefs) {
        $tagFields = ([string]$tagRef) -split ([char]9), 2
        if ($tagFields.Count -ne 2) {
            throw 'Unable to parse tag ref'
        }
        $tagName = [string]$tagFields[0]
        $tagObject = [string]$tagFields[1]
        $identifier = 'ref-id:' + (Get-MetadataRefIdentifier $tagName)
        Add-MetadataText -Text $tagName -Identifier $identifier -Context 'tag_name'

        $objectType = (git -C $rootPath cat-file -t $tagObject 2>$null).Trim()
        if ($objectType -ne 'tag') {
            continue
        }
        $annotatedTagCount++
        $tagRaw = git -C $rootPath cat-file tag $tagObject 2>$null | Out-String
        $tagHeader = ($tagRaw -split '\r?\n\r?\n', 2)[0]
        $taggerLine = @($tagHeader -split '\r?\n' | Where-Object { $_ -like 'tagger *' } | Select-Object -First 1)
        if ($taggerLine.Count -eq 1) {
            $taggerMatch = [regex]::Match([string]$taggerLine[0], '^tagger (.*) <([^>]*)> \d+ [+-]\d+$')
            if (-not $taggerMatch.Success) {
                Add-MetadataFinding -Identifier $identifier -Category 'annotated_tag_tagger_identity'
            }
            else {
                $taggerName = $taggerMatch.Groups[1].Value
                $taggerEmail = $taggerMatch.Groups[2].Value
                if ($taggerName -cne 'piuteu' -or $taggerEmail -cne 'piuteu@users.noreply.github.com') {
                    Add-MetadataFinding -Identifier $identifier -Category 'annotated_tag_tagger_identity'
                }
                Add-MetadataText -Text ([string]$taggerLine[0]) -Identifier $identifier -Context 'annotated_tag_tagger'
            }
        }
        $tagMessageMatch = [regex]::Match($tagRaw, '\r?\n\r?\n([\s\S]*)$')
        if ($tagMessageMatch.Success) {
            Add-MetadataText -Text $tagMessageMatch.Groups[1].Value -Identifier $identifier -Context 'annotated_tag_message'
        }
    }

    if ($metadataFindings.Count -gt 0) {
        foreach ($finding in $metadataFindings) {
            'METADATA_FINDING ref_id={0} category={1} status=FAIL' -f $finding.Identifier, $finding.Category
        }
        'GIT_METADATA_PRIVACY_CHECK_FAIL findings={0}' -f $metadataFindings.Count
        exit 1
    }

    'GIT_METADATA_PRIVACY_CHECK_PASS reachable_commits={0} branches={1} tags={2} annotated_tags={3}' -f $reachableCommits.Count, $branchRefs.Count, $tagRefs.Count, $annotatedTagCount
    exit 0
}

if ($findings.Count -gt 0) {
    foreach ($finding in $findings) {
        'PII_FINDING file={0} line={1} category={2} sanitized=no' -f $finding.File, $finding.Line, $finding.Category
    }
    exit 1
}

'PRIVACY_CHECK_PASS text_files={0}' -f $textFileCount
