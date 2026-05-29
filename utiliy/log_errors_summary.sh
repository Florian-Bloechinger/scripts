#!/usr/bin/env bash

if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -u

# log_errors_summary.sh - Fehler aus System- und Dienst-Logs zusammenfassen

SINCE="24 hours ago"
LINES=5
JSON_OUTPUT=false
NO_COLORS=false
INCLUDE_AUTH=true
INCLUDE_JOURNAL=true
INCLUDE_NGINX=true
INCLUDE_APACHE=true
INCLUDE_DOCKER=true

print_help() {
    cat <<EOF
Usage: $0 [options]

Fasst Fehler und Warnungen aus gängigen Log-Quellen zusammen.

Options:
  -h, --help          Hilfe anzeigen
  -s, --since=TEXT    Zeitraum (journalctl-Format, Standard: "${SINCE}")
  -n, --lines=N       Beispielzeilen pro Quelle (Standard: ${LINES})
  -j, --json          JSON-Ausgabe
      --no-colors     Farben deaktivieren
      --no-auth       auth.log überspringen
      --no-journal    journalctl überspringen
      --no-nginx      nginx-Logs überspringen
      --no-apache     apache-Logs überspringen
      --no-docker     Docker-Logs überspringen

Beispiele:
  $0
  $0 --since "1 hour ago" --lines 10
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
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g'
}

print_section_header() {
    local name="$1" count="$2"
    $JSON_OUTPUT && return 0
    echo ""
    echo -e "${CYAN}${BOLD}▶ ${name}${RESET} ${DIM}(${count} Treffer)${RESET}"
    echo -e "${DIM}---------------------------------------------${RESET}"
}

print_section_json() {
    local name="$1" count="$2" samples="$3"
    [ "$first_json" = false ] && echo ','
    first_json=false
    printf '{"source":"%s","count":%s,"samples":%s}' \
        "$(json_escape "$name")" "$count" "$samples"
}

summarize_auth_log() {
    local pattern='Failed password|authentication failure|Invalid user|Failed publickey|error|critical'
    local files count samples json_samples

    if compgen -G "/var/log/auth.log*" >/dev/null; then
        files=(/var/log/auth.log*)
    else
        return 0
    fi

    count=$(grep -hEi "$pattern" "${files[@]}" 2>/dev/null | wc -l | tr -d ' ')
    samples=$(grep -hEi "$pattern" "${files[@]}" 2>/dev/null | tail -n "$LINES")

    if $JSON_OUTPUT; then
        json_samples='['
        local first=true line
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            $first || json_samples+=','
            first=false
            json_samples+='"'$(json_escape "$line")'"'
        done <<< "$samples"
        json_samples+=']'
        print_section_json "auth.log" "$count" "$json_samples"
    else
        print_section_header "auth.log" "$count"
        if [ "$count" -eq 0 ]; then
            echo -e "  ${GREEN}Keine Fehler gefunden.${RESET}"
        else
            printf '%s\n' "$samples" | sed 's/^/  /'
        fi
    fi
}

summarize_journal() {
    local count samples json_samples line first=true

    if ! command -v journalctl >/dev/null 2>&1; then
        return 0
    fi

    count=$(journalctl -p err --since "$SINCE" --no-pager 2>/dev/null | sed '/^-- No entries --$/d;/^$/d' | wc -l | tr -d ' ')
    samples=$(journalctl -p err --since "$SINCE" --no-pager 2>/dev/null | tail -n "$LINES")

    if $JSON_OUTPUT; then
        json_samples='['
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            $first || json_samples+=','
            first=false
            json_samples+='"'$(json_escape "$line")'"'
        done <<< "$samples"
        json_samples+=']'
        print_section_json "journalctl (err)" "$count" "$json_samples"
    else
        print_section_header "journalctl (err, since: ${SINCE})" "$count"
        if [ "$count" -eq 0 ]; then
            echo -e "  ${GREEN}Keine Fehler gefunden.${RESET}"
        else
            printf '%s\n' "$samples" | sed 's/^/  /'
        fi
    fi
}

summarize_web_log() {
    local name="$1"
    local file="$2"
    local pattern='\[error\]|ERROR|crit|alert|emerg'
    local count samples json_samples line first=true

    [ -r "$file" ] || return 0

    count=$(grep -Ei "$pattern" "$file" 2>/dev/null | wc -l | tr -d ' ')
    samples=$(grep -Ei "$pattern" "$file" 2>/dev/null | tail -n "$LINES")

    if $JSON_OUTPUT; then
        json_samples='['
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            $first || json_samples+=','
            first=false
            json_samples+='"'$(json_escape "$line")'"'
        done <<< "$samples"
        json_samples+=']'
        print_section_json "$name" "$count" "$json_samples"
    else
        print_section_header "$name" "$count"
        if [ "$count" -eq 0 ]; then
            echo -e "  ${GREEN}Keine Fehler gefunden.${RESET}"
        else
            printf '%s\n' "$samples" | sed 's/^/  /'
        fi
    fi
}

summarize_docker_logs() {
    local count=0 samples="" json_samples='[' first=true container line

    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        return 0
    fi

    while IFS= read -r container; do
        [ -z "$container" ] && continue
        line=$(docker logs "$container" --since "$SINCE" 2>&1 | grep -Ei 'error|exception|fatal|panic' | tail -1)
        if [ -n "$line" ]; then
            count=$((count + 1))
            samples+="${container}: ${line}"$'\n'
        fi
    done < <(docker ps -q 2>/dev/null)

    if $JSON_OUTPUT; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            $first || json_samples+=','
            first=false
            json_samples+='"'$(json_escape "$line")'"'
        done <<< "$samples"
        json_samples+=']'
        print_section_json "docker (running containers)" "$count" "$json_samples"
    else
        print_section_header "docker (running containers)" "$count"
        if [ "$count" -eq 0 ]; then
            echo -e "  ${GREEN}Keine Fehler in laufenden Containern.${RESET}"
        else
            printf '%s\n' "$samples" | head -n "$LINES" | sed 's/^/  /'
        fi
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -s|--since=*) SINCE="${1#*=}"; shift ;;
        -n|--lines=*) LINES="${1#*=}"; shift ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        --no-colors) NO_COLORS=true; shift ;;
        --no-auth) INCLUDE_AUTH=false; shift ;;
        --no-journal) INCLUDE_JOURNAL=false; shift ;;
        --no-nginx) INCLUDE_NGINX=false; shift ;;
        --no-apache) INCLUDE_APACHE=false; shift ;;
        --no-docker) INCLUDE_DOCKER=false; shift ;;
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
    echo -e "${BOLD}${CYAN}Log Error Summary${RESET}"
    echo -e "${DIM}Zeitraum (journal/docker): ${SINCE}${RESET}"
fi

$INCLUDE_AUTH && summarize_auth_log
$INCLUDE_JOURNAL && summarize_journal
$INCLUDE_NGINX && summarize_web_log "nginx error.log" "/var/log/nginx/error.log"
$INCLUDE_APACHE && summarize_web_log "apache error.log" "/var/log/apache2/error.log"
$INCLUDE_DOCKER && summarize_docker_logs

if $JSON_OUTPUT; then
    echo ']'
else
    echo ""
    echo -e "${GREEN}${BOLD}Fertig.${RESET}"
fi
