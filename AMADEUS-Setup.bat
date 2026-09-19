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
 "    try { $release = Invoke-RestMethod -UseBasicParsing -Uri 'https://api.github.com/repos/jpmyrmecol/AMADEUS/releases/latest'; $tag = [string]$release.tag_name; if ([string]::IsNullOrWhiteSpace($tag)) { throw 'The latest release does not contain a tag name.' }; $archiveUrl = 'https://github.com/jpmyrmecol/AMADEUS/archive/refs/tags/' + [Uri]::EscapeDataString($tag) + '.zip'; Invoke-WebRequest -UseBasicParsing -Uri $archiveUrl -OutFile $zip } catch { throw 'Cannot download the latest AMADEUS release. Check your internet connection and confirm that a published GitHub Release exists.' };" ^
 "    Expand-Archive -LiteralPath $zip -DestinationPath $temp;" ^
 "    $source = Get-ChildItem -LiteralPath $temp -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'AMADEUS.bat') } | Select-Object -First 1;" ^
 "    if ($null -eq $source) { throw 'The downloaded release archive does not contain the AMADEUS launcher.' };" ^
 "    $source = $source.FullName;" ^
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
