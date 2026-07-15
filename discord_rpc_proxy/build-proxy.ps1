[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Write-Step {
  param([string]$Message)
  Write-Host "[ATLAS Discord RPC] $Message" -ForegroundColor Cyan
}

function Find-VsWhere {
  $candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"),
    (Join-Path $env:ProgramFiles "Microsoft Visual Studio\Installer\vswhere.exe")
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  return $null
}

function Find-VsDevCmd {
  $vswhere = Find-VsWhere
  if (-not $vswhere) {
    return $null
  }

  $installationPath = & $vswhere `
    -latest `
    -products * `
    -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath

  if ($LASTEXITCODE -ne 0 -or -not $installationPath) {
    return $null
  }

  $installationPath = [string](@($installationPath) | Select-Object -First 1)
  $candidates = @(
    (Join-Path $installationPath "Common7\Tools\VsDevCmd.bat"),
    (Join-Path $installationPath "VC\Auxiliary\Build\vcvars64.bat")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

function Get-LauncherVersion {
  param([string]$VersionSource)

  if (-not (Test-Path $VersionSource)) {
    return "unknown"
  }

  $match = Select-String `
    -Path $VersionSource `
    -Pattern "static\s+const\s+String\s+_launcherVersion\s*=\s*'([^']+)'" `
    -List

  if ($match -and $match.Matches.Count -gt 0) {
    return $match.Matches[0].Groups[1].Value
  }

  return "unknown"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$buildDir = Join-Path $scriptDir "build"
$sourceFile = Join-Path $scriptDir "discord_rpc_proxy.cpp"
$defFile = Join-Path $scriptDir "discord-rpc.def"
$outputDll = Join-Path $buildDir "discord-rpc.dll"
$assetDll = Join-Path $repoRoot "atlas_link_flutter\assets\dlls\discord-rpc.dll"
$versionSource = Join-Path $repoRoot "atlas_link_flutter\lib\main.dart"
$launcherVersion = Get-LauncherVersion -VersionSource $versionSource
$escapedLauncherVersion = $launcherVersion.Replace("\", "\\").Replace('"', '\"')

if (-not (Test-Path $sourceFile)) {
  throw "Source file not found: $sourceFile"
}

if (-not (Test-Path $defFile)) {
  throw "DEF file not found: $defFile"
}

New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $assetDll -Parent) | Out-Null

function Quote-CmdArgument {
  param([string]$Value)
  return '"' + $Value.Replace('"', '\"') + '"'
}

Write-Step "Building discord-rpc.dll for launcher version $launcherVersion"
Remove-Item -LiteralPath $outputDll -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $buildDir "discord_rpc_proxy.dll") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $buildDir "discord_rpc_proxy.rsp") -Force -ErrorAction SilentlyContinue

$clCommand = Get-Command cl.exe -ErrorAction SilentlyContinue
$vsDevCmd = $null
if (-not $clCommand) {
  $vsDevCmd = Find-VsDevCmd
  if (-not $vsDevCmd) {
    throw "cl.exe was not found and Visual Studio C++ Build Tools could not be located. Install Visual Studio 2022/2026 with the Desktop development with C++ workload."
  }
}

$defineArg = '/D"ATLAS_LAUNCHER_VERSION=\"' + $escapedLauncherVersion + '\""'
$compileLine = @(
  "cl.exe",
  "/nologo",
  "/std:c++17",
  "/O2",
  "/MT",
  "/EHsc",
  "/LD",
  $defineArg,
  (Quote-CmdArgument $sourceFile),
  "/link",
  ("/DEF:" + (Quote-CmdArgument $defFile)),
  ("/OUT:" + (Quote-CmdArgument $outputDll)),
  "/MACHINE:X64"
) -join " "

$buildCommand = Join-Path $buildDir "build-discord-rpc.cmd"
$batchLines = @("@echo off", "setlocal")
if ($vsDevCmd) {
  $batchLines += "call $(Quote-CmdArgument $vsDevCmd) -arch=x64 -host_arch=x64"
  $batchLines += "if errorlevel 1 exit /b %errorlevel%"
}
$batchLines += $compileLine
$batchLines += "exit /b %errorlevel%"
Set-Content -Path $buildCommand -Value $batchLines -Encoding ASCII

Push-Location $buildDir
try {
  & cmd.exe /d /s /c "`"$buildCommand`""
  if ($LASTEXITCODE -ne 0) {
    throw "cl.exe failed with exit code $LASTEXITCODE"
  }
} finally {
  Pop-Location
  Remove-Item -LiteralPath $buildCommand -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $outputDll)) {
  throw "Build finished without creating $outputDll"
}

Copy-Item -Path $outputDll -Destination $assetDll -Force
Write-Step "Built proxy DLL: $outputDll"
Write-Step "Copied to launcher assets: $assetDll"
