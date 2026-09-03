[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '..'),
    [string]$DisallowedUsername = $env:PCFPS_PRIVACY_LOCAL_USERNAME
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
$files = @(Get-ChildItem -LiteralPath $rootPath -Recurse -File -Force)
$textFileCount = 0

foreach ($file in $files) {
    $relative = [System.IO.Path]::GetRelativePath($rootPath, $file.FullName).Replace('\', '/')
    if ($relative -like '.git/*' -or $relative -eq '.git' -or
        $relative -like 'build/*') {
        continue
    }

    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
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

if ($findings.Count -gt 0) {
    foreach ($finding in $findings) {
        'PII_FINDING file={0} line={1} category={2} sanitized=no' -f $finding.File, $finding.Line, $finding.Category
    }
    exit 1
}

'PRIVACY_CHECK_PASS text_files={0}' -f $textFileCount
