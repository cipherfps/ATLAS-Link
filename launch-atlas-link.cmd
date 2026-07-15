@echo off
setlocal

cd /d "%~dp0\atlas_link_flutter"

if not exist "pubspec.yaml" (
  echo [ATLAS-Link Flutter] pubspec.yaml not found in %cd%
  exit /b 1
)

if "%~1"=="" (
  set "MODE=run"
) else (
  set "MODE=%~1"
)

where flutter.bat >nul 2>nul
if errorlevel 1 (
  echo [ATLAS-Link Flutter] flutter.bat not found. Install Flutter and add it to PATH.
  exit /b 1
)

if /I "%MODE%"=="run" (
  echo [ATLAS-Link Flutter] Running on Windows desktop...
  call flutter.bat run -d windows
  exit /b %errorlevel%
)

if /I "%MODE%"=="build" (
  echo [ATLAS-Link Flutter] Building Discord RPC proxy DLL...
  call "%~dp0discord_rpc_proxy\build-proxy.cmd"
  if errorlevel 1 exit /b %errorlevel%

  echo [ATLAS-Link Flutter] Building embedded backend executables...
  powershell -ExecutionPolicy Bypass -File "tool\build_backend_exes.ps1"
  if errorlevel 1 exit /b %errorlevel%

  echo [ATLAS-Link Flutter] Building Windows release...
  call flutter.bat build windows
  if errorlevel 1 exit /b %errorlevel%

  if exist "..\update-notes.md" (
    copy /y "..\update-notes.md" "build\windows\x64\runner\Release\update-notes.md" >nul
    echo [ATLAS-Link Flutter] Included update-notes.md in release output.
  ) else (
    echo [ATLAS-Link Flutter] update-notes.md not found at repo root.
  )
  if exist "assets\backend" (
    if exist "build\windows\x64\runner\Release\data\flutter_assets\assets\backend" (
      rmdir /s /q "build\windows\x64\runner\Release\data\flutter_assets\assets\backend"
    )
    robocopy "assets\backend" "build\windows\x64\runner\Release\data\flutter_assets\assets\backend" /E /NFL /NDL /NJH /NJS /NP >nul
    if errorlevel 8 exit /b 1
    echo [ATLAS-Link Flutter] Included embedded backend assets in release output.
  )
  exit /b 0
)

if /I "%MODE%"=="analyze" (
  echo [ATLAS-Link Flutter] Running flutter analyze...
  call flutter.bat analyze
  exit /b %errorlevel%
)

echo.
echo Usage: launch-atlas-link.cmd [run^|build^|analyze]
echo   run     : start Flutter desktop app on Windows (default)
echo   build   : build Windows release output
echo   analyze : run static analysis
exit /b 1
