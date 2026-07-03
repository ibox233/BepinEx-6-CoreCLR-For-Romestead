@echo off
setlocal
title Romestead Server BepInEx Mod Loader Uninstaller
cd /d "%~dp0"

echo Romestead Server BepInEx Mod Loader Uninstaller
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
set "exitcode=%ERRORLEVEL%"

echo.
if not "%exitcode%"=="0" (
    echo Uninstall failed with exit code %exitcode%.
) else (
    echo Uninstall finished.
)
echo.
pause
exit /b %exitcode%
