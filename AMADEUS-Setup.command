#!/usr/bin/env bash
# Copyright (C) 2026 Yusuke Notomi
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail

fail() {
    printf '[ERROR] %s\n' "$*" >&2
    if [ -t 0 ]; then read -r -p "Press Enter to close..." || true; fi
    exit 1
}

[ "$(uname -s)" = Darwin ] || fail "Use this installer on macOS."
[ "$(uname -m)" = arm64 ] || fail "Native Apple Silicon is required. Do not use Rosetta."
if [ "$#" -gt 1 ]; then fail "Usage: AMADEUS-Setup.command [--git]"; fi
if [ "$#" -eq 1 ]; then
    [ "$1" = "--git" ] || fail "Usage: AMADEUS-Setup.command [--git]"
    mode=git
    app="$PWD/AMADEUS"
else
    mode=release
    app="$HOME/Applications/AMADEUS"
fi
export AMADEUS_VENV="${AMADEUS_VENV:-$app/.venv}"

# BEGIN shared macOS Python bootstrap
#!/usr/bin/env bash
# Copyright (C) 2026 Yusuke Notomi
# SPDX-License-Identifier: AGPL-3.0-only
# Also embedded verbatim in AMADEUS-site/AMADEUS-Setup.command so the
# downloaded, standalone installer can check Python before any downloads.

amadeus_check_python() {
    "$1" -I - <<'PY' >/dev/null 2>&1
import platform
import sys
assert sys.platform == 'darwin'
assert sys.version_info[:2] == (3, 12)
assert platform.machine() == 'arm64'
import tkinter as tk
assert tk.TclVersion == 8.6 and tk.TkVersion == 8.6
root = tk.Tk()
root.withdraw()
assert str(root.tk.call('info', 'patchlevel')).startswith('8.6.')
assert str(root.tk.call('package', 'require', 'Tk')).startswith('8.6.')
root.update()
root.destroy()
PY
}

amadeus_python_candidates() {
    printf '%s\n' "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3.12"
    printf '%s\n' "/opt/homebrew/opt/python@3.12/bin/python3.12"
    command -v python3.12 || true
    candidate="$(command -v python3 || true)"
    # Apple's stub can open a Command Line Tools installation dialog.
    if [ "$candidate" != /usr/bin/python3 ]; then printf '%s\n' "$candidate"; fi
}

amadeus_open_python_installer() (
    # Clean up failures, but retain the pkg while Installer.app uses it.
    local temp_dir pkg digest
    temp_dir="$(mktemp -d)" || return 1
    trap 'rm -rf "$temp_dir"' EXIT
    pkg="$temp_dir/python.pkg"
    echo '[AMADEUS] Downloading Python 3.12.10 from python.org...'
    /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' \
        --retry 2 --connect-timeout 30 \
        https://www.python.org/ftp/python/3.12.10/python-3.12.10-macos11.pkg \
        --output "$pkg" || return 1
    # SHA-256 from the release's python.org .sigstore messageDigest.
    digest="$(/usr/bin/shasum -a 256 "$pkg")" || return 1
    if [ "${digest%% *}" != 8373e58da4ea146b3eb1c1f9834f19a319440b6b679b06050b1f9ee3237aa8e4 ]; then
        echo '[ERROR] Python package checksum mismatch; installation stopped.' >&2
        return 1
    fi
    /usr/sbin/pkgutil --check-signature "$pkg" || return 1
    /usr/sbin/spctl --assess --type install "$pkg" || return 1
    /usr/bin/open -a /System/Library/CoreServices/Installer.app "$pkg" || return 1
    trap - EXIT
    echo "[AMADEUS] Python package opened in Installer.app: $pkg"
    echo '[AMADEUS] Complete the Python installation in Installer.app, then run AMADEUS Setup again.'
    echo '[AMADEUS] Setup is exiting now. The package can be deleted after installation.'
)

