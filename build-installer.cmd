@echo off
setlocal
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\installer\build-installer.ps1" %*
exit /b %errorlevel%
