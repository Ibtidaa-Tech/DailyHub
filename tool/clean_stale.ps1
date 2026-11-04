# Removes Dart files left over from an older DailyHub release.
#
# Extracting a new zip over an old folder overwrites files with the same name
# but leaves behind ones that were deleted or renamed between versions — and
# those stale files still get compiled, so the build fails on code that isn't
# part of this release any more.
#
# Run this from the project root (the folder holding pubspec.yaml) AFTER
# extracting a new zip:
#
#     powershell -ExecutionPolicy Bypass -File .\tool\clean_stale.ps1
#
# Add -WhatIf to list what it would delete without deleting anything:
#
#     powershell -ExecutionPolicy Bypass -File .\tool\clean_stale.ps1 -WhatIf

param([switch]$WhatIf, [switch]$Force)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $PSScriptRoot 'release_manifest.txt'

if (-not (Test-Path $manifestPath)) {
    Write-Host "Can't find tool\release_manifest.txt - run this from the project root." -ForegroundColor Red
    exit 1
}

# Every .dart file this release ships, as forward-slash paths relative to root.
$expected = [System.Collections.Generic.HashSet[string]]::new(
    [string[]](Get-Content $manifestPath | Where-Object { $_.Trim() -ne '' }),
    [System.StringComparer]::OrdinalIgnoreCase)

$stale = @()
foreach ($folder in @('lib', 'test')) {
    $full = Join-Path $root $folder
    if (-not (Test-Path $full)) { continue }
    Get-ChildItem -Path $full -Recurse -File -Filter *.dart | ForEach-Object {
        $rel = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
        if (-not $expected.Contains($rel)) { $stale += $_ }
    }
}

if ($stale.Count -eq 0) {
    Write-Host "Clean - no leftover files from an older version." -ForegroundColor Green
    exit 0
}

Write-Host "Found $($stale.Count) file(s) left over from an older version:" -ForegroundColor Yellow
foreach ($f in $stale) {
    Write-Host ("  " + $f.FullName.Substring($root.Length + 1))
}

if ($WhatIf) {
    Write-Host "`n-WhatIf given, nothing deleted. Re-run without it to remove them." -ForegroundColor Cyan
    exit 0
}

if (-not $Force) {
    $answer = Read-Host "`nDelete these $($stale.Count) file(s)? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "Nothing deleted." -ForegroundColor Cyan
        exit 0
    }
}

foreach ($f in $stale) { Remove-Item -LiteralPath $f.FullName -Force }

# Drop any directories left empty behind them.
foreach ($folder in @('lib', 'test')) {
    $full = Join-Path $root $folder
    if (-not (Test-Path $full)) { continue }
    do {
        $empty = Get-ChildItem -Path $full -Recurse -Directory |
                 Where-Object { -not (Get-ChildItem -Path $_.FullName -Recurse -File) }
        $empty | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    } while ($empty)
}

Write-Host "`nRemoved $($stale.Count) stale file(s). Now run:" -ForegroundColor Green
Write-Host "  flutter clean; flutter pub get; flutter analyze"
