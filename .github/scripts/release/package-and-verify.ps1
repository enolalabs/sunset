<#
.SYNOPSIS
    Package a sunset executable into a verified zip archive.

.DESCRIPTION
    package-and-verify.ps1 -Executable <path> -Version <version> -Fixture <path> -ArchiveOutputDir <path>

    Creates the archive sunset_<version>_windows_<arch>.zip in the output dir,
    verifies archive integrity (single root entry 'sunset.exe', executable),
    runs the PowerShell smoke helper, and prints ONLY the absolute verified
    archive path to stdout.

    On failure, exits non-zero with diagnostics on stderr and removes any
    partially-created archive.

    The Invoke-SunsetVerifyArchive function is dot-sourceable for unit testing
    (see test-helpers.ps1).
#>
[CmdletBinding()]
param(
    [string]$Executable = "",
    [string]$Version = "",
    [string]$Fixture = "",
    [string]$ArchiveOutputDir = ""
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    [Console]::Error.WriteLine("package-and-verify: $Message")
}

# ---------------------------------------------------------------------------
# Invoke-SunsetVerifyArchive — Sourceable verification, mirrors the POSIX
# _sunset_pv_verify_archive function.
#
#   Invoke-SunsetVerifyArchive -ArchivePath <path> -ExpectedRoot <name>
#
# Returns $true if the archive is valid, $false otherwise.
# Diagnostics go to stderr.
# ---------------------------------------------------------------------------
function Invoke-SunsetVerifyArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ArchivePath,
        [Parameter(Mandatory=$true)][string]$ExpectedRoot
    )

    if (-not (Test-Path $ArchivePath -PathType Leaf)) {
        [Console]::Error.WriteLine("verify: archive not found: $ArchivePath")
        return $false
    }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    } catch {
        [Console]::Error.WriteLine("verify: malformed or corrupt archive: $ArchivePath")
        return $false
    }
    try {
        $rootEntries = @()
        foreach ($entry in $zip.Entries) {
            $root = ($entry.FullName -split "[/\\]")[0]
            if ($root -and $rootEntries -notcontains $root) {
                $rootEntries += $root
            }
        }

        if ($rootEntries.Count -ne 1) {
            [Console]::Error.WriteLine("verify: expected exactly 1 root entry, found $($rootEntries.Count): $($rootEntries -join ', ')")
            return $false
        }
        if ($rootEntries[0] -ne $ExpectedRoot) {
            [Console]::Error.WriteLine("verify: expected root entry '$ExpectedRoot', found '$($rootEntries[0])'")
            return $false
        }
        return $true
    } finally {
        $zip.Dispose()
    }
}

# ---------------------------------------------------------------------------
# Main — runs only when executed directly, not when dot-sourced for testing.
# ---------------------------------------------------------------------------
if ($MyInvocation.InvocationName -ne ".") {
    # Validate that all required params were provided
    if (-not $Executable -or -not $Version -or -not $Fixture -or -not $ArchiveOutputDir) {
        Fail "Usage: package-and-verify.ps1 -Executable <path> -Version <ver> -Fixture <path> -ArchiveOutputDir <dir>"
        exit 2
    }

    # Determine architecture from the environment
    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        "AMD64" { "amd64" }
        "ARM64" { "arm64" }
        default { "amd64" }
    }

    $archiveName = "sunset_${Version}_windows_${arch}.zip"
    $archivePath = Join-Path $ArchiveOutputDir $archiveName

    # --- Validate inputs ---

    if (-not (Test-Path $Executable -PathType Leaf)) {
        Fail "executable not found: $Executable"
        exit 2
    }
    if (-not (Test-Path $Fixture -PathType Container)) {
        Fail "fixture directory not found: $Fixture"
        exit 2
    }

    # Create output directory if needed
    if (-not (Test-Path $ArchiveOutputDir -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $ArchiveOutputDir -Force | Out-Null
        } catch {
            Fail "cannot create archive output dir: $ArchiveOutputDir"
            exit 2
        }
    }

    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

    # --- Stage: copy executable as 'sunset.exe' into a staging directory ---

    $stage = Join-Path ([System.IO.Path]::GetTempPath()) "sunset-pkg-$(Get-Random)"
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    try {
        Copy-Item $Executable (Join-Path $stage "sunset.exe") -Force

        # --- Create archive ---

        Compress-Archive -Path (Join-Path $stage "sunset.exe") -DestinationPath $archivePath -Force

        # --- Verify archive integrity ---

        if (-not (Invoke-SunsetVerifyArchive -ArchivePath $archivePath -ExpectedRoot "sunset.exe")) {
            Fail "archive verification failed"
            Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
            exit 1
        }

        # --- Extract and run smoke test ---

        $smokeTmp = Join-Path ([System.IO.Path]::GetTempPath()) "sunset-smoke-$(Get-Random)"
        New-Item -ItemType Directory -Path $smokeTmp -Force | Out-Null

        Expand-Archive -Path $archivePath -DestinationPath $smokeTmp -Force

        $smokeOut = Join-Path $smokeTmp "smoke-out"
        New-Item -ItemType Directory -Path $smokeOut -Force | Out-Null

        $smokeResult = & pwsh -NoProfile -File (Join-Path $scriptDir "smoke.ps1") `
            -Executable (Join-Path $smokeTmp "sunset.exe") `
            -Version $Version `
            -Fixture $Fixture `
            -OutputDir $smokeOut 2>&1

        $smokeExit = $LASTEXITCODE
        Remove-Item -Recurse -Force $smokeTmp -ErrorAction SilentlyContinue

        if ($smokeExit -ne 0) {
            Fail "smoke test failed on extracted binary: $smokeResult"
            Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
            exit 1
        }

        # --- Print ONLY the absolute verified archive path ---

        $absPath = (Resolve-Path $archivePath).Path
        Write-Output $absPath

        exit 0
    } catch {
        Fail "unexpected error: $_"
        Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
        exit 1
    } finally {
        Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
    }
}
