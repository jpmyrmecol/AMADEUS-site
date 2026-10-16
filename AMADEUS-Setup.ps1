# Copyright (C) 2026 Yusuke Notomi
# SPDX-License-Identifier: AGPL-3.0-only
# Standalone Windows setup engine for the downloadable installer and Git mode.
param(
    [ValidateSet("Release", "Git")]
    [string]$Mode = "Release"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$app = if ($Mode -eq "Git") {
    Join-Path $PWD.Path "AMADEUS"
} else {
    Join-Path (Join-Path $env:LOCALAPPDATA "AMADEUS") "app"
}
$launcher = Join-Path $app "AMADEUS.bat"

function Test-CompleteInstallation([string]$Root) {
    $required = @(
        "tools/runtime_profiles.py", "tools/python_runtime.py", "tools/ffmpeg_runtime.py", "main/compute_telemetry.py", "main/compute_backend.py", "gui/splash_ipc.py", "gui/tk_compat.py", "tools/uv_bootstrap.ps1", "tools/windows_python.ps1",
        "AMADEUS.bat", "AMADEUS.sh", "VERSION", "pyproject.toml",
        "uv.lock", "gui/gui_home.py", "tools/setup_environment.py",
        "gui/gui_easy_tracking.py", "gui/gui_segmentation.py", "gui/gui_advanced_tracking.py", "gui/gui_refinement.py", "gui/gui_preprocess.py",
        "gui/gui_colab.py", "gui/gui_multi_config_batch.py", "main/batch.py", "main/create_video.py", "main/create_dataset.py",
        "main/initial_tracking.py", "main/segmentation_core.py", "main/refinement.py", "main/obb_detection.py", "assets/logo_amadeus_splash.png"
    )
    foreach ($relative in $required) {
        $file = Join-Path $Root $relative
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
        if ((Get-Item -LiteralPath $file).Length -eq 0) { return $false }
    }
    if (!(Test-Path -LiteralPath (Join-Path $Root "main") -PathType Container)) {
        return $false
    }
    $pyproject = Get-Content -Raw -LiteralPath (Join-Path $Root "pyproject.toml")
    if ($pyproject -notmatch '(?m)^name\s*=\s*"amadeus"\s*$') { return $false }
    $versionText = (Get-Content -Raw -LiteralPath (Join-Path $Root "VERSION")).Trim()
    return $versionText -match '^[vV]?[0-9]+\.[0-9]+\.[0-9]+$'
}

function Test-LegacyVersion([string]$Root) {
    $text = (Get-Content -Raw -LiteralPath (Join-Path $Root "VERSION")).Trim()
    $normal = $text -replace '^[vV]', ''
    return ([Version]::Parse($normal) -le [Version]::Parse("1.0.4"))
}

function Confirm-Replacement([string]$Kind) {
    Add-Type -AssemblyName System.Windows.Forms
    $message = if ($Kind -eq "Legacy") {
        "AMADEUS v1.0.4 or earlier was detected. Overwrite it with the current release?"
    } else {
        "The AMADEUS launcher exists, but essential files are missing or invalid. " +
        "Overwrite this incomplete installation?"
    }
    $choice = [System.Windows.Forms.MessageBox]::Show(
        $message, "AMADEUS Setup",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    return $choice -eq [System.Windows.Forms.DialogResult]::Yes
}

function Install-Source([string]$Source, [string]$Destination) {
    # Overwrite matching distribution files without moving the old directory.
    # Extra files and managed runtime folders are retained.
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    & robocopy.exe $Source $Destination /E /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) {
        throw "Could not overwrite AMADEUS files in $Destination (robocopy exit $LASTEXITCODE)."
    }
    if (!(Test-CompleteInstallation $Destination)) {
        throw "AMADEUS source verification failed after overwrite."
    }
    Write-Host "[AMADEUS] Installed source files in $Destination."
}

if (Test-Path -LiteralPath $app) {
    $target = Get-Item -LiteralPath $app -Force
    if (!$target.PSIsContainer) { throw "Installation path is not a directory: $app" }
    if (($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Installation path is a symbolic link or junction: $app"
    }
}

$replace = !(Test-Path -LiteralPath $app)
if (!$replace) {
    if (!(Test-Path -LiteralPath $launcher -PathType Leaf)) {
        Write-Host "[AMADEUS] Launcher missing. Reinstalling into $app."
        $replace = $true
    } elseif (!(Test-CompleteInstallation $app)) {
        if (!(Confirm-Replacement "Incomplete")) {
            Write-Host "[AMADEUS] Replacement cancelled. Existing files were not changed."
            exit 0
        }
        $replace = $true
    } elseif (Test-LegacyVersion $app) {
        if (Confirm-Replacement "Legacy") {
            $replace = $true
        } else {
            Write-Host "[AMADEUS] Update declined. Launching the existing version."
        }
    }
}

if ($replace) {
    $parent = Split-Path -Parent $app
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $staging = Join-Path $parent (".AMADEUS-install-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $staging | Out-Null
    try {
        if ($Mode -eq "Git") {
            if (!(Get-Command git -ErrorAction SilentlyContinue)) {
                throw "Git is required for this installation method."
            }
            Write-Host "[AMADEUS] Cloning the current main branch..."
            $source = Join-Path $staging "source"
            & git clone --depth 1 --branch main "https://github.com/jpmyrmecol/AMADEUS.git" $source
            if ($LASTEXITCODE -ne 0) { throw "Could not clone AMADEUS." }
        } else {
            Write-Host "[AMADEUS] Checking the latest GitHub Release..."
            $release = Invoke-RestMethod -UseBasicParsing -Uri "https://api.github.com/repos/jpmyrmecol/AMADEUS/releases/latest"
            $tag = [string]$release.tag_name
            if ($tag -notmatch '^v?[0-9]+\.[0-9]+\.[0-9]+$') {
                throw "The latest GitHub Release has an invalid version tag."
            }
            $archive = Join-Path $staging "AMADEUS.zip"
            $url = "https://github.com/jpmyrmecol/AMADEUS/archive/refs/tags/" + [Uri]::EscapeDataString($tag) + ".zip"
            Write-Host "[AMADEUS] Downloading $tag..."
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive
            $unpacked = Join-Path $staging "extracted"
            Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
            $sourceDirectory = Get-ChildItem -LiteralPath $unpacked -Directory |
                Where-Object { $_.Name -like "AMADEUS-*" } | Select-Object -First 1
            if ($null -eq $sourceDirectory) {
                throw "The release archive has no AMADEUS source directory."
            }
            $source = $sourceDirectory.FullName
            $actualVersion = (Get-Content -Raw -LiteralPath (Join-Path $source "VERSION")).Trim()
            if ($actualVersion -ne $tag.TrimStart("v")) {
                throw "The release archive version does not match its tag."
            }
        }

        if (!(Test-CompleteInstallation $source)) {
            throw "The downloaded source is incomplete. Existing files were not changed."
        }
        Install-Source $source $app
    } finally {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }
}

if ($Mode -eq "Release") {
    $desktop = [Environment]::GetFolderPath("DesktopDirectory")
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $desktop "AMADEUS.lnk"))
    $shortcut.TargetPath = $launcher
    $shortcut.WorkingDirectory = $app
    $shortcut.Description = "Launch AMADEUS"
    $shortcut.Save()
}

Write-Host "[AMADEUS] Starting $app..."
Push-Location -LiteralPath $app
try {
    & $launcher
    if ($LASTEXITCODE -ne 0) {
        throw "AMADEUS exited with code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
