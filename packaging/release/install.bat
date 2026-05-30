@echo off
setlocal
title Romestead BepInEx Mod Loader Installer
cd /d "%~dp0"

echo Romestead BepInEx Mod Loader Installer
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "exitcode=%ERRORLEVEL%"

echo.
if not "%exitcode%"=="0" (
    echo Install failed with exit code %exitcode%.
) else (
    echo Install finished.
)
echo.
pause
exit /b %exitcode%