# Returns 0 for a compatible Python, 1 for failure, or 2 to stop normally
# after cancellation or handing the package to Installer.app.
amadeus_ensure_macos_python() {
    local candidate existing
    case "${AMADEUS_VENV:?AMADEUS_VENV must be set}" in
        /*) ;;
        *) export AMADEUS_VENV="$PWD/$AMADEUS_VENV" ;;
    esac
    echo '[AMADEUS] Checking for compatible Apple Silicon Python and Tcl/Tk...'
    # Explicit Python selections must be validated before setup.
    if [ -n "${AMADEUS_PYTHON:-}" ]; then
        if ! amadeus_check_python "$AMADEUS_PYTHON"; then
            echo '[ERROR] AMADEUS_PYTHON is incompatible. Correct or unset it, then retry.' >&2
            return 1
        fi
        return 0
    fi
    existing="${AMADEUS_VENV:?AMADEUS_VENV must be set}/bin/python"
    if [ -e "$AMADEUS_VENV" ]; then
        if [ -x "$existing" ] && amadeus_check_python "$existing"; then
            export AMADEUS_PYTHON="$existing"
            return 0
        fi
        echo '[AMADEUS] Existing environment is incompatible with Python 3.12; setup will rebuild the managed .venv.'
    fi
    while IFS= read -r candidate; do
        if [ -x "$candidate" ] && amadeus_check_python "$candidate"; then
            export AMADEUS_PYTHON="$candidate"
            echo "[AMADEUS] Using Python: $AMADEUS_PYTHON"
            return 0
        fi
    done < <(amadeus_python_candidates)

    echo 'No compatible Python was found (native arm64, Python 3.12, Tcl/Tk 8.6).'
    if ! /usr/bin/osascript -e 'display dialog "No compatible Python was found. Download the official Python 3.12.10 package from python.org and open it in Installer.app?\n\nInstaller.app will handle installation and any administrator authentication. It installs a system-wide Python and may replace an existing python.org 3.12 installation.\n\nAfter completing the Python installation, run AMADEUS Setup again." with title "AMADEUS Setup" buttons {"Cancel", "Download Python"} default button "Download Python" cancel button "Cancel"' >/dev/null; then
        echo '[AMADEUS] Python download was not approved; setup stopped.'
        return 2
    fi
    if ! amadeus_open_python_installer; then
        echo '[ERROR] Could not prepare or open the Python installer. Retry AMADEUS Setup.' >&2
        return 1
    fi
    return 2
}
# END shared macOS Python bootstrap

# A missing virtual environment is repairable by the normal launcher.
installation_complete() {
    local root="$1" file version
    for file in AMADEUS.sh VERSION pyproject.toml uv.lock gui/gui_home.py tools/setup_environment.py \
        gui/gui_easy_tracking.py gui/gui_segmentation.py gui/gui_advanced_tracking.py gui/gui_refinement.py gui/gui_preprocess.py gui/gui_colab.py gui/gui_multi_config_batch.py \
        main/batch.py main/create_video.py main/create_dataset.py main/initial_tracking.py main/segmentation_core.py main/refinement.py main/obb_detection.py assets/logo_amadeus_splash.png; do
        [ -s "$root/$file" ] || return 1
    done
    [ -d "$root/main" ] || return 1
    if [ "$(uname -s)" = Darwin ]; then
        [ -s "$root/AMADEUS.command" ] || return 1
    fi
    grep -Eq '^name[[:space:]]*=[[:space:]]*"amadeus"[[:space:]]*$' "$root/pyproject.toml" || return 1
    version="$(tr -d '[:space:]' < "$root/VERSION")" || return 1
    [[ "$version" =~ ^[vV]?[0-9]+\.[0-9]+\.[0-9]+$ ]]
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
        message="AMADEUS v1.0.4 or earlier was detected. Update to the current release now? The existing installation will be backed up."
    else
        message="The AMADEUS launcher exists, but essential application files are missing or invalid. Replace this incomplete installation? A backup will be kept."
    fi
    case "$(uname -s)" in
        Darwin)
            if [ "$reason" = legacy ]; then
                /usr/bin/osascript -e 'display dialog "AMADEUS v1.0.4 or earlier was detected. Update it now? Your existing installation will be backed up." with title "AMADEUS Setup" buttons {"Cancel", "Update"} default button "Cancel" cancel button "Cancel" with icon caution' >/dev/null
            else
                /usr/bin/osascript -e 'display dialog "The AMADEUS launcher exists, but essential files are missing or invalid. Replace the incomplete installation? A backup will be kept." with title "AMADEUS Setup" buttons {"Cancel", "Replace"} default button "Cancel" cancel button "Cancel" with icon caution' >/dev/null
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

    backup=""
    if [ -d "$app" ]; then
        backup="$app.backup-$(date +%Y%m%d-%H%M%S)-$$"
        mv -- "$app" "$backup" || fail "Could not back up the existing AMADEUS directory."
    fi
    if ! mv -- "$source_dir" "$app"; then
        if [ -n "$backup" ]; then
            mv -- "$backup" "$app" || fail "Replacement failed and the backup could not be restored: $backup"
        fi
        fail "Could not install AMADEUS."
    fi
    if [ -n "$backup" ]; then
        echo "[AMADEUS] Previous directory preserved at: $backup"
    fi
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
