param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^\d+\.\d+\.\d+$')]
  [string]$Version,
  [string]$BuildDir = "build/windows/x64/runner/Release",
  [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDir = Join-Path $projectRoot $BuildDir
$outputPath = Join-Path $projectRoot $OutputDir
$scriptPath = Join-Path $PSScriptRoot "SmartStore.iss"
$iconPath = Join-Path $projectRoot "windows/runner/resources/app_icon.ico"

foreach ($requiredPath in @(
  (Join-Path $releaseDir "smart_store.exe"),
  (Join-Path $releaseDir "flutter_windows.dll"),
  (Join-Path $releaseDir "data"),
  $iconPath
)) {
  if (-not (Test-Path $requiredPath)) {
    throw "Required release file not found: $requiredPath. Build with 'flutter build windows --release' first."
  }
}

$compilerCommand = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
$compiler = if ($compilerCommand) { $compilerCommand.Source } else { $null }
if (-not $compiler) {
  $candidates = @()
  if ($env:ProgramFiles) {
    $candidates += Join-Path $env:ProgramFiles "Inno Setup 6/ISCC.exe"
  }
  if (${env:ProgramFiles(x86)}) {
    $candidates += Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6/ISCC.exe"
  }
  $compiler = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $compiler) {
  throw "Inno Setup 6 was not found. Install it from https://jrsoftware.org/isinfo.php, then rerun this script."
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
& $compiler `
  "/DAppVersion=$Version" `
  "/DBuildDir=$releaseDir" `
  "/DOutputDir=$outputPath" `
  "/DAppIconFile=$iconPath" `
  $scriptPath
if ($LASTEXITCODE -ne 0) {
  throw "Inno Setup failed with exit code $LASTEXITCODE."
}

Write-Output "Installer: $(Join-Path $outputPath "SmartStore-Setup-$Version.exe")"