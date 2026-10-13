# Rewrites kAppVersion in lib/data/app_version.dart, and prints it.
# PowerShell twin of tool/sync-version.sh — see that file for the full notes.
#
#   ./tool/sync-version.ps1           # takes the version from pubspec.yaml
#   ./tool/sync-version.ps1 1.0.1     # takes the version given
#
param([string]$Version = "")

$ErrorActionPreference = "Stop"

$root = Join-Path $PSScriptRoot ".."
$dart = Join-Path $root "lib\data\app_version.dart"

if (-not $Version) {
    $line = Select-String -Path (Join-Path $root "pubspec.yaml") `
        -Pattern '^version:\s*(\S+)' | Select-Object -First 1
    if (-not $line) { throw "sync-version: no 'version:' line in pubspec.yaml." }
    $Version = $line.Matches[0].Groups[1].Value
}

$Version = ($Version -split '\+')[0]

if ($Version -notmatch '^[0-9]+(\.[0-9]+)*$') {
    throw "sync-version: '$Version' is not a dotted version."
}

$text = Get-Content $dart -Raw
if ($text -notmatch "(?m)^const kAppVersion = '") {
    throw "sync-version: no 'const kAppVersion = ...' line in $dart."
}

$text = [regex]::Replace($text, "(?m)^const kAppVersion = '.*';$",
    "const kAppVersion = '$Version';")
Set-Content -Path $dart -Value $text -Encoding utf8 -NoNewline

Write-Output $Version
