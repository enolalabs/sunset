<#
.SYNOPSIS
    PowerShell test suite for the native release helpers (Windows).

.DESCRIPTION
    test-helpers.ps1 — mirrors the POSIX test suite for Windows.

    This suite is designed to run on windows-2025 in the read-only pre-tag
    validation workflow (Task 5). It is NOT expected to pass on non-Windows
    platforms.

    Usage: pwsh -File .github/scripts/release/test-helpers.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..\..\..")
$Fixture = Join-Path $RepoRoot "testdata\go-sample"

$script:Pass = 0
$script:Fail = 0
$script:FailedNames = @()

function Test-Start([string]$Name) {
    Write-Host "  $Name ... " -NoNewline
    $script:CurrentName = $Name
}

function Test-OK() {
    Write-Host "OK"
    $script:Pass++
}

function Test-KO([string]$Detail = "") {
    Write-Host "FAIL"
    if ($Detail) { Write-Host "    $Detail" }
    $script:Fail++
    $script:FailedNames += $script:CurrentName
}

function Test-ExitZero([int]$ExitCode) {
    if ($ExitCode -eq 0) { Test-OK } else { Test-KO "exit $ExitCode" }
}

function Test-ExitNonZero([int]$ExitCode) {
    if ($ExitCode -ne 0) { Test-OK } else { Test-KO "expected non-zero, got 0" }
}

function Test-Empty([string]$Output) {
    if ([string]::IsNullOrWhiteSpace($Output)) { Test-OK } else { Test-KO "stdout not empty" }
}

function Test-OneLine([string]$Output) {
    $lines = ($Output -split "`n").Where({ $_ -ne "" })
    if ($lines.Count -eq 1) { Test-OK } else { Test-KO "stdout lines=$($lines.Count)" }
}

# ---------------------------------------------------------------------------
# Stub generator
# ---------------------------------------------------------------------------

function New-Stub {
    param(
        [string]$Path,
        [string]$Version = "1.0.1",
        [string[]]$Langs = @("go", "javascript", "typescript", "python"),
        [switch]$NoIndex,
        [switch]$NoFiles,
        [string]$IndexVersion = "",
        [switch]$NoExec
    )

    if ([string]::IsNullOrEmpty($IndexVersion)) {
        $IndexVersion = $Version
    }

    $exts = @{
        "go" = ".go"
        "javascript" = ".js, .jsx"
        "typescript" = ".ts, .tsx"
        "python" = ".py"
    }

    $lines = @(
        'param([string]$SubCmd, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest)'
        'switch ($SubCmd) {'
        '    "version" {'
        "        Write-Output 'sunset $Version'"
        '        exit 0'
        '    }'
        '    "languages" {'
        '        Write-Output "Supported languages:"'
        '        Write-Output ""'
        '        Write-Output "  Language        Extensions"'
        '        Write-Output "  --------        ----------"'
    )

    foreach ($lang in $Langs) {
        $ext = if ($exts.ContainsKey($lang)) { $exts[$lang] } else { ".txt" }
        $lines += '        Write-Output ("  {0,-15} {1}" -f "' + $lang + '", "' + $ext + '")'
    }

    $lines += @(
        '        exit 0'
        '    }'
        '    "parse" {'
        '        $outdir = $null'
        '        $fixture = $null'
        '        $i = 0'
        '        while ($i -lt $Rest.Count) {'
        '            switch ($Rest[$i]) {'
        '                "--output" { $outdir = $Rest[$i + 1]; $i += 2 }'
        '                "--no-cache" { $i++ }'
        '                "--quiet" { $i++ }'
        '                default { if (-not $fixture) { $fixture = $Rest[$i] }; $i++ }'
        '            }'
        '        }'
        '        if (-not (Test-Path $outdir)) { New-Item -ItemType Directory -Path $outdir -Force | Out-Null }'
        '        $filesDir = Join-Path $outdir "files"'
        '        New-Item -ItemType Directory -Path $filesDir -Force | Out-Null'
    )

    if (-not $NoIndex) {
        $lines += @(
            '        $indexContent = "---`nproject: sample`nsunset_version: ' + $IndexVersion + '`n---"'
            '        Set-Content -Path (Join-Path $outdir "index.md") -Value $indexContent'
        )
    }

    if (-not $NoFiles) {
        $lines += '        Set-Content -Path (Join-Path $filesDir "main.go.md") -Value "# main.go"'
    }

    $lines += @(
        '        exit 0'
        '    }'
        '    default {'
        '        [Console]::Error.WriteLine("unknown command: $SubCmd")'
        '        exit 1'
        '    }'
        '}'
    )

    $content = $lines -join "`n"
    Set-Content -Path $Path -Value $content -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------

$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) "sunset-test-$(Get-Random)"
New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

