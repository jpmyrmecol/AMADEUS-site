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
app="${XDG_DATA_HOME:-$HOME/.local/share}/AMADEUS"

mkdir -p "$(dirname "$app")"

if [ ! -f "$app/AMADEUS.sh" ]; then
    [ ! -e "$app" ] || fail "Installation folder exists but is incomplete: $app"

    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' EXIT
    archive="$temp_dir/AMADEUS.tar.gz"

    echo "Checking the latest AMADEUS release..."
    if command -v curl >/dev/null 2>&1; then
        release_json="$(curl -fsSL --proto '=https' --proto-redir '=https' \
            https://api.github.com/repos/jpmyrmecol/AMADEUS/releases/latest)" \
            || fail "Cannot check the latest AMADEUS release. Check the connection and repository access."
    elif command -v wget >/dev/null 2>&1; then
        release_json="$(wget -qO- \
            https://api.github.com/repos/jpmyrmecol/AMADEUS/releases/latest)" \
            || fail "Cannot check the latest AMADEUS release. Check the connection and repository access."
    else
        fail "curl or wget is required to download AMADEUS."
    fi

    tag="$(printf '%s\n' "$release_json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
    [[ "$tag" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || fail "The latest GitHub Release does not contain a valid AMADEUS version tag."

    echo "Downloading AMADEUS $tag..."
    url="https://github.com/jpmyrmecol/AMADEUS/archive/refs/tags/$tag.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --proto '=https' --proto-redir '=https' "$url" -o "$archive" \
            || fail "Cannot download AMADEUS $tag. Check the connection and repository access."
    else
        wget -O "$archive" "$url" \
            || fail "Cannot download AMADEUS $tag. Check the connection and repository access."
    fi

    tar -xzf "$archive" -C "$temp_dir" || fail "Cannot extract the downloaded release archive."

    source_dir=""
    for candidate in "$temp_dir"/*; do
        if [ -d "$candidate" ] && [ -f "$candidate/AMADEUS.sh" ]; then
            source_dir="$candidate"
            break
        fi
    done
    [ -n "$source_dir" ] || fail "The downloaded release archive does not contain the AMADEUS launcher."

    mv "$source_dir" "$app"
fi

echo "Preparing the environment and starting AMADEUS..."
bash "$app/AMADEUS.sh" || fail "Setup or launch failed. See the message above."
