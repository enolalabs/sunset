<#
.SYNOPSIS
    Run smoke tests against a sunset executable.

.DESCRIPTION
    smoke.ps1 -Executable <path> -Version <version> -Fixture <path> -OutputDir <path>

    Writes diagnostics ONLY to stderr (Write-Host -ForegroundColor Red / $env:stderr).
    Exits zero WITHOUT stdout on success.
    Exits non-zero WITH diagnostics on failure.

    The smoke contract (design spec Section 4.3):
      1. sunset version exits zero and prints exact version.
      2. sunset languages exits zero and lists Go, JavaScript, TypeScript, Python.
      3. sunset parse --no-cache --quiet --output <temp> <fixture> exits zero.
      4. Output contains index.md and at least one files/*.md.
      5. index.md contains sunset_version: <exact-version>.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$Fixture,
    [Parameter(Mandatory=$true)][string]$OutputDir
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    [Console]::Error.WriteLine("smoke: $Message")
    exit 1
}

# --- Argument validation ---

if (-not (Test-Path $Executable -PathType Leaf)) {
    Fail "executable not found: $Executable"
}
if (-not (Test-Path $Fixture -PathType Container)) {
    Fail "fixture directory not found: $Fixture"
}
if (-not (Test-Path $OutputDir -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    } catch {
        Fail "cannot create output directory: $OutputDir"
    }
}

$requiredLangs = @("go", "javascript", "typescript", "python")

# 1. sunset version -> exits zero, prints exact version
$versionResult = & $Executable version 2>&1
$versionExit = $LASTEXITCODE
if ($versionExit -ne 0) {
    Fail "'sunset version' exited non-zero ($versionExit): $versionResult"
}
$versionLine = ($versionResult | Out-String).Trim()
$expected = "sunset $Version"
if ($versionLine -ne $expected) {
    Fail "version mismatch: expected '$expected', got '$versionLine'"
}

# 2. sunset languages -> exits zero, lists all four languages
$langsResult = & $Executable languages 2>&1
$langsExit = $LASTEXITCODE
if ($langsExit -ne 0) {
    Fail "'sunset languages' exited non-zero ($langsExit): $langsResult"
}
$langsText = ($langsResult | Out-String)
foreach ($lang in $requiredLangs) {
    if ($langsText -notmatch "(?i)\b$lang\b") {
        Fail "language '$lang' not found in 'sunset languages' output"
    }
}

# 3. sunset parse --no-cache --quiet --output <temp> <fixture>
$parseTmp = Join-Path $OutputDir "smoke_$(Get-Random)"
New-Item -ItemType Directory -Path $parseTmp -Force | Out-Null

$parseResult = & $Executable parse --no-cache --quiet --output $parseTmp $Fixture 2>&1
$parseExit = $LASTEXITCODE
if ($parseExit -ne 0) {
    Remove-Item -Recurse -Force $parseTmp -ErrorAction SilentlyContinue
    Fail "'sunset parse' exited non-zero ($parseExit): $parseResult"
}

# 4. Output contains index.md and at least one files/*.md
$indexPath = Join-Path $parseTmp "index.md"
if (-not (Test-Path $indexPath -PathType Leaf)) {
    Remove-Item -Recurse -Force $parseTmp -ErrorAction SilentlyContinue
    Fail "index.md not found in parse output"
}

$filesDir = Join-Path $parseTmp "files"
$fileMd = Get-ChildItem -Path $filesDir -Filter "*.md" -ErrorAction SilentlyContinue
if (-not $fileMd -or $fileMd.Count -eq 0) {
    Remove-Item -Recurse -Force $parseTmp -ErrorAction SilentlyContinue
    Fail "no files/*.md found in parse output"
}

# 5. index.md contains sunset_version: <exact-version>
$indexContent = Get-Content $indexPath -Raw
$versionPattern = "(?m)^sunset_version: " + [regex]::Escape($Version) + "$"
if ($indexContent -notmatch $versionPattern) {
    Remove-Item -Recurse -Force $parseTmp -ErrorAction SilentlyContinue
    Fail "index.md does not contain 'sunset_version: $Version'"
}

Remove-Item -Recurse -Force $parseTmp -ErrorAction SilentlyContinue
exit 0
