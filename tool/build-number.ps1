# Bumps build_number.txt by 1 and prints the new value.
# PowerShell twin of tool/build-number.sh — see that file for the full notes.
#
#   flutter build appbundle --build-number=$(./tool/build-number.ps1)
#
$ErrorActionPreference = "Stop"

$file = Join-Path $PSScriptRoot "..\build_number.txt"

$current = 0
if (Test-Path $file) {
    $raw = (Get-Content $file -Raw) -replace '[^0-9]', ''
    if ($raw) { $current = [int]$raw }
}

$next = $current + 1
Set-Content -Path $file -Value $next -Encoding utf8 -NoNewline
Write-Output $next
