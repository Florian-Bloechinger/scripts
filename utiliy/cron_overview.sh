#!/usr/bin/env bash

if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -u

# cron_overview.sh - Cronjobs und systemd-Timer übersichtlich auflisten

JSON_OUTPUT=false
NO_COLORS=false
INCLUDE_SYSTEM=true
INCLUDE_USERS=true
INCLUDE_TIMERS=true

print_help() {
    cat <<EOF
Usage: $0 [options]

Listet Cronjobs (System + User) und optional systemd-Timer auf.

Options:
  -h, --help          Hilfe anzeigen
  -j, --json          JSON-Ausgabe
      --no-colors     Farben deaktivieren
      --no-system     System-Cron (/etc/cron.*) überspringen
      --no-users      User-Crontabs überspringen
      --no-timers     systemd-Timer überspringen

Beispiele:
  $0
  $0 --json
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

json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g'
}

print_header() {
    $JSON_OUTPUT && return 0
    echo -e "${CYAN}${BOLD}▶ $1${RESET}"
    echo -e "${DIM}---------------------------------------------${RESET}"
}

emit_json_entry() {
    local source="$1" schedule="$2" command="$3" user="${4:-}"
    [ "$first_json" = false ] && echo ','
    first_json=false
    printf '{"source":"%s","schedule":"%s","command":"%s","user":"%s"}' \
        "$(json_escape "$source")" "$(json_escape "$schedule")" \
        "$(json_escape "$command")" "$(json_escape "$user")"
}

show_system_cron() {
    local dir file line schedule command

    for dir in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
        [ -d "$dir" ] || continue
        for file in "$dir"/*; do
            [ -e "$file" ] || continue
            [ "$(basename "$file")" = ".placeholder" ] && continue

            if [ -d "$file" ]; then
                continue
            elif [ -x "$file" ] && [[ "$dir" == */cron.*ly ]] || [[ "$dir" == */cron.hourly ]]; then
                schedule=$(basename "$dir")
                command="$file"
                if $JSON_OUTPUT; then
                    emit_json_entry "$dir" "$schedule" "$command" "root"
                else
                    printf "  ${YELLOW}%-18s${RESET} ${GREEN}%-12s${RESET} %s\n" "$dir" "$schedule" "$command"
                fi
            else
                while IFS= read -r line || [ -n "$line" ]; do
                    line="${line%%#*}"
                    line="${line#"${line%%[![:space:]]*}"}"
                    [ -z "$line" ] && continue
                    schedule=$(echo "$line" | awk '{print $1" "$2" "$3" "$4" "$5}')
                    command=$(echo "$line" | awk '{$1=$2=$3=$4=$5=""; sub(/^ +/, ""); print}')
                    if $JSON_OUTPUT; then
                        emit_json_entry "$file" "$schedule" "$command" "root"
                    else
                        printf "  ${YELLOW}%-18s${RESET} ${GREEN}%-18s${RESET} %s\n" "$(basename "$file")" "$schedule" "$command"
                    fi
                done < "$file"
            fi
        done
    done

    if [ -r /etc/crontab ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%%#*}"
            line="${line#"${line%%[![:space:]]*}"}"
            [ -z "$line" ] && continue
            [[ "$line" == SHELL* || "$line" == PATH* || "$line" == MAILTO* ]] && continue
            user=$(echo "$line" | awk '{print $6}')
            schedule=$(echo "$line" | awk '{print $1" "$2" "$3" "$4" "$5}')
            command=$(echo "$line" | awk '{$1=$2=$3=$4=$5=$6=""; sub(/^ +/, ""); print}')
            if $JSON_OUTPUT; then
                emit_json_entry "/etc/crontab" "$schedule" "$command" "$user"
            else
                printf "  ${YELLOW}%-18s${RESET} ${GREEN}%-18s${RESET} ${CYAN}%-8s${RESET} %s\n" "crontab" "$schedule" "$user" "$command"
            fi
        done < /etc/crontab
    fi
}

show_user_crontabs() {
    local user crontab_content line schedule command

    if ! command -v crontab >/dev/null 2>&1; then
        return 0
    fi

    while IFS= read -r user; do
        [ -z "$user" ] && continue
        crontab_content=$(crontab -u "$user" -l 2>/dev/null) || continue
        while IFS= read -r line || [ -n "$line" ]; do
            line="${line%%#*}"
            line="${line#"${line%%[![:space:]]*}"}"
            [ -z "$line" ] && continue
            [[ "$line" == @* ]] && schedule="$line" && command="" || {
                schedule=$(echo "$line" | awk '{print $1" "$2" "$3" "$4" "$5}')
                command=$(echo "$line" | awk '{$1=$2=$3=$4=$5=""; sub(/^ +/, ""); print}')
            }
            if $JSON_OUTPUT; then
                emit_json_entry "user crontab" "$schedule" "$command" "$user"
            else
                printf "  ${CYAN}%-12s${RESET} ${GREEN}%-18s${RESET} %s\n" "$user" "$schedule" "$command"
            fi
        done <<< "$crontab_content"
    done < <(cut -f1 -d: /etc/passwd 2>/dev/null)
}

show_systemd_timers() {
    if ! command -v systemctl >/dev/null 2>&1; then
        return 0
    fi

    while read -r next left last unit activates; do
        [ -z "$unit" ] && continue
        if $JSON_OUTPUT; then
            emit_json_entry "systemd timer" "next: ${next}" "$unit" "$activates"
        else
            printf "  ${YELLOW}%-20s${RESET} ${GREEN}%-16s${RESET} ${DIM}next: %-12s left: %-8s${RESET}\n" \
                "$unit" "$activates" "$next" "$left"
        fi
    done < <(systemctl list-timers --all --no-pager 2>/dev/null | tail -n +2)
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        --no-colors) NO_COLORS=true; shift ;;
        --no-system) INCLUDE_SYSTEM=false; shift ;;
        --no-users) INCLUDE_USERS=false; shift ;;
        --no-timers) INCLUDE_TIMERS=false; shift ;;
        --) shift; break ;;
        -*) echo "Unbekannte Option: $1" >&2; print_help; exit 1 ;;
        *) break ;;
    esac
done

init_colors
first_json=true

if $JSON_OUTPUT; then
    echo -n '['
else
    echo -e "${BOLD}${CYAN}Cron & Timer Overview${RESET}"
fi

if $INCLUDE_SYSTEM; then
    print_header "System Cron (/etc/cron.*, crontab)"
    show_system_cron
fi

if $INCLUDE_USERS; then
    print_header "User Crontabs"
    show_user_crontabs
fi

if $INCLUDE_TIMERS; then
    print_header "systemd Timer"
    show_systemd_timers
fi

if $JSON_OUTPUT; then
    echo ']'
else
    echo ""
    echo -e "${GREEN}${BOLD}Fertig.${RESET}"
fi
