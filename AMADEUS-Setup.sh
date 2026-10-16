#!/usr/bin/env bash
# Copyright (C) 2026 Yusuke Notomi
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    if [ -t 0 ]; then read -r -p "Press Enter to close..." || true; fi
    exit 1
}

[ "$(uname -s)" = Linux ] || fail "Use this installer on Linux."
[ -n "${DISPLAY:-}" ] || fail "A graphical desktop session or WSLg is required."
if [ "$#" -gt 1 ]; then fail "Usage: AMADEUS-Setup.sh [--git]"; fi
case "${XDG_DATA_HOME:-}" in
    /*) data_home="$XDG_DATA_HOME" ;;
    *)  data_home="$HOME/.local/share" ;;
esac
if [ "$#" -eq 1 ]; then
    [ "$1" = "--git" ] || fail "Usage: AMADEUS-Setup.sh [--git]"
    mode=git
    app="$PWD/AMADEUS"
else
    mode=release
    app="$data_home/AMADEUS"
fi

# A missing virtual environment is repairable by the normal launcher.
installation_complete() {
    local root="$1" file version major minor patch
    for file in tools/runtime_profiles.py tools/python_runtime.py tools/ffmpeg_runtime.py main/compute_telemetry.py main/compute_backend.py gui/splash_ipc.py gui/tk_compat.py \
        AMADEUS.sh VERSION pyproject.toml uv.lock gui/gui_home.py tools/setup_environment.py \
        gui/gui_easy_tracking.py gui/gui_segmentation.py gui/gui_advanced_tracking.py gui/gui_refinement.py gui/gui_preprocess.py gui/gui_colab.py gui/gui_multi_config_batch.py \
        main/batch.py main/create_video.py main/create_dataset.py main/initial_tracking.py main/segmentation_core.py main/refinement.py main/obb_detection.py assets/logo_amadeus_splash.png; do
        [ -s "$root/$file" ] || return 1
    done
    [ -d "$root/main" ] || return 1
    if [ "$(uname -s)" = Darwin ]; then
        [ -f "$root/AMADEUS.command" ] || return 1
    fi
    grep -Eq '^name[[:space:]]*=[[:space:]]*"amadeus"[[:space:]]*$' "$root/pyproject.toml" || return 1
    version="$(tr -d '[:space:]' < "$root/VERSION")" || return 1
    [[ "$version" =~ ^[vV]?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    major=$((10#${BASH_REMATCH[1]}))
    minor=$((10#${BASH_REMATCH[2]}))
    patch=$((10#${BASH_REMATCH[3]}))
    # Keep older complete releases launchable offline; these modules arrived in 1.2.2.
    if (( major > 1 || (major == 1 && minor > 2) || (major == 1 && minor == 2 && patch >= 2) )); then
        for file in gui/addon_gui.py gui/addon_manager.py gui/dark_widgets.py gui/home_drop_routes.py gui/save_shortcut.py gui/segmentation_workflow.py; do
            [ -s "$root/$file" ] || return 1
        done
    fi
    return 0
}

legacy_version() {
    local version="$1" major minor patch
    [[ "$version" =~ ^[vV]?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    major=$((10#${BASH_REMATCH[1]}))
    minor=$((10#${BASH_REMATCH[2]}))
    patch=$((10#${BASH_REMATCH[3]}))
    (( major == 0 || (major == 1 && minor == 0 && patch <= 4) ))
}

confirm_replace() {
    local reason="$1" message answer
    if [ "$reason" = legacy ]; then
        message="AMADEUS v1.0.4 or earlier was detected. Overwrite the existing installation with the current release?"
    else
        message="The AMADEUS launcher exists, but essential files are missing or invalid. Overwrite the incomplete installation?"
    fi
    case "$(uname -s)" in
        Darwin)
            if [ "$reason" = legacy ]; then
                /usr/bin/osascript -e 'display dialog "AMADEUS v1.0.4 or earlier was detected. Overwrite the existing installation with the current release?" with title "AMADEUS Setup" buttons {"Cancel", "Update"} default button "Cancel" cancel button "Cancel" with icon caution' >/dev/null
            else
                /usr/bin/osascript -e 'display dialog "The AMADEUS launcher exists, but essential files are missing or invalid. Overwrite the incomplete installation?" with title "AMADEUS Setup" buttons {"Cancel", "Replace"} default button "Cancel" cancel button "Cancel" with icon caution' >/dev/null
            fi
            ;;
        Linux)
            if command -v zenity >/dev/null 2>&1; then
                zenity --question --title="AMADEUS Setup" --text="$message"
            elif command -v kdialog >/dev/null 2>&1; then
                kdialog --title "AMADEUS Setup" --yesno "$message"
            elif command -v yad >/dev/null 2>&1; then
                yad --question --title="AMADEUS Setup" --text="$message"
            elif command -v xmessage >/dev/null 2>&1; then
                xmessage -center -buttons "Cancel:1,Continue:0" "$message"
            else
                printf '%s\nConfirm [y/N]: ' "$message" >/dev/tty || return 1
                read -r answer </dev/tty || return 1
                [[ "$answer" = y || "$answer" = Y ]]
            fi
            ;;
    esac
}

download_file() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --proto-redir '=https' "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$output" "$url"
    else
        fail "curl or wget is required to download AMADEUS."
    fi
}

# Symlinks and unrelated file targets are never overwritten.
[ ! -L "$app" ] || fail "The installation path is a symbolic link: $app"
[ ! -e "$app" ] || [ -d "$app" ] || fail "The installation path is not a directory: $app"
mkdir -p "$(dirname "$app")"

replace=false
if [ ! -d "$app" ]; then
    replace=true
elif [ ! -f "$app/AMADEUS.sh" ]; then
    echo "[AMADEUS] No launcher found. Reinstalling into $app."
    replace=true
elif ! installation_complete "$app"; then
    if confirm_replace incomplete; then
        replace=true
    else
        echo "[AMADEUS] Replacement cancelled. Existing files were not changed."
        exit 0
    fi
elif legacy_version "$(tr -d '[:space:]' < "$app/VERSION")"; then
    if confirm_replace legacy; then
        replace=true
    else
        echo "[AMADEUS] Update declined. Launching the existing version."
    fi
fi

if [ "$replace" = true ]; then
    temp_dir="$(mktemp -d "$(dirname "$app")/.AMADEUS-install.XXXXXXXX")" || fail "Cannot create installation staging directory."
    trap 'rm -rf -- "$temp_dir"' EXIT

    if [ "$mode" = git ]; then
        command -v git >/dev/null 2>&1 || fail "Git is required for this installation method."
        echo "[AMADEUS] Cloning the current main branch..."
        git clone --depth 1 --branch main https://github.com/jpmyrmecol/AMADEUS.git "$temp_dir/source" \
            || fail "Could not clone AMADEUS."
        source_dir="$temp_dir/source"
    else
        echo "[AMADEUS] Checking the latest AMADEUS release..."
        download_file https://api.github.com/repos/jpmyrmecol/AMADEUS/releases/latest "$temp_dir/release.json" \
            || fail "Could not query the latest GitHub Release."
        tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$temp_dir/release.json" | head -n 1)"
        [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "The latest GitHub Release has an invalid version tag."
        echo "[AMADEUS] Downloading $tag..."
        download_file "https://github.com/jpmyrmecol/AMADEUS/archive/refs/tags/$tag.tar.gz" "$temp_dir/AMADEUS.tar.gz" \
            || fail "Could not download AMADEUS $tag."
        mkdir "$temp_dir/extracted"
        tar -xzf "$temp_dir/AMADEUS.tar.gz" -C "$temp_dir/extracted" \
            || fail "Could not extract the downloaded release."
        source_dir=""
        for candidate in "$temp_dir/extracted"/AMADEUS-*; do
            if [ -d "$candidate" ] && [ -f "$candidate/VERSION" ]; then
                source_dir="$candidate"
                break
            fi
        done
        [ -n "$source_dir" ] || fail "The release archive has no AMADEUS source directory."
        source_version="$(tr -d '[:space:]' < "$source_dir/VERSION")"
        [ "$source_version" = "${tag#v}" ] || fail "The release archive version does not match its tag."
    fi

    installation_complete "$source_dir" || fail "The downloaded source is incomplete; existing files were not changed."

    # Overlay the verified source. Existing matching files are overwritten;
    # unrelated files and the managed virtual environment remain in place.
    mkdir -p "$app" || fail "Could not create installation directory: $app. Check write permissions."
    cp -R "$source_dir/." "$app/" || fail "Could not overwrite AMADEUS files in $app. Check write permissions."
    installation_complete "$app" || fail "AMADEUS source verification failed after overwrite."
    echo "[AMADEUS] Installed source files in $app."
fi

if [ "$(uname -s)" = Darwin ]; then
    export AMADEUS_VENV="${AMADEUS_VENV:-$app/.venv}"
    if amadeus_ensure_macos_python; then
        :
    else
        status=$?
        [ "$status" -eq 2 ] && exit 0
        fail "Python preparation stopped. See the message above."
    fi
fi

echo "[AMADEUS] Starting $app..."
bash "$app/AMADEUS.sh" || fail "Setup or launch failed. See the message above."

