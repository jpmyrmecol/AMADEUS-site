@echo off
setlocal
title AMADEUS Setup
set "MODE=Release"
if /I "%~1"=="--git" set "MODE=Git"
if not "%~1"=="" if /I not "%~1"=="--git" (
    echo Usage: AMADEUS-Setup.bat [--git]
    exit /b 1
)
if /I "%MODE%"=="Git" (
    set "APP=%CD%\AMADEUS"
) else (
    set "APP=%LOCALAPPDATA%\AMADEUS\app"
)
set "AMADEUS_SETUP_TARGET=%APP%"

REM A complete v1.0.5+ installation can start offline without downloading setup.
powershell.exe -NoProfile -Command ^
 "$r=$env:AMADEUS_SETUP_TARGET; $files=@('AMADEUS.bat','AMADEUS.sh','VERSION','pyproject.toml','uv.lock','gui/gui_home.py','tools/setup_environment.py','gui/gui_easy_tracking.py','gui/gui_segmentation.py','gui/gui_advanced_tracking.py','gui/gui_refinement.py','gui/gui_preprocess.py','gui/gui_colab.py','gui/gui_multi_config_batch.py','main/batch.py','main/create_video.py','main/create_dataset.py','main/initial_tracking.py','main/segmentation_core.py','main/refinement.py','main/obb_detection.py','assets/logo_amadeus_splash.png');" ^
 "try { if (!(Test-Path -LiteralPath $r -PathType Container)) { exit 1 };" ^
 "if (((Get-Item -LiteralPath $r -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { exit 1 };" ^
 "foreach ($f in $files) { $p=Join-Path $r $f; if (!(Test-Path -LiteralPath $p -PathType Leaf)) { exit 1 }; if ((Get-Item -LiteralPath $p).Length -eq 0) { exit 1 } };" ^
 "if (!(Test-Path -LiteralPath (Join-Path $r 'main') -PathType Container)) { exit 1 };" ^
 "$p=Get-Content -Raw -LiteralPath (Join-Path $r 'pyproject.toml'); $rx='(?m)^name\s*=\s*'+[char]34+'amadeus'+[char]34+'\s*$'; if ($p -notmatch $rx) { exit 1 };" ^
 "$v=(Get-Content -Raw -LiteralPath (Join-Path $r 'VERSION')).Trim(); if ($v -notmatch '^[vV]?[0-9]+\.[0-9]+\.[0-9]+$') { exit 1 };" ^
 "if ([Version]::Parse(($v -replace '^[vV]', '')) -le [Version]'1.0.4') { exit 1 }; exit 0" ^
 "} catch { exit 1 }"
if not errorlevel 1 goto start_existing

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

:start_existing
echo [AMADEUS] Launching existing installation...
call "%APP%\AMADEUS.bat"
exit /b %ERRORLEVEL%
