$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

Write-Host "Installing Flutter packages and running checks..." -ForegroundColor Cyan
flutter pub get
flutter analyze
flutter test

Write-Host "Building Windows 64-bit release..." -ForegroundColor Cyan
flutter build windows --release

$IsccPaths = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)
$Iscc = $IsccPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $Iscc) {
    throw "Inno Setup 6 (ISCC.exe) not found. Install from https://jrsoftware.org/isdl.php and re-run this script."
}

New-Item -ItemType Directory -Force -Path dist | Out-Null
Write-Host "Compiling WhatIsThatSetup.exe..." -ForegroundColor Cyan
& $Iscc "installer\whatisthat.iss"

Write-Host "Done! Shareable installer created at: $RootDir\dist\WhatIsThatSetup.exe" -ForegroundColor Green
