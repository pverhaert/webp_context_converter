@echo off
cd /d "%~dp0"
echo Running WebP Context Menu Converter Installer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
echo.
pause
