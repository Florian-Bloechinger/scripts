#!/usr/bin/env bash

if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -u

# update_system.sh - System-Updates mit Vorab-Checks (apt)

DRY_RUN=false
UPGRADE=false
AUTO_YES=false
JSON_OUTPUT=false
NO_COLORS=false
MIN_DISK_MB=500

print_help() {
    cat <<EOF
Usage: $0 [options]

Führt apt update aus und optional apt upgrade mit Sicherheits-Checks.

Options:
  -h, --help          Hilfe anzeigen
  -u, --upgrade       Nach update auch upgrade ausführen
  -y, --yes           Ohne Rückfrage bestätigen
  -n, --dry-run       Nur prüfen und anzeigen, nichts installieren
  -j, --json          JSON-Ausgabe
      --no-colors     Farben deaktivieren
      --min-disk=MB   Mindest-Festplattenspace in MB (Standard: ${MIN_DISK_MB})

Beispiele:
  $0                  Update-Index + verfügbare Pakete anzeigen
  $0 --upgrade --yes  Updates installieren
  $0 --dry-run --upgrade
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

require_root_for_upgrade() {
    if $UPGRADE && [ "$(id -u)" -ne 0 ]; then
        echo "Upgrade erfordert root (sudo)." >&2
        exit 1
    fi
}

require_apt() {
    if ! command -v apt >/dev/null 2>&1; then
        echo "apt ist nicht verfügbar (kein Debian/Ubuntu-System?)." >&2
        exit 1
    fi
}

check_disk_space() {
    local avail_kb avail_mb
    avail_kb=$(df / /var 2>/dev/null | awk 'NR>1 {print $4}' | sort -n | head -1)
    avail_mb=$(( avail_kb / 1024 ))
    [ "$avail_mb" -lt "$MIN_DISK_MB" ] && return 1
    echo "$avail_mb"
    return 0
}

check_failed_services() {
    systemctl list-units --failed --type=service --no-legend 2>/dev/null | awk '{print $1}'
}

count_upgradable() {
    apt list --upgradable 2>/dev/null | tail -n +2 | sed '/^$/d' | wc -l | tr -d ' '
}

count_security_updates() {
    apt-get -s upgrade 2>/dev/null | awk '/^Inst / && tolower($0) ~ /security/ {c++} END {print c+0}'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -u|--upgrade) UPGRADE=true; shift ;;
        -y|--yes) AUTO_YES=true; shift ;;
        -n|--dry-run) DRY_RUN=true; shift ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        --no-colors) NO_COLORS=true; shift ;;
        --min-disk=*) MIN_DISK_MB="${1#*=}"; shift ;;
        --) shift; break ;;
        -*) echo "Unbekannte Option: $1" >&2; print_help; exit 1 ;;
        *) break ;;
    esac
done

require_apt
require_root_for_upgrade
init_colors

disk_mb=$(check_disk_space) || disk_mb=0
failed_services=$(check_failed_services)
failed_count=$(printf '%s\n' "$failed_services" | sed '/^$/d' | wc -l | tr -d ' ')

if [ "$disk_mb" -lt "$MIN_DISK_MB" ]; then
    msg="Zu wenig Speicher: ${disk_mb}MB verfügbar (Minimum: ${MIN_DISK_MB}MB)"
    if $JSON_OUTPUT; then
        printf '{"status":"error","message":"%s"}\n' "$msg"
    else
        echo -e "${RED}[✕]${RESET} $msg" >&2
    fi
    exit 1
fi

if ! $JSON_OUTPUT; then
    echo -e "${BOLD}${CYAN}System Update${RESET}"
    echo -e "${DIM}---------------------------------------------${RESET}"
    echo -e "Freier Speicher : ${GREEN}${disk_mb} MB${RESET}"
    echo -e "Failed Services : ${failed_count}"
    if [ "$failed_count" -gt 0 ]; then
        printf '%s\n' "$failed_services" | sed 's/^/  - /'
        echo -e "${YELLOW}[!] Warnung: Es gibt fehlgeschlagene Dienste.${RESET}"
    fi
    echo ""
fi

if $DRY_RUN; then
    $JSON_OUTPUT || echo -e "${YELLOW}[Dry-Run]${RESET} apt update wird simuliert."
else
    $JSON_OUTPUT || echo -e "${CYAN}[*]${RESET} apt update..."
    if $JSON_OUTPUT; then
        apt update >/dev/null 2>&1 || {
            printf '{"status":"error","message":"apt update fehlgeschlagen"}\n'
            exit 1
        }
    elif ! apt update; then
        exit 1
    fi
fi

total=$(count_upgradable)
security=$(count_security_updates)

if $JSON_OUTPUT; then
    printf '{"status":"ok","disk_mb":%s,"failed_services":%s,"upgradable":%s,"security_updates":%s,"upgrade":%s,"dry_run":%s}\n' \
        "$disk_mb" "$failed_count" "$total" "$security" "$UPGRADE" "$DRY_RUN"
else
    echo -e "${DIM}---------------------------------------------${RESET}"
    echo -e "Verfügbare Updates    : ${BOLD}${total}${RESET}"
    echo -e "Sicherheitsupdates    : ${YELLOW}${security}${RESET}"
fi

if ! $UPGRADE; then
    $JSON_OUTPUT || echo -e "${DIM}Tipp: Mit --upgrade Updates installieren.${RESET}"
    exit 0
fi

if $DRY_RUN; then
    $JSON_OUTPUT || echo -e "${YELLOW}[Dry-Run]${RESET} apt upgrade --dry-run:"
    apt-get -s upgrade 2>/dev/null
    exit 0
fi

if ! $AUTO_YES; then
    echo -e "${YELLOW}[?]${RESET} ${total} Update(s) installieren? [j/N]"
    read -r answer
    case "$answer" in
        j|J|y|Y) ;;
        *) echo "Abgebrochen."; exit 0 ;;
    esac
fi

$JSON_OUTPUT || echo -e "${CYAN}[*]${RESET} apt upgrade..."
if apt upgrade -y; then
    $JSON_OUTPUT || echo -e "${GREEN}[✓]${RESET} Upgrade abgeschlossen."
else
    $JSON_OUTPUT && printf '{"status":"error","message":"apt upgrade fehlgeschlagen"}\n'
    exit 1
fi

$JSON_OUTPUT || echo -e "${GREEN}${BOLD}Fertig.${RESET}"
