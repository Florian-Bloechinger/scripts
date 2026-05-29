#!/usr/bin/env bash

if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -u

# docker_cleanup.sh - Ungenutzte Docker-Ressourcen bereinigen

DRY_RUN=false
FORCE=false
JSON_OUTPUT=false
NO_COLORS=false
CLEAN_CONTAINERS=false
CLEAN_IMAGES=false
CLEAN_VOLUMES=false
CLEAN_NETWORKS=false
CLEAN_BUILD_CACHE=false
CLEAN_ALL=false

print_help() {
    cat <<EOF
Usage: $0 [options]

Bereinigt ungenutzte Docker-Ressourcen. Standard: nur Anzeige (Dry-Run).

Options:
  -h, --help          Hilfe anzeigen
  -n, --dry-run       Nur anzeigen, nichts löschen (Standard)
  -y, --yes           Löschen ohne Rückfrage
  -a, --all           Alles bereinigen (Container, Images, Volumes, Networks, Build-Cache)
      --containers    Gestoppte Container entfernen
      --images        Ungenutzte Images entfernen
      --volumes       Ungenutzte Volumes entfernen
      --networks      Ungenutzte Netzwerke entfernen
      --build-cache   Build-Cache entfernen
  -j, --json          JSON-Ausgabe
      --no-colors     Farben deaktivieren

Beispiele:
  $0                  Vorschau der reclaimbaren Ressourcen
  $0 --all --yes      Alles bereinigen
  $0 --images --yes   Nur ungenutzte Images löschen
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

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker ist nicht installiert." >&2
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo "Docker-Daemon nicht erreichbar." >&2
        exit 1
    fi
}

count_stopped_containers() {
    docker ps -aq -f status=exited -f status=created 2>/dev/null | wc -l | tr -d ' '
}

count_dangling_images() {
    docker images -f dangling=true -q 2>/dev/null | wc -l | tr -d ' '
}

count_unused_images() {
    docker images -q 2>/dev/null | wc -l | tr -d ' '
}

count_unused_volumes() {
    docker volume ls -qf dangling=true 2>/dev/null | wc -l | tr -d ' '
}

count_unused_networks() {
    docker network ls --filter dangling=true -q 2>/dev/null | wc -l | tr -d ' '
}

get_reclaimable_space() {
    docker system df --format '{{.Reclaimable}}' 2>/dev/null | head -1
}

run_cleanup() {
    local action="$1"
    local label="$2"
    local cmd=("${@:3}")

    if $JSON_OUTPUT; then
        return 0
    fi

    if $DRY_RUN; then
        echo -e "${YELLOW}[Dry-Run]${RESET} ${label}"
        return 0
    fi

    if ! $FORCE; then
        echo -e "${YELLOW}[?]${RESET} ${label} — fortfahren? [j/N]"
        read -r answer
        case "$answer" in
            j|J|y|Y) ;;
            *) echo "Übersprungen."; return 0 ;;
        esac
    fi

    echo -e "${CYAN}[*]${RESET} ${label}..."
    if "${cmd[@]}"; then
        echo -e "${GREEN}[✓]${RESET} ${label} abgeschlossen."
    else
        echo -e "${RED}[✕]${RESET} ${label} fehlgeschlagen." >&2
        return 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -y|--yes) FORCE=true; DRY_RUN=false; shift ;;
        -a|--all) CLEAN_ALL=true; shift ;;
        --containers) CLEAN_CONTAINERS=true; shift ;;
        --images) CLEAN_IMAGES=true; shift ;;
        --volumes) CLEAN_VOLUMES=true; shift ;;
        --networks) CLEAN_NETWORKS=true; shift ;;
        --build-cache) CLEAN_BUILD_CACHE=true; shift ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        --no-colors) NO_COLORS=true; shift ;;
        --) shift; break ;;
        -*) echo "Unbekannte Option: $1" >&2; print_help; exit 1 ;;
        *) break ;;
    esac
done

# Default: dry-run preview only
if ! $CLEAN_ALL && ! $CLEAN_CONTAINERS && ! $CLEAN_IMAGES && ! $CLEAN_VOLUMES && ! $CLEAN_NETWORKS && ! $CLEAN_BUILD_CACHE; then
    DRY_RUN=true
fi

if $CLEAN_ALL; then
    CLEAN_CONTAINERS=true
    CLEAN_IMAGES=true
    CLEAN_VOLUMES=true
    CLEAN_NETWORKS=true
    CLEAN_BUILD_CACHE=true
    DRY_RUN=false
fi

require_docker
init_colors

stopped=$(count_stopped_containers)
dangling=$(count_dangling_images)
volumes=$(count_unused_volumes)
networks=$(count_unused_networks)
reclaimable=$(get_reclaimable_space)

if $JSON_OUTPUT; then
    printf '{"stopped_containers":%s,"dangling_images":%s,"unused_volumes":%s,"unused_networks":%s,"reclaimable":"%s","dry_run":%s}\n' \
        "$stopped" "$dangling" "$volumes" "$networks" "$reclaimable" "$DRY_RUN"
else
    echo -e "${BOLD}${CYAN}Docker Cleanup${RESET}"
    echo -e "${DIM}---------------------------------------------${RESET}"
    echo -e "Gestoppte Container : ${YELLOW}${stopped}${RESET}"
    echo -e "Dangling Images     : ${YELLOW}${dangling}${RESET}"
    echo -e "Ungenutzte Volumes  : ${YELLOW}${volumes}${RESET}"
    echo -e "Ungenutzte Networks : ${YELLOW}${networks}${RESET}"
    echo -e "Reclaimable Space   : ${GREEN}${reclaimable:-N/A}${RESET}"
    echo ""
    docker system df 2>/dev/null || true
    echo -e "${DIM}---------------------------------------------${RESET}"
fi

if $DRY_RUN && ! $CLEAN_ALL && ! $CLEAN_CONTAINERS && ! $CLEAN_IMAGES && ! $CLEAN_VOLUMES && ! $CLEAN_NETWORKS && ! $CLEAN_BUILD_CACHE; then
    $JSON_OUTPUT || echo -e "${DIM}Tipp: Mit --all --yes alles bereinigen.${RESET}"
    exit 0
fi

exit_code=0

if $CLEAN_CONTAINERS; then
    run_cleanup prune_containers "Gestoppte Container entfernen" \
        docker container prune -f || exit_code=1
fi

if $CLEAN_IMAGES; then
    run_cleanup prune_images "Ungenutzte Images entfernen" \
        docker image prune -a -f || exit_code=1
fi

if $CLEAN_VOLUMES; then
    run_cleanup prune_volumes "Ungenutzte Volumes entfernen" \
        docker volume prune -f || exit_code=1
fi

if $CLEAN_NETWORKS; then
    run_cleanup prune_networks "Ungenutzte Netzwerke entfernen" \
        docker network prune -f || exit_code=1
fi

if $CLEAN_BUILD_CACHE; then
    run_cleanup prune_build_cache "Build-Cache entfernen" \
        docker builder prune -a -f || exit_code=1
fi

$JSON_OUTPUT || echo -e "${GREEN}${BOLD}Fertig.${RESET}"
exit "$exit_code"
