[CmdletBinding()]
param(
  [switch]$SkipFlutterBuild,
  [switch]$SkipFlutterClean,
  [switch]$SkipInnoCompile
)

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[ATLAS-Link Installer] $Message" -ForegroundColor Cyan
}

function Stop-AtlasLinkProcesses {
  $names = @(
    'ATLAS Link',
    'atlas_link_flutter'
  )

  foreach ($name in $names) {
    try {
      $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
      foreach ($p in @($procs)) {
        Write-Step "Stopping running process: $($p.ProcessName) (pid $($p.Id))"
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
      }
    } catch {
      # Ignore failures (process may not exist / access denied).
    }
  }
}

function Remove-DirWithRetry {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [int]$Attempts = 6
  )

  if (-not (Test-Path $Path)) {
    return
  }

  for ($i = 1; $i -le $Attempts; $i++) {
    try {
      Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
      return
    } catch {
      if ($i -eq $Attempts) {
        Write-Step "Warning: failed to remove '$Path' after $Attempts attempts: $($_.Exception.Message)"
        return
      }
      Start-Sleep -Milliseconds (200 * $i)
    }
  }
}

function Remove-FileWithRetry {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [int]$Attempts = 6
  )

  if (-not (Test-Path $Path)) {
    return
  }

  for ($i = 1; $i -le $Attempts; $i++) {
    try {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      return
    } catch {
      if ($i -eq $Attempts) {
        Write-Step "Warning: failed to remove file '$Path' after $Attempts attempts: $($_.Exception.Message)"
        return
      }
      Start-Sleep -Milliseconds (200 * $i)
    }
  }
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

function Get-VcRedistPath {
  param([string]$ScriptDir)

  $repoCopy = Join-Path $ScriptDir "vc_redist.x64.exe"
  if (Test-Path $repoCopy) {
    $resolvedRepoCopy = Resolve-Path $repoCopy
    Write-Step "Using repository VC++ redistributable: $resolvedRepoCopy"
    return [string]$resolvedRepoCopy
  }

  $cacheDir = Join-Path $env:TEMP "ATLAS-Link"
  if (-not (Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
  }

  $cacheCopy = Join-Path $cacheDir "vc_redist.x64.exe"
  if (-not (Test-Path $cacheCopy)) {
    $url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    Write-Step "Downloading VC++ redistributable from $url"
    try {
      Invoke-WebRequest -Uri $url -OutFile $cacheCopy
    } catch {
      throw @"
Failed to download vc_redist.x64.exe from:
  $url

Either restore internet access and rerun the build, or place a local copy at:
  $repoCopy
"@
    }
  } else {
    Write-Step "Using cached VC++ redistributable: $cacheCopy"
  }

  if (-not (Test-Path $cacheCopy)) {
    throw "VC++ redistributable not found at $cacheCopy"
  }

  $size = (Get-Item -LiteralPath $cacheCopy).Length
  if ($size -lt 1048576) {
    throw "VC++ redistributable at $cacheCopy looks invalid (size: $size bytes)"
  }

  $resolvedCacheCopy = Resolve-Path $cacheCopy
  return [string]$resolvedCacheCopy
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
  if (-not $SkipFlutterClean) {
    Write-Step "Running flutter clean"

    # Release builds can fail to clean/rebuild if a previous app binary is
    # still running (or held by AV/indexers). Stop ATLAS Link and best-effort
    # remove common locked outputs before cleaning.
    Stop-AtlasLinkProcesses
    $releaseOutputDir = Join-Path $flutterDir 'build\windows\x64\runner\Release'
    Remove-FileWithRetry -Path (Join-Path $releaseOutputDir 'atlas_link_flutter.exe')
    Remove-FileWithRetry -Path (Join-Path $releaseOutputDir 'ATLAS Link.exe')

    Push-Location $flutterDir
    try {
      try {
        flutter clean
      } catch {
        Write-Step "flutter clean failed (likely locked files). Attempting to stop ATLAS Link and retry..."
        Stop-AtlasLinkProcesses
        Start-Sleep -Milliseconds 350
        try {
          flutter clean
        } catch {
          Write-Step "Warning: flutter clean still failed. Continuing build with manual cleanup attempts."
        }
      }
    }
    finally {
      Pop-Location
    }

    # Best-effort cleanup for common lock hotspots.
    Remove-DirWithRetry -Path (Join-Path $flutterDir 'build')
    Remove-DirWithRetry -Path (Join-Path $flutterDir '.dart_tool')
  }

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
#
# Note: Flutter build output is typically <pubspec name>.exe (atlas_link_flutter.exe).
# If we previously renamed it to "ATLAS Link.exe" and then built again, both files can
# exist and the renamed one may be stale. Prefer renaming the fresh Flutter output
# when present so the installer always packages the latest build.
$desiredExecutableName = "ATLAS Link.exe"
$desiredExecutablePath = Join-Path $releaseDir $desiredExecutableName
$flutterOutputExecutablePath = Join-Path $releaseDir "atlas_link_flutter.exe"

if (Test-Path $flutterOutputExecutablePath) {
  if (Test-Path $desiredExecutablePath) {
    Remove-Item -Path $desiredExecutablePath -Force
  }
  Rename-Item -Path $flutterOutputExecutablePath -NewName $desiredExecutableName
  $executableName = $desiredExecutableName
  Write-Step "Renamed Flutter output executable to: $executableName"
}
elseif ($executableName -ne $desiredExecutableName) {
  $sourceExecutablePath = Join-Path $releaseDir $executableName
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

# Ensure the installer doesn't accidentally package multiple app exes.
Get-ChildItem -Path $releaseDir -Filter *.exe -File |
  Where-Object {
    $_.Name -ne $desiredExecutableName -and
    $_.Name -notmatch '^unins[0-9]*\.exe$'
  } |
  ForEach-Object {
    Write-Step "Removing extra executable from release output: $($_.Name)"
    Remove-Item -Path $_.FullName -Force
  }

$outputBaseFilename = "ATLAS Link Setup-$version"

if ($SkipInnoCompile) {
  Write-Step "Skipping Inno compilation. Release output is ready at $releaseDir"
  exit 0
}

$vcRedistPath = Get-VcRedistPath -ScriptDir $scriptDir
Write-Step "Bundling VC++ redistributable: $vcRedistPath"

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
  "/DOutputBaseFilename=$outputBaseFilename",
  "/DVcRedistPath=$vcRedistPath"
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
