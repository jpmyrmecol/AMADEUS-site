@echo off
setlocal
title AMADEUS Setup
set "MODE=Release"
if /I "%~1"=="--git" set "MODE=Git"
if not "%~1"=="" if /I not "%~1"=="--git" (
    echo Usage: AMADEUS-Setup.bat [--git]
    exit /b 1
)
set "SCRIPT=%TEMP%\AMADEUS-Setup-%RANDOM%-%RANDOM%.ps1"
set "AMADEUS_SETUP_SCRIPT=%SCRIPT%"
echo [AMADEUS] Preparing setup for %MODE% mode...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; Invoke-WebRequest -UseBasicParsing -Uri 'https://amadeus.jpmyrmecol.com/AMADEUS-Setup.ps1' -OutFile $env:AMADEUS_SETUP_SCRIPT"
if errorlevel 1 (
    echo [ERROR] Cannot download the setup helper. Check your internet connection.
    pause
    exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode %MODE%
set "STATUS=%ERRORLEVEL%"
del /q "%SCRIPT%" >nul 2>&1
if not "%STATUS%"=="0" (
    echo [ERROR] AMADEUS setup failed.
    pause
    exit /b %STATUS%
)
exit /b 0
