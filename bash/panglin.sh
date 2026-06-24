#!/bin/sh
# XPipe entry point — POSIX only; delegates to bash CLI in utiliy/.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
CLI_SCRIPT="$SCRIPT_DIR/../utiliy/panglin-cli.sh"

if [ ! -f "$CLI_SCRIPT" ]; then
    printf 'Error: missing %s\n' "$CLI_SCRIPT" >&2
    exit 1
fi

for _bash in /bin/bash /usr/bin/bash /usr/local/bin/bash bash; do
    if command -v "$_bash" >/dev/null 2>&1 && "$_bash" -c 'exit 0' 2>/dev/null; then
        exec "$_bash" "$CLI_SCRIPT" "$@"
    fi
done

printf 'Error: bash is required.\n' >&2
exit 1
