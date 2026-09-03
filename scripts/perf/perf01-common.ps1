Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Perf01AdbPath {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($env:PCFPS_ADB_PATH)) {
        [void]$candidates.Add($env:PCFPS_ADB_PATH)
    }
    foreach ($programFilesRoot in @($env:ProgramW6432, $env:ProgramFiles)) {
        if (-not [string]::IsNullOrWhiteSpace($programFilesRoot)) {
            [void]$candidates.Add((Join-Path $programFilesRoot 'BlueStacks_nxt\HD-Adb.exe'))
        }
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'BlueStacks ADB not found. Set PCFPS_ADB_PATH to <bluestacks-install-dir>\HD-Adb.exe.'
}

function Invoke-Perf01RemoteLines {
    param(
        [Parameter(Mandatory = $true)][string]$AdbPath,
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$Command
    )
    return @(& $AdbPath -s $Serial shell $Command 2>&1 | ForEach-Object { "$_" })
}

function Get-Perf01Serial {
    param(
        [Parameter(Mandatory = $true)][string]$AdbPath,
        [string]$PreferredSerial = ''
    )
    $lines = @(& $AdbPath devices 2>&1 | ForEach-Object { "$_" })
    $devices = @(
        foreach ($line in $lines) {
            if ($line -match '^\s*(\S+)\s+device\s*$') {
                $Matches[1]
            }
        }
    )
    if ($PreferredSerial -and ($devices -contains $PreferredSerial)) {
        return $PreferredSerial
    }
    if ($devices.Count -eq 0) {
        throw "No ADB serial is in the exact state 'device'. Output: $($lines -join ' | ')"
    }
    return $devices[0]
}

function Get-Perf01TargetPid {
    param(
        [Parameter(Mandatory = $true)][string]$AdbPath,
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$Package
    )
    $raw = (Invoke-Perf01RemoteLines -AdbPath $AdbPath -Serial $Serial -Command "pidof $Package") -join ' '
    $pids = @(
        foreach ($match in [regex]::Matches($raw, '\b\d+\b')) {
            [int]$match.Value
        }
    )
    if ($pids.Count -eq 0) {
        throw "Target process not found for $Package on $Serial"
    }
    return $pids[0]
}

function Get-Perf01UnitySurface {
    param(
        [Parameter(Mandatory = $true)][string]$AdbPath,
        [Parameter(Mandatory = $true)][string]$Serial,
        [Parameter(Mandatory = $true)][string]$Package
    )
    $lines = Invoke-Perf01RemoteLines -AdbPath $AdbPath -Serial $Serial -Command 'dumpsys SurfaceFlinger --list'
    $pattern = '^SurfaceView\[' + [regex]::Escape($Package) + '/com\.unity3d\.player\.UnityPlayerActivity\]\(BLAST\)#\d+$'
    $matches = @(
        foreach ($line in $lines) {
            $candidate = $line.Trim()
            if ($candidate -match $pattern) {
                $candidate
            }
        }
    )
    if ($matches.Count -eq 0) {
        throw "Unity BLAST surface not found for $Package"
    }
    return $matches[0]
}

function Get-Perf01HostUtc {
    return [DateTime]::UtcNow.ToString('o')
}

function Get-Perf01UnixMilliseconds {
    return [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
}

function Write-Perf01CsvRow {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Values
    )
    $fields = foreach ($value in $Values) {
        '"' + (("$value").Replace('"', '""')) + '"'
    }
    Add-Content -LiteralPath $Path -Value ($fields -join ',') -Encoding UTF8
}

function Write-Perf01SamplerError {
    param(
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$Sampler,
        [Parameter(Mandatory = $true)][object]$ErrorRecord
    )
    $line = (Get-Perf01HostUtc) + [char]9 + $Sampler + [char]9 + "$ErrorRecord"
    Add-Content -LiteralPath (Join-Path $OutputDirectory 'perf01_sampler_errors.log') -Value $line -Encoding UTF8
}

function Test-Perf01StopRequested {
    param([Parameter(Mandatory = $true)][string]$StopFile)
    return Test-Path -LiteralPath $StopFile -PathType Leaf
}
