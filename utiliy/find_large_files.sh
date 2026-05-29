#!/usr/bin/env bash

if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -u

# find_large_files.sh - Größte Dateien und Verzeichnisse finden

SEARCH_PATH="/"
TOP_N=20
MIN_SIZE="+100M"
JSON_OUTPUT=false
NO_COLORS=false
MODE="files"

print_help() {
    cat <<EOF
Usage: $0 [options] [path]

Findet große Dateien oder Verzeichnisse auf dem System.

Options:
  -h, --help          Hilfe anzeigen
  -n, --top=N         Anzahl Ergebnisse (Standard: ${TOP_N})
  -s, --min-size=SIZE Mindestgröße (find-Format, Standard: ${MIN_SIZE})
  -d, --dirs          Größte Verzeichnisse statt Dateien
  -j, --json          JSON-Ausgabe
      --no-colors     Farben deaktivieren

Beispiele:
  $0 /var/log
  $0 --top 10 --min-size +1G /home
  $0 --dirs /var
EOF
}

init_colors() {
    if $NO_COLORS || ! command -v tput >/dev/null 2>&1; then
        RESET="" BOLD="" GREEN="" YELLOW="" RED="" CYAN="" DIM=""
        return
    fi
    RESET=$(tput sgr0)
    BOLD=$(tput bold)
    GREEN=$(tput setaf 84)
    YELLOW=$(tput setaf 221)
    RED=$(tput setaf 196)
    CYAN=$(tput setaf 51)
    DIM=$(tput setaf 244)
}

human_size() {
    numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "${1}B"
}

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g'
}

find_large_files() {
    local path="$1"
    local tmp count=0

    tmp=$(mktemp)
    find "$path" -xdev -type f -size "$MIN_SIZE" -printf '%s\t%p\n' 2>/dev/null \
        | sort -rn \
        | head -n "$TOP_N" > "$tmp"

    if $JSON_OUTPUT; then
        echo -n '['
        local first=true size file hsize
        while IFS=$'\t' read -r size file; do
            [ -z "$file" ] && continue
            $first || echo -n ','
            first=false
            hsize=$(human_size "$size")
            printf '{"path":"%s","size_bytes":%s,"size_human":"%s"}' \
                "$(json_escape "$file")" "$size" "$(json_escape "$hsize")"
        done < "$tmp"
        echo ']'
    else
        echo -e "${BOLD}${CYAN}Größte Dateien in ${path}${RESET} ${DIM}(>= ${MIN_SIZE})${RESET}"
        echo -e "${DIM}---------------------------------------------${RESET}"
        if [ ! -s "$tmp" ]; then
            echo -e "${GREEN}Keine Dateien über der Mindestgröße gefunden.${RESET}"
        else
            while IFS=$'\t' read -r size file; do
                count=$((count + 1))
                hsize=$(human_size "$size")
                color=$GREEN
                [ "$size" -ge 1073741824 ] && color=$RED
                [ "$size" -ge 524288000 ] && [ "$size" -lt 1073741824 ] && color=$YELLOW
                printf "  ${color}%-10s${RESET} %s\n" "$hsize" "$file"
            done < "$tmp"
        fi
        echo -e "${DIM}---------------------------------------------${RESET}"
        echo -e "${DIM}${count} Ergebnis(se)${RESET}"
    fi
    rm -f "$tmp"
}

find_large_dirs() {
    local path="$1"

    if $JSON_OUTPUT; then
        echo -n '['
        local first=true size dir hsize
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            size=$(echo "$line" | awk '{print $1}')
            dir=$(echo "$line" | awk '{$1=""; sub(/^ /,""); print}')
            $first || echo -n ','
            first=false
            hsize=$(human_size "$size")
            printf '{"path":"%s","size_bytes":%s,"size_human":"%s"}' \
                "$(json_escape "$dir")" "$size" "$(json_escape "$hsize")"
        done < <(du -x -B1 "$path" 2>/dev/null | sort -rn | head -n "$TOP_N")
        echo ']'
    else
        echo -e "${BOLD}${CYAN}Größte Verzeichnisse in ${path}${RESET}"
        echo -e "${DIM}---------------------------------------------${RESET}"
        du -x -B1 "$path" 2>/dev/null | sort -rn | head -n "$TOP_N" | while read -r size dir; do
            hsize=$(human_size "$size")
            color=$GREEN
            [ "$size" -ge 1048576 ] && color=$RED
            [ "$size" -ge 512000 ] && [ "$size" -lt 1048576 ] && color=$YELLOW
            printf "  ${color}%-10s${RESET} %s\n" "$hsize" "$dir"
        done
        echo -e "${DIM}---------------------------------------------${RESET}"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -n|--top=*) TOP_N="${1#*=}"; shift ;;
        -s|--min-size=*) MIN_SIZE="${1#*=}"; shift ;;
        -d|--dirs) MODE="dirs"; shift ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        --no-colors) NO_COLORS=true; shift ;;
        --) shift; break ;;
        -*) echo "Unbekannte Option: $1" >&2; print_help; exit 1 ;;
        *) SEARCH_PATH="$1"; shift ;;
    esac
done

if [ ! -e "$SEARCH_PATH" ]; then
    echo "Pfad existiert nicht: $SEARCH_PATH" >&2
    exit 1
fi

init_colors

if [ "$MODE" = "dirs" ]; then
    find_large_dirs "$SEARCH_PATH"
else
    find_large_files "$SEARCH_PATH"
fi

$JSON_OUTPUT || echo -e "${GREEN}${BOLD}Fertig.${RESET}"