# ---------------------------------------------------------------------------
# SMOKE TESTS
# ---------------------------------------------------------------------------

function Invoke-SmokeTests {
    Write-Host ""
    Write-Host "=== Smoke helper tests ==="

    $goodStub = Join-Path $TestRoot "sunset-good.ps1"
    New-Stub -Path $goodStub -Version "1.0.1"

    $smokeOut = Join-Path $TestRoot "smoke-out"

    # 1. Success
    Test-Start "smoke: success path (good stub)"
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "smoke.ps1") -Executable $goodStub -Version "1.0.1" -Fixture $Fixture -OutputDir $smokeOut 2>&1
    Test-ExitZero $LASTEXITCODE

    Test-Start "smoke: no stdout on success"
    Test-Empty ($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String)

    # 2. Wrong version
    Test-Start "smoke: wrong version rejected"
    $badVer = Join-Path $TestRoot "sunset-wrong-ver.ps1"
    New-Stub -Path $badVer -Version "9.9.9"
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "smoke.ps1") -Executable $badVer -Version "1.0.1" -Fixture $Fixture -OutputDir $smokeOut 2>&1
    Test-ExitNonZero $LASTEXITCODE

    # 3. Missing language
    Test-Start "smoke: missing language rejected"
    $missingLang = Join-Path $TestRoot "sunset-missing-lang.ps1"
    New-Stub -Path $missingLang -Version "1.0.1" -Langs @("go", "javascript", "typescript")
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "smoke.ps1") -Executable $missingLang -Version "1.0.1" -Fixture $Fixture -OutputDir $smokeOut 2>&1
    Test-ExitNonZero $LASTEXITCODE

    # 4. Missing index.md
    Test-Start "smoke: missing index.md rejected"
    $noIndex = Join-Path $TestRoot "sunset-no-index.ps1"
    New-Stub -Path $noIndex -Version "1.0.1" -NoIndex
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "smoke.ps1") -Executable $noIndex -Version "1.0.1" -Fixture $Fixture -OutputDir $smokeOut 2>&1
    Test-ExitNonZero $LASTEXITCODE

    # 5. No per-file output
    Test-Start "smoke: no files/*.md rejected"
    $noFiles = Join-Path $TestRoot "sunset-no-files.ps1"
    New-Stub -Path $noFiles -Version "1.0.1" -NoFiles
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "smoke.ps1") -Executable $noFiles -Version "1.0.1" -Fixture $Fixture -OutputDir $smokeOut 2>&1
    Test-ExitNonZero $LASTEXITCODE

    # 6. Wrong sunset_version in index.md
    Test-Start "smoke: wrong sunset_version rejected"
    $badSv = Join-Path $TestRoot "sunset-bad-sv.ps1"
    New-Stub -Path $badSv -Version "1.0.1" -IndexVersion "0.0.1"
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "smoke.ps1") -Executable $badSv -Version "1.0.1" -Fixture $Fixture -OutputDir $smokeOut 2>&1
    Test-ExitNonZero $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# ARCHIVE VERIFY FUNCTION TESTS (mirror POSIX _sunset_pv_verify_archive tests)
# ---------------------------------------------------------------------------

