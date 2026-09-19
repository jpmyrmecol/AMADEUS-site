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
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT
archive="$temp_dir/AMADEUS.tar.gz"

if [ ! -f "$app/AMADEUS.sh" ]; then
    [ ! -e "$app" ] || fail "Installation folder exists but is incomplete: $app"
    echo "Downloading AMADEUS..."
    url="https://github.com/jpmyrmecol/AMADEUS/archive/refs/heads/main.tar.gz"
    if command -v curl >/dev/null 2>&1; then
        curl -fL "$url" -o "$archive" || fail "Cannot download AMADEUS. Check the connection and repository access."
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$archive" "$url" || fail "Cannot download AMADEUS. Check the connection and repository access."
    else
        fail "curl or wget is required to download AMADEUS."
    fi
    tar -xzf "$archive" -C "$temp_dir" || fail "Cannot extract the downloaded archive."
    [ -f "$temp_dir/AMADEUS-main/AMADEUS.sh" ] || fail "The archive does not contain the AMADEUS launcher."
    mv "$temp_dir/AMADEUS-main" "$app"
fi

echo "Preparing the environment and starting AMADEUS..."
bash "$app/AMADEUS.sh" || fail "Setup or launch failed. See the message above."
