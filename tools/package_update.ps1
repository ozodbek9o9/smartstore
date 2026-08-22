param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$BuildDir = "build/windows/x64/runner/Release",
  [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"
$packageRoot = Join-Path $OutputDir "package"
$archive = Join-Path $OutputDir "SmartStore-$Version.zip"

if (-not (Test-Path (Join-Path $BuildDir "smart_store.exe"))) {
  throw "Release build not found: $BuildDir"
}

Remove-Item $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $archive -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $packageRoot "app") -Force | Out-Null

Get-ChildItem $BuildDir -Force | Where-Object {
  $_.Name -ne "user_data"
} | ForEach-Object {
  Copy-Item $_.FullName (Join-Path (Join-Path $packageRoot "app") $_.Name) -Recurse -Force
}

Compress-Archive -Path (Join-Path $packageRoot "app") -DestinationPath $archive -CompressionLevel Optimal
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
$size = (Get-Item $archive).Length
Write-Output "Package: $archive"
Write-Output "SHA256:  $hash"
Write-Output "Size:    $size"
Write-Output "Update version.json with downloadUrl, sha256, and sizeBytes."