function Invoke-VerifyTests {
    Write-Host ""
    Write-Host "=== Archive verify function tests ==="

    # Dot-source package-and-verify.ps1 to get Invoke-SunsetVerifyArchive
    . (Join-Path $ScriptDir "package-and-verify.ps1")

    # Helper to create a zip from a set of file paths
    function New-TestArchive {
        param([string]$ArchivePath, [string[]]$FilePaths)
        Compress-Archive -Path $FilePaths -DestinationPath $ArchivePath -Force
    }

    # 1. Verify accepts a valid archive
    Test-Start "verify: accepts valid archive"
    $stage1 = Join-Path $TestRoot "verify-stage1"
    New-Item -ItemType Directory -Path $stage1 -Force | Out-Null
    Set-Content -Path (Join-Path $stage1 "sunset.exe") -Value "stub" -Encoding ASCII
    $goodZip = Join-Path $TestRoot "good.zip"
    New-TestArchive -ArchivePath $goodZip -FilePaths (Join-Path $stage1 "sunset.exe")
    $result = Invoke-SunsetVerifyArchive -ArchivePath $goodZip -ExpectedRoot "sunset.exe" 2>$null
    if ($result) { Test-OK } else { Test-KO "valid archive rejected" }

    # 2. Verify rejects malformed archive
    Test-Start "verify: rejects malformed archive"
    $malformedZip = Join-Path $TestRoot "malformed.zip"
    Set-Content -Path $malformedZip -Value "this is not a zip file" -Encoding ASCII
    $result = Invoke-SunsetVerifyArchive -ArchivePath $malformedZip -ExpectedRoot "sunset.exe" 2>$null
    if (-not $result) { Test-OK } else { Test-KO "malformed archive accepted" }

    # 3. Verify rejects extra root entry
    Test-Start "verify: rejects extra root entry"
    $stage2 = Join-Path $TestRoot "verify-stage2"
    New-Item -ItemType Directory -Path $stage2 -Force | Out-Null
    Set-Content -Path (Join-Path $stage2 "sunset.exe") -Value "stub" -Encoding ASCII
    Set-Content -Path (Join-Path $stage2 "extra.txt") -Value "extra" -Encoding ASCII
    $extraZip = Join-Path $TestRoot "extra.zip"
    New-TestArchive -ArchivePath $extraZip -FilePaths @((Join-Path $stage2 "sunset.exe"), (Join-Path $stage2 "extra.txt"))
    $result = Invoke-SunsetVerifyArchive -ArchivePath $extraZip -ExpectedRoot "sunset.exe" 2>$null
    if (-not $result) { Test-OK } else { Test-KO "extra root entry accepted" }

    # 4. Verify rejects wrong root entry name
    Test-Start "verify: rejects wrong root entry name"
    $stage3 = Join-Path $TestRoot "verify-stage3"
    New-Item -ItemType Directory -Path $stage3 -Force | Out-Null
    Set-Content -Path (Join-Path $stage3 "wrongname.exe") -Value "stub" -Encoding ASCII
    $wrongZip = Join-Path $TestRoot "wrongname.zip"
    New-TestArchive -ArchivePath $wrongZip -FilePaths (Join-Path $stage3 "wrongname.exe")
    $result = Invoke-SunsetVerifyArchive -ArchivePath $wrongZip -ExpectedRoot "sunset.exe" 2>$null
    if (-not $result) { Test-OK } else { Test-KO "wrong root entry name accepted" }
}

# ---------------------------------------------------------------------------
# PACKAGE-AND-VERIFY TESTS
# ---------------------------------------------------------------------------

function Invoke-PackageTests {
    Write-Host ""
    Write-Host "=== Package-and-verify helper tests ==="

    $archiveDir = Join-Path $TestRoot "archives1"

    # Build a real Windows binary for the package test. A PowerShell stub
    # renamed to .exe cannot be executed directly on Windows, so we use
    # go build to create a real PE binary with the expected version.
    Write-Host "  building test binary ..."
    $realExe = Join-Path $TestRoot "sunset.exe"
    $buildOut = & go build -trimpath -ldflags "-s -w -X github.com/enolalabs/sunset/internal/version.BuildVersion=1.0.1" -o $realExe ./cmd/sunset/ 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  go build failed:" $buildOut
        exit 1
    }

    # 1. Full success path
    Test-Start "package: full success path prints one archive path"
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "package-and-verify.ps1") -Executable $realExe -Version "1.0.1" -Fixture $Fixture -ArchiveOutputDir $archiveDir 2>&1
    Test-ExitZero $LASTEXITCODE

    Test-Start "package: stdout is exactly one line"
    Test-OneLine ($out | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | Out-String)

    # 2. Failure path removes archive
    Test-Start "package: failure leaves no archive behind"
    $badStub = Join-Path $TestRoot "sunset-fail-pkg.ps1"
    New-Stub -Path $badStub -Version "9.9.9"
    $badArchiveDir = Join-Path $TestRoot "archives2"
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "package-and-verify.ps1") -Executable $badStub -Version "1.0.1" -Fixture $Fixture -ArchiveOutputDir $badArchiveDir 2>&1
    Test-ExitNonZero $LASTEXITCODE

    # 3. Missing executable
    Test-Start "package: missing executable rejected"
    $out = & pwsh -NoProfile -File (Join-Path $ScriptDir "package-and-verify.ps1") -Executable (Join-Path $TestRoot "nonexistent") -Version "1.0.1" -Fixture $Fixture -ArchiveOutputDir (Join-Path $TestRoot "archives3") 2>&1
    Test-ExitNonZero $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host "Release helper test suite (PowerShell)"
Write-Host "TEST_ROOT: $TestRoot"
Write-Host "FIXTURE:   $Fixture"

Invoke-SmokeTests
Invoke-VerifyTests
Invoke-PackageTests

Write-Host ""
Write-Host "==========================================="
Write-Host "Results: $script:Pass passed, $script:Fail failed"
if ($script:Fail -gt 0) {
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($t in $script:FailedNames) {
        Write-Host "  - $t"
    }
    exit 1
}
Write-Host "All tests passed."
exit 0
