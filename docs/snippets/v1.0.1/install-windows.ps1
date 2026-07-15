# install-windows.ps1 — Install sunset v1.0.1 on Windows (amd64).
#
# Downloads ONLY the target archive plus checksums.txt, verifies the matching
# SHA-256 digest, extracts the archive, and runs `sunset version`.
#
# Defaults to the public v1.0.1 release URL.  Override the base URL for native
# pre-tag testing:
#
#   $env:SUNSET_BASE_URL = "http://127.0.0.1:8080"; .\install-windows.ps1
#
# SHA-256 detects corruption and byte mismatches.  It does NOT authenticate
# the publisher; signing and attestations remain future work.
$ErrorActionPreference = "Stop"

$Version    = "1.0.1"
$DefaultUrl = "https://github.com/enolalabs/sunset/releases/download/v$Version"
$BaseUrl    = if ($env:SUNSET_BASE_URL) { $env:SUNSET_BASE_URL } else { $DefaultUrl }
$Arch       = "amd64"

$Archive    = "sunset_${Version}_windows_${Arch}.zip"
$InstallDir = if ($env:SUNSET_INSTALL_DIR) { $env:SUNSET_INSTALL_DIR } else { "$env:LOCALAPPDATA\Programs\sunset" }

$Work = Join-Path $env:TEMP "sunset-install-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $Work -Force | Out-Null

try {
    Write-Host "==> Downloading $Archive and checksums.txt"
    Invoke-WebRequest -Uri "$BaseUrl/$Archive"      -OutFile "$Work\$Archive"      -UseBasicParsing
    Invoke-WebRequest -Uri "$BaseUrl/checksums.txt" -OutFile "$Work\checksums.txt" -UseBasicParsing

    Write-Host "==> Verifying SHA-256 (selecting the $Archive entry)"
    $line = Get-Content "$Work\checksums.txt" | Where-Object { $_ -like "*$Archive" }
    if (-not $line) { throw "no checksum entry for $Archive in checksums.txt" }
    $expected = ($line -split '\s+')[0].Trim()
    $actual   = (Get-FileHash -Algorithm SHA256 "$Work\$Archive").Hash
    if ($actual.ToLower() -ne $expected.ToLower()) {
        throw "checksum mismatch for $Archive (expected $expected, got $actual)"
    }

    Write-Host "==> Extracting and installing to $InstallDir"
    Expand-Archive -Path "$Work\$Archive" -DestinationPath $Work -Force
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Move-Item -Path "$Work\sunset.exe" -Destination "$InstallDir\sunset.exe" -Force

    Write-Host "==> Verifying install"
    & "$InstallDir\sunset.exe" version
}
finally {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}
