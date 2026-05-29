#!/usr/bin/env bash

if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -u

# check_ssl_expiry.sh - SSL/TLS-Zertifikate auf Ablauf prüfen (Domain oder lokale Datei)

WARN_DAYS=30
CRITICAL_DAYS=7
JSON_OUTPUT=false
NO_COLORS=false
TARGETS=()

print_help() {
    cat <<EOF
Usage: $0 [options] [target ...]

Prüft SSL/TLS-Zertifikate per Domain (openssl s_client) oder lokaler PEM-Datei.

Targets:
  example.com          Domain (Port 443, optional :PORT)
  /etc/ssl/certs/x.pem Lokale Zertifikatsdatei

Options:
  -h, --help              Hilfe anzeigen
  -w, --warn-days=N       Warnung ab N Tagen (Standard: ${WARN_DAYS})
  -c, --critical-days=N   Kritisch ab N Tagen (Standard: ${CRITICAL_DAYS})
  -f, --file=PATH         Zertifikatsdatei prüfen
  -j, --json              JSON-Ausgabe
      --no-colors         Farben deaktivieren

Beispiele:
  $0 example.com api.example.com:8443
  $0 --file /etc/letsencrypt/live/example.com/fullchain.pem
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

days_until_expiry() {
    local end_date="$1"
    local end_epoch now_epoch
    end_epoch=$(date -d "$end_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$end_date" +%s 2>/dev/null)
    now_epoch=$(date +%s)
    echo $(( (end_epoch - now_epoch) / 86400 ))
}

status_for_days() {
    local days="$1"
    if [ "$days" -lt 0 ]; then
        echo "expired"
    elif [ "$days" -le "$CRITICAL_DAYS" ]; then
        echo "critical"
    elif [ "$days" -le "$WARN_DAYS" ]; then
        echo "warning"
    else
        echo "ok"
    fi
}

color_for_status() {
    case "$1" in
        ok) echo "$GREEN" ;;
        warning) echo "$YELLOW" ;;
        critical|expired) echo "$RED" ;;
        *) echo "$DIM" ;;
    esac
}

get_cert_info_from_file() {
    local file="$1"
    openssl x509 -in "$file" -noout -enddate -subject -issuer 2>/dev/null
}

get_cert_info_from_host() {
    local host="$1"
    local port="$2"
    echo | openssl s_client -servername "$host" -connect "${host}:${port}" 2>/dev/null \
        | openssl x509 -noout -enddate -subject -issuer 2>/dev/null
}

parse_cert_info() {
    local info="$1"
    END_DATE=$(echo "$info" | awk -F= '/notAfter=/ {print $2}')
    SUBJECT=$(echo "$info" | awk -F= '/subject=/ {sub(/^subject=/, ""); print}')
    ISSUER=$(echo "$info" | awk -F= '/issuer=/ {sub(/^issuer=/, ""); print}')
}

check_target() {
    local label="$1"
    local type="$2"
    local host="${3:-}"
    local port="${4:-443}"
    local file="${5:-}"
    local info days status

    if [ "$type" = "file" ]; then
        if [ ! -r "$file" ]; then
            print_result "$label" "file" "error" "" "" "" "Datei nicht lesbar: $file"
            return 1
        fi
        info=$(get_cert_info_from_file "$file")
        label="${label:-$file}"
    else
        info=$(get_cert_info_from_host "$host" "$port")
        label="${label:-${host}:${port}}"
    fi

    if [ -z "$info" ]; then
        print_result "$label" "$type" "error" "" "" "" "Zertifikat konnte nicht gelesen werden"
        return 1
    fi

    parse_cert_info "$info"
    days=$(days_until_expiry "$END_DATE")
    status=$(status_for_days "$days")
    print_result "$label" "$type" "$status" "$days" "$END_DATE" "$SUBJECT" "$ISSUER"
}

print_result() {
    local label="$1" type="$2" status="$3" days="$4" end_date="$5" subject="$6" issuer="$7"
    local color

    if $JSON_OUTPUT; then
        [ "$first_json" = false ] && echo ','
        first_json=false
        printf '{"target":"%s","type":"%s","status":"%s","days_remaining":%s,"expires":"%s","subject":"%s","issuer":"%s"}' \
            "$(json_escape "$label")" "$(json_escape "$type")" "$(json_escape "$status")" \
            "${days:-null}" "$(json_escape "$end_date")" "$(json_escape "$subject")" "$(json_escape "$issuer")"
        return
    fi

    color=$(color_for_status "$status")
    echo -e "${CYAN}${BOLD}${label}${RESET}"
    echo -e "  Status   : ${color}${BOLD}$(echo "$status" | tr '[:lower:]' '[:upper:]')${RESET}"
    [ -n "$days" ] && echo -e "  Verbleibend: ${color}${days} Tag(e)${RESET}"
    [ -n "$end_date" ] && echo -e "  Ablauf   : ${end_date}"
    [ -n "$subject" ] && echo -e "  Subject  : ${DIM}${subject}${RESET}"
    [ -n "$issuer" ] && echo -e "  Issuer   : ${DIM}${issuer}${RESET}"
    echo -e "${DIM}---------------------------------------------${RESET}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -w|--warn-days=*) WARN_DAYS="${1#*=}"; shift ;;
        -c|--critical-days=*) CRITICAL_DAYS="${1#*=}"; shift ;;
        -f|--file=*) TARGETS+=("file:${1#*=}"); shift ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        --no-colors) NO_COLORS=true; shift ;;
        --) shift; break ;;
        -*) echo "Unbekannte Option: $1" >&2; print_help; exit 1 ;;
        *) TARGETS+=("$1"); shift ;;
    esac
done

while [[ $# -gt 0 ]]; do
    TARGETS+=("$1")
    shift
done

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "Keine Targets angegeben." >&2
    print_help
    exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl ist nicht installiert." >&2
    exit 1
fi

init_colors
first_json=true
exit_code=0

if $JSON_OUTPUT; then
    echo -n '['
fi

for target in "${TARGETS[@]}"; do
    if [[ "$target" == file:* ]]; then
        file="${target#file:}"
        check_target "$file" "file" "" "" "$file" || exit_code=1
    elif [[ "$target" == /* ]] || [[ "$target" == *.pem ]] || [[ "$target" == *.crt ]]; then
        check_target "$target" "file" "" "" "$target" || exit_code=1
    else
        host="$target"
        port=443
        if [[ "$target" == *:* ]]; then
            host="${target%%:*}"
            port="${target##*:}"
        fi
        check_target "${host}:${port}" "domain" "$host" "$port" "" || exit_code=1
    fi
done

if $JSON_OUTPUT; then
    echo ']'
else
    echo -e "${BOLD}${CYAN}Fertig.${RESET} Warnung <= ${WARN_DAYS}d | Kritisch <= ${CRITICAL_DAYS}d"
fi

exit "$exit_code"
