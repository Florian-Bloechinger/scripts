#!/bin/sh
# POSIX launcher for XPipe / dash — delegates to bash TUI.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
TUI_SCRIPT="$SCRIPT_DIR/panglin-tui.sh"

if [ ! -f "$TUI_SCRIPT" ]; then
    printf 'Error: missing %s\n' "$TUI_SCRIPT" >&2
    exit 1
fi

for bash_bin in /bin/bash /usr/bin/bash /usr/local/bin/bash bash; do
    if command -v "$bash_bin" >/dev/null 2>&1 && "$bash_bin" -c 'exit 0' 2>/dev/null; then
        exec "$bash_bin" "$TUI_SCRIPT" "$@"
    fi
done

printf 'Error: bash is required for Pangolin Manager.\n' >&2
exit 1
