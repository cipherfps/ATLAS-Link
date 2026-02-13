[CmdletBinding()]
param(
  [switch]$SkipFlutterBuild,
  [switch]$SkipInnoCompile
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[ATLAS-Link Installer] $Message" -ForegroundColor Cyan
}

function Find-Iscc {
  $isccCommand = Get-Command iscc -ErrorAction SilentlyContinue
  $isccFromPath = $null
  if ($isccCommand) {
    $isccFromPath = $isccCommand.Source
  }
  if ($isccFromPath) {
    return $isccFromPath
  }

  $candidates = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 5\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 5\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 5\ISCC.exe")
  ) | Where-Object { $_ -and (Test-Path $_) }

  $firstCandidate = @($candidates) | Select-Object -First 1
  if ($firstCandidate) {
    return [string]$firstCandidate
  }

  return $null
}

function Get-PubspecVersion {
  param([string]$PubspecPath)
  $line = Get-Content $PubspecPath | Where-Object { $_ -match '^\s*version:\s*' } | Select-Object -First 1
  if (-not $line) {
    throw "Could not find version in $PubspecPath"
  }

  $rawVersion = ($line -replace '^\s*version:\s*', '').Trim()
  if ($rawVersion -match '^[0-9]+\.[0-9]+\.[0-9]+') {
    return $Matches[0]
  }

  throw "Invalid pubspec version format: $rawVersion"
}

function Get-ReleaseExecutableName {
  param([string]$ReleaseDir)
  $exe = Get-ChildItem -Path $ReleaseDir -Filter *.exe -File |
    Where-Object { $_.Name -notmatch '^unins[0-9]*\.exe$' } |
    Sort-Object Length -Descending |
    Select-Object -First 1

  if (-not $exe) {
    throw "No executable found in $ReleaseDir"
  }

  return $exe.Name
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$flutterDir = Join-Path $repoRoot "atlas_link_flutter"
$pubspecPath = Join-Path $flutterDir "pubspec.yaml"
$releaseDir = Join-Path $flutterDir "build\windows\x64\runner\Release"
$installerScript = Join-Path $scriptDir "ATLAS-Link.iss"
$distDir = Join-Path $repoRoot "dist"
$setupIcon = Join-Path $flutterDir "windows\runner\resources\app_icon.ico"
$updateNotes = Join-Path $repoRoot "update-notes.md"

if (-not (Test-Path $pubspecPath)) {
  throw "Flutter project not found at $flutterDir"
}

if (-not (Test-Path $installerScript)) {
  throw "Installer script not found at $installerScript"
}

if (-not (Test-Path $distDir)) {
  New-Item -ItemType Directory -Path $distDir | Out-Null
}

$version = Get-PubspecVersion -PubspecPath $pubspecPath
Write-Step "Resolved app version: $version"

if (-not $SkipFlutterBuild) {
  Write-Step "Running flutter build windows --release"
  Push-Location $flutterDir
  try {
    flutter build windows --release
  }
  finally {
    Pop-Location
  }
}
else {
  Write-Step "Skipping Flutter build (using existing Release output)"
}

if (-not (Test-Path $releaseDir)) {
  throw "Release output not found at $releaseDir"
}

if (Test-Path $updateNotes) {
  Copy-Item -Path $updateNotes -Destination (Join-Path $releaseDir "update-notes.md") -Force
  Write-Step "Copied update-notes.md into release output"
}

$executableName = Get-ReleaseExecutableName -ReleaseDir $releaseDir
Write-Step "Found executable: $executableName"

# Keep end-user naming consistent in the installed folder.
$desiredExecutableName = "ATLAS Link.exe"
if ($executableName -ne $desiredExecutableName) {
  $sourceExecutablePath = Join-Path $releaseDir $executableName
  $desiredExecutablePath = Join-Path $releaseDir $desiredExecutableName
  if (Test-Path $desiredExecutablePath) {
    Remove-Item -Path $desiredExecutablePath -Force
  }
  Rename-Item -Path $sourceExecutablePath -NewName $desiredExecutableName
  $executableName = $desiredExecutableName
  Write-Step "Renamed release executable to: $executableName"
}
else {
  Write-Step "Using executable: $executableName"
}

$outputBaseFilename = "ATLAS Link Setup-$version"

if ($SkipInnoCompile) {
  Write-Step "Skipping Inno compilation. Release output is ready at $releaseDir"
  exit 0
}

$isccPath = Find-Iscc
if (-not $isccPath) {
  throw @"
Inno Setup compiler (ISCC.exe) was not found.
Install Inno Setup 6 from https://jrsoftware.org/isinfo.php and rerun:
  .\installer\build-installer.ps1
"@
}

Write-Step "Compiling installer with ISCC: $isccPath"

$isccArgs = @(
  "/DMyAppVersion=$version",
  "/DSourceDir=$releaseDir",
  "/DExecutableName=$executableName",
  "/DOutputDir=$distDir",
  "/DOutputBaseFilename=$outputBaseFilename"
)

if (Test-Path $setupIcon) {
  $isccArgs += "/DSetupIconFile=$setupIcon"
}

$isccArgs += $installerScript

& $isccPath @isccArgs
if ($LASTEXITCODE -ne 0) {
  throw "ISCC failed with exit code $LASTEXITCODE"
}

$installerPath = Join-Path $distDir "$outputBaseFilename.exe"
if (Test-Path $installerPath) {
  Write-Step "Installer created: $installerPath"
}
else {
  Write-Step "Installer compilation finished. Check output directory: $distDir"
}
