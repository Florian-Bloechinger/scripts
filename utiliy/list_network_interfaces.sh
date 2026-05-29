#!/usr/bin/env bash

# Ensure the script runs under bash (not /bin/sh which may be dash)
if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

set -u

# list_network_interfaces.sh - improved
# Features added:
# - CLI flags: --hide-docker, --only-up, --json, --no-colors, --help
# - Robust color handling without referencing unset vars
# - Improved filtering and safer parsing of interfaces
# - Optional JSON output

HIDE_DOCKER=false
ONLY_UP=false
JSON_OUTPUT=false
NO_COLORS=false

print_help() {
    cat <<EOF
Usage: $0 [options]

Options:
  -h, --help        Show this help
  -d, --hide-docker Hide Docker/bridge/veth interfaces
  -u, --only-up     Show only interfaces that are 'up'
  -j, --json        Output JSON instead of pretty text
      --no-colors   Disable colored output
EOF
}

# Parse args (simple)
while [[ ${#} -gt 0 ]]; do
    case "$1" in
        -h|--help) print_help; exit 0 ;;
        -d|--hide-docker) HIDE_DOCKER=true; shift ;;
        -u|--only-up) ONLY_UP=true; shift ;;
        -j|--json) JSON_OUTPUT=true; shift ;;
        --no-colors) NO_COLORS=true; shift ;;
        --) shift; break ;;
        -* ) echo "Unknown option: $1"; print_help; exit 1 ;;
        * ) break ;;
    esac
done

# Colors: use tput if available and colors not disabled
if ! $NO_COLORS && command -v tput &>/dev/null; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    WHITE=$(tput setaf 7)
    RESET=$(tput sgr0)
    BOLD=$(tput bold)
else
    RED=""; GREEN=""; YELLOW=""; BLUE="";
    MAGENTA=""; CYAN=""; WHITE="";
    RESET=""; BOLD="";
fi

filter_docker_names() {
    # common docker/bridge/veth/virtual prefixes
    grep -Ev '^(docker|br-|veth|virbr|lxcbr|tunl|tap|vnet|veth|ifb|macvlan|vxlan)'
}

get_interfaces() {
    if command -v ip &>/dev/null; then
        ip -o link show | awk -F': ' '{print $2}'
    elif command -v ifconfig &>/dev/null; then
        ifconfig -a | grep '^[a-zA-Z0-9]' | awk '{print $1}'
    else
        echo "${RED}Neither 'ip' nor 'ifconfig' command found.${RESET}" >&2
        return 1
    fi
}

json_array_opened=false
json_escape() {
    # simple JSON string escaper
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\\"/g'
}

output_json_start() {
    echo -n '['
    json_array_opened=true
}

output_json_end() {
    echo ']'
}

first_json_item=true

format_and_print() {
    local iface="$1"
    local state mac mtu speed ipv4 ipv6
    [ -d "/sys/class/net/$iface" ] || return
    state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "N/A")
    mtu=$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || echo "N/A")
    speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || echo "Unknown")
    ipv4=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | paste -sd ', ' -)
    ipv6=$(ip -6 addr show "$iface" 2>/dev/null | awk '/inet6 / && !/scope link/ {print $2}' | paste -sd ', ' -)

    if $ONLY_UP && [[ "$state" != "up" ]]; then
        return
    fi

    if $JSON_OUTPUT; then
        if ! $first_json_item; then
            echo -n ','
        fi
        first_json_item=false
        printf '{"interface":"%s","state":"%s","mac":"%s","mtu":"%s","speed":"%s","ipv4":"%s","ipv6":"%s"}' \
            "$(json_escape "$iface")" "$(json_escape "$state")" "$(json_escape "$mac")" \
            "$(json_escape "$mtu")" "$(json_escape "$speed")" "$(json_escape "$ipv4")" "$(json_escape "$ipv6")"
    else
        echo -e "${BOLD}${YELLOW}Interface: ${WHITE}$iface${RESET}"
        echo -e "   ${GREEN}State:    ${RESET}${state:-Unknown}"
        echo -e "   ${GREEN}MAC:      ${RESET}${mac:-N/A}"
        echo -e "   ${GREEN}MTU:      ${RESET}${mtu:-N/A}"
        echo -e "   ${GREEN}Speed:    ${RESET}${speed} Mbps"
        echo -e "   ${GREEN}IPv4:     ${RESET}${ipv4:-N/A}"
        echo -e "   ${GREEN}IPv6:     ${RESET}${ipv6:-N/A}"
        echo -e "${MAGENTA}---------------------------------------------${RESET}"
    fi
}

# Main
clear
echo -e "${BOLD}${CYAN}"
echo "╔════════════════════════════════════════════╗"
echo "║         🌐 Network Interface List          ║"
echo "╚════════════════════════════════════════════╝"
echo -e "${RESET}"

ifs=$(get_interfaces) || exit 1

if $HIDE_DOCKER; then
    # filter list
    ifs=$(printf '%s\n' "$ifs" | filter_docker_names)
fi

if $JSON_OUTPUT; then
    output_json_start
fi

while IFS= read -r iface; do
    [ -z "$iface" ] && continue
    format_and_print "$iface"
done <<<"$ifs"

if $JSON_OUTPUT; then
    output_json_end
    echo
else
    echo -e "${BOLD}${CYAN}✨ Done! Stay connected. ✨${RESET}"
fi
