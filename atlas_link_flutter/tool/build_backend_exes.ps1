[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutputDir = Join-Path $ProjectRoot "assets\backend\bin"
$WrapperSource = Join-Path $ProjectRoot "tool\backend_wrapper.dart"

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Push-Location $ProjectRoot
try {
  dart compile exe $WrapperSource -DATLAS_BACKEND_ID=lawinserver -o (Join-Path $OutputDir "atlas_lawinserver.exe")
  dart compile exe $WrapperSource -DATLAS_BACKEND_ID=neonite_v2 -o (Join-Path $OutputDir "atlas_neonitev2.exe")
} finally {
  Pop-Location
}
