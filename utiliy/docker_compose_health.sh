#!/usr/bin/env bash

if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -u

# docker_compose_health.sh - Docker Compose Stacks auf Gesundheit prüfen

SEARCH_PATH="."
JSON_OUTPUT=false
NO_COLORS=false
RECURSIVE=false

print_help() {
    cat <<EOF
Usage: $0 [options] [path]

Prüft docker compose Projekte: Container-Status, Healthchecks, Restart-Counts.

Options:
  -h, --help          Hilfe anzeigen
  -p, --path=PATH     Startverzeichnis (Standard: .)
  -r, --recursive     compose-Dateien rekursiv suchen
  -j, --json          JSON-Ausgabe
      --no-colors     Farben deaktivieren

Beispiele:
  $0 /opt/stacks
  $0 --recursive /srv
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

detect_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD=(docker compose)
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD=(docker-compose)
    else
        echo "docker compose / docker-compose nicht gefunden." >&2
        exit 1
    fi
}

require_docker() {
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        echo "Docker-Daemon nicht erreichbar." >&2
        exit 1
    fi
}

find_compose_files() {
    local base="$1"
    if $RECURSIVE; then
        find "$base" \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yml' -o -name 'compose.yaml' \) 2>/dev/null
    else
        for name in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
            [ -f "${base}/${name}" ] && echo "${base}/${name}"
        done
    fi
}

status_color() {
    case "$1" in
        running|healthy) echo "$GREEN" ;;
        starting|unhealthy) echo "$YELLOW" ;;
        exited|dead|*) echo "$RED" ;;
    esac
}

check_compose_project() {
    local compose_file="$1"
    local dir project containers overall="ok"
    local -a container_entries=()

    dir=$(dirname "$compose_file")
    project=$(basename "$dir")

    if ! "${COMPOSE_CMD[@]}" -f "$compose_file" ps --format json >/dev/null 2>&1; then
        # Fallback for older compose without json format
        containers=$("${COMPOSE_CMD[@]}" -f "$compose_file" ps 2>/dev/null)
        if $JSON_OUTPUT; then
            [ "$first_json" = false ] && echo ','
            first_json=false
            printf '{"project":"%s","path":"%s","status":"error","message":"compose ps fehlgeschlagen"}' \
                "$(json_escape "$project")" "$(json_escape "$compose_file")"
        else
            echo -e "${RED}[✕]${RESET} ${project} (${compose_file}): compose ps fehlgeschlagen"
        fi
        return 1
    fi

    if $JSON_OUTPUT; then
        local json_containers='[' first_c=true name state health restarts
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            name=$(echo "$line" | sed -n 's/.*"Name":"\([^"]*\)".*/\1/p')
            state=$(echo "$line" | sed -n 's/.*"State":"\([^"]*\)".*/\1/p')
            health=$(echo "$line" | sed -n 's/.*"Health":"\([^"]*\)".*/\1/p')
            restarts=$(echo "$line" | sed -n 's/.*"RestartCount":\([0-9]*\).*/\1/p')
            [ -z "$name" ] && continue
            [ "$state" != "running" ] && overall="degraded"
            [ "$health" = "unhealthy" ] && overall="degraded"
            $first_c || json_containers+=','
            first_c=false
            json_containers+='{"name":"'$(json_escape "$name")'","state":"'$(json_escape "$state")'","health":"'$(json_escape "$health")'","restarts":'${restarts:-0}'}'
        done < <("${COMPOSE_CMD[@]}" -f "$compose_file" ps --format json 2>/dev/null)
        json_containers+=']'
        [ "$first_json" = false ] && echo ','
        first_json=false
        printf '{"project":"%s","path":"%s","status":"%s","containers":%s}' \
            "$(json_escape "$project")" "$(json_escape "$compose_file")" "$overall" "$json_containers"
    else
        echo -e "${CYAN}${BOLD}▶ ${project}${RESET} ${DIM}${compose_file}${RESET}"
        "${COMPOSE_CMD[@]}" -f "$compose_file" ps 2>/dev/null | tail -n +2 | while read -r name _ image cmd status ports; do
            color=$(status_color "$status")
            echo -e "  ${color}●${RESET} ${name} — ${status}"
            [ "$status" != "running" ] && overall="degraded"
        done

        # Health + restart details via docker inspect
        while IFS= read -r cid; do
            [ -z "$cid" ] && continue
            docker inspect "$cid" --format \
                '  {{.Name}} | State: {{.State.Status}} | Health: {{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}} | Restarts: {{.RestartCount}}' 2>/dev/null \
                | sed 's|^/||'
        done < <("${COMPOSE_CMD[@]}" -f "$compose_file" ps -q 2>/dev/null)

        if [ "$overall" = "ok" ]; then
            echo -e "  ${GREEN}Status: OK${RESET}"
        else
            echo -e "  ${YELLOW}Status: DEGRADED${RESET}"
        fi
        echo -e "${DIM}---------------------------------------------${RESET}"
    fi

    [ "$overall" = "ok" ]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -p|--path=*) SEARCH_PATH="${1#*=}"; shift ;;
        -r|--recursive) RECURSIVE=true; shift ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        --no-colors) NO_COLORS=true; shift ;;
        --) shift; break ;;
        -*) echo "Unbekannte Option: $1" >&2; print_help; exit 1 ;;
        *) SEARCH_PATH="$1"; shift ;;
    esac
done

if [ ! -d "$SEARCH_PATH" ]; then
    echo "Verzeichnis nicht gefunden: $SEARCH_PATH" >&2
    exit 1
fi

require_docker
detect_compose_cmd
init_colors

mapfile -t compose_files < <(find_compose_files "$SEARCH_PATH")

if [ ${#compose_files[@]} -eq 0 ]; then
    echo "Keine compose-Dateien in ${SEARCH_PATH} gefunden." >&2
    exit 1
fi

first_json=true
exit_code=0

if $JSON_OUTPUT; then
    echo -n '['
else
    echo -e "${BOLD}${CYAN}Docker Compose Health${RESET}"
    echo -e "${DIM}${#compose_files[@]} Projekt(e) gefunden${RESET}"
    echo -e "${DIM}---------------------------------------------${RESET}"
fi

for compose_file in "${compose_files[@]}"; do
    check_compose_project "$compose_file" || exit_code=1
done

if $JSON_OUTPUT; then
    echo ']'
else
    echo -e "${GREEN}${BOLD}Fertig.${RESET}"
fi

exit "$exit_code"
