#!/bin/sh
# One-command installer for Contabo / XPipe servers.
set -eu

TARGET_DIR="${1:-/tmp/xpipe/root/scripts/bash}"
BASE_URL="https://raw.githubusercontent.com/Florian-Bloechinger/scripts/main/bash"

mkdir -p "$TARGET_DIR"

printf 'Installing Pangolin Manager into %s ...\n' "$TARGET_DIR"
curl -fsSL "$BASE_URL/panglin.sh" -o "$TARGET_DIR/panglin.sh"
curl -fsSL "$BASE_URL/panglin-tui.sh" -o "$TARGET_DIR/panglin-tui.sh"
chmod +x "$TARGET_DIR/panglin.sh" "$TARGET_DIR/panglin-tui.sh"

printf '\nInstalled. Version check:\n'
head -2 "$TARGET_DIR/panglin.sh"
printf '\nRun:\n  %s/panglin.sh\n' "$TARGET_DIR"
