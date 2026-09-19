@echo off
setlocal
title AMADEUS Setup
echo AMADEUS Setup - Windows 10 / 11
echo Downloading and preparing AMADEUS. Please keep this window open.
powershell.exe -NoProfile -Command ^
 "$ErrorActionPreference = 'Stop';" ^
 "$root = Join-Path $env:LOCALAPPDATA 'AMADEUS'; $app = Join-Path $root 'app'; $launcher = Join-Path $app 'AMADEUS.bat';" ^
 "$temp = Join-Path ([IO.Path]::GetTempPath()) ('amadeus-setup-' + [guid]::NewGuid().ToString('N'));" ^
 "try {" ^
 "  if (!(Test-Path -LiteralPath $launcher)) {" ^
 "    if (Test-Path -LiteralPath $app) { throw 'The installation folder already exists but is incomplete. Rename it before retrying: ' + $app };" ^
 "    New-Item -ItemType Directory -Path $temp -Force | Out-Null;" ^
 "    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
 "    $zip = Join-Path $temp 'AMADEUS.zip';" ^
 "    try { Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/jpmyrmecol/AMADEUS/archive/refs/heads/main.zip' -OutFile $zip } catch { throw 'Cannot download AMADEUS. Check your internet connection. Automatic download requires a publicly accessible repository.' };" ^
 "    Expand-Archive -LiteralPath $zip -DestinationPath $temp;" ^
 "    $source = Join-Path $temp 'AMADEUS-main';" ^
 "    if (!(Test-Path -LiteralPath (Join-Path $source 'AMADEUS.bat'))) { throw 'The downloaded archive does not contain the AMADEUS launcher.' };" ^
 "    New-Item -ItemType Directory -Path $root -Force | Out-Null;" ^
 "    Move-Item -LiteralPath $source -Destination $app;" ^
 "  };" ^
 "  $desktop = [Environment]::GetFolderPath('DesktopDirectory');" ^
 "  $shell = New-Object -ComObject WScript.Shell; $shortcut = $shell.CreateShortcut((Join-Path $desktop 'AMADEUS.lnk'));" ^
 "  $shortcut.TargetPath = $launcher; $shortcut.WorkingDirectory = $app; $shortcut.Description = 'Launch AMADEUS'; $shortcut.Save();" ^
 "} catch { Write-Host ('[ERROR] ' + $_.Exception.Message); exit 1 } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }"
if errorlevel 1 (
    echo Setup could not finish. See the message above.
    pause
    exit /b 1
)
echo Starting dependency setup. The home screen will open when ready.
call "%LOCALAPPDATA%\AMADEUS\app\AMADEUS.bat"
exit /b %errorlevel%
