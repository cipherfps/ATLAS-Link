@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "BUILD_DIR=%SCRIPT_DIR%build"
set "SOURCE_FILE=%SCRIPT_DIR%discord_rpc_proxy.cpp"
set "DEF_FILE=%SCRIPT_DIR%discord-rpc.def"
set "OUTPUT_DLL=%BUILD_DIR%\discord-rpc.dll"
set "ASSET_DLL=%SCRIPT_DIR%..\atlas_link_flutter\assets\dlls\discord-rpc.dll"
set "VERSION_SOURCE=%SCRIPT_DIR%..\atlas_link_flutter\lib\main.dart"
set "LAUNCHER_VERSION=unknown"

for /f "tokens=2 delims='" %%I in ('findstr /R /C:"_launcherVersion = '.*'" "%VERSION_SOURCE%"') do set "LAUNCHER_VERSION=%%I"

where cl >nul 2>nul
if errorlevel 1 (
  echo [ERROR] cl.exe not found.
  echo [ERROR] Run this from a Visual Studio Developer Command Prompt.
  exit /b 1
)

if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
pushd "%BUILD_DIR%"

cl /nologo /std:c++17 /O2 /MT /EHsc /LD /D"ATLAS_LAUNCHER_VERSION=\"%LAUNCHER_VERSION%\"" "%SOURCE_FILE%" /link /DEF:"%DEF_FILE%" /OUT:"%OUTPUT_DLL%"
if errorlevel 1 (
  popd
  exit /b 1
)

if not exist "%SCRIPT_DIR%..\atlas_link_flutter\assets\dlls" (
  mkdir "%SCRIPT_DIR%..\atlas_link_flutter\assets\dlls"
)
copy /Y "%OUTPUT_DLL%" "%ASSET_DLL%" >nul

echo Built proxy DLL: %OUTPUT_DLL%
echo Copied to launcher assets: %ASSET_DLL%

popd
endlocal
