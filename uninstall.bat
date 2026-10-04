@echo off
cd /d "%~dp0"
echo Running WebP Context Menu Converter Uninstaller...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
pause
