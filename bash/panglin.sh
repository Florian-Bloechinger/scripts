#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /usr/bin/env bash "$SCRIPT_DIR/../utiliy/panglin-cli.sh" "$@"
