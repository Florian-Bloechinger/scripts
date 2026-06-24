#!/usr/bin/env bash

# XPipe may invoke scripts with sh/dash — re-exec with bash before any bash-only syntax.
if [ -z "${BASH_VERSION:-}" ]; then
    _script=$(CDPATH= cd -- "$(dirname "$0")" && pwd)/$(basename "$0")
    for _bash in /bin/bash /usr/bin/bash /usr/local/bin/bash bash; do
        if command -v "$_bash" >/dev/null 2>&1 && "$_bash" -c 'exit 0' 2>/dev/null; then
            exec "$_bash" "$_script" "$@"
        fi
    done
    printf 'Error: This script requires bash.\n' >&2
    exit 1
fi

PANGOLIN_MANAGER_VERSION="2.3.0"
NEWT_BIN="/usr/local/bin/newt"
NEWT_ENV_FILE="/etc/newt/newt.env"
NEWT_SERVICE="newt"
DEFAULT_ENDPOINT="https://aegis.hivegamez.com"

# --- Color definitions for the fancy look ---
NC='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

say() {
    printf '%b\n' "$1"
}

# --- Banner ---
clear
say "${PURPLE}==================================================${NC}"
say "${CYAN}    ██████╗  █████╗ ███╗   ██╗ ██████╗  ██╗     ██╗███╗   ██╗${NC}"
say "${CYAN}    ██╔══██╗██╔══██╗████╗  ██║██╔════╝  ██║     ██║████╗  ██║${NC}"
say "${CYAN}    ██████╔╝███████║██╔██╗ ██║██║  ███╗ ██║     ██║██╔██╗ ██║${NC}"
say "${CYAN}    ██╔═══╝ ██╔══██║██║╚██╗██║██║   ██║ ██║     ██║██║╚██╗██║${NC}"
say "${CYAN}    ██║     ██║  ██║██║ ╚████║╚██████╔╝ ███████╗██║██║ ╚████║${NC}"
say "${CYAN}    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚══════╝╚═╝╚═╝  ╚═══╝${NC}"
say "${PURPLE}==================================================${NC}"
say "${WHITE}          Newt Service Manager & Installer            ${NC}"
say "${CYAN}                         v${PANGOLIN_MANAGER_VERSION}${NC}"
say "${PURPLE}==================================================${NC}"
echo ""
say "${PURPLE}==================================================${NC}"

_interactive_tty() {
    if [ -r /dev/tty ] 2>/dev/null && [ -w /dev/tty ] 2>/dev/null; then
        echo /dev/tty
    fi
}

read_prompt() {
    local __var_name="$1"
    local __prompt="${2:-➔ }"
    local __value=""
    local __tty
    __tty=$(_interactive_tty)

    if [ -n "$__tty" ]; then
        printf '%s' "$__prompt" >"$__tty"
        if ! IFS= read -r __value <"$__tty"; then
            return 1
        fi
    elif [ -t 0 ]; then
        if ! IFS= read -r -p "$__prompt" __value; then
            return 1
        fi
    elif ! IFS= read -r __value; then
        return 1
    fi

    printf -v "$__var_name" '%s' "$__value"
}

read_hidden() {
    local __var_name="$1"
    local __value=""
    local __tty
    __tty=$(_interactive_tty)

    if [ -n "$__tty" ]; then
        printf '➔ ' >"$__tty"
        stty -echo <"$__tty" 2>/dev/null || true
        if ! IFS= read -r __value <"$__tty"; then
            stty echo <"$__tty" 2>/dev/null || true
            return 1
        fi
        stty echo <"$__tty" 2>/dev/null || true
        printf '\n' >"$__tty"
    elif [ -t 0 ]; then
        printf '➔ '
        stty -echo 2>/dev/null || true
        if ! IFS= read -r __value; then
            stty echo 2>/dev/null || true
            return 1
        fi
        stty echo 2>/dev/null || true
        printf '\n'
    elif ! IFS= read -r __value; then
        return 1
    fi

    printf -v "$__var_name" '%s' "$__value"
}

# --- Ensure root privileges for actions that require it ---
if [ "$(id -u)" -ne 0 ]; then
    say "${RED}[✕] Error: Please run this script with sudo or as root!${NC}"
    exit 1
fi

MAX_PROMPT_ATTEMPTS=3

prompt_required() {
    local var_name=$1
    local label=$2
    local is_secret=${3:-false}
    local attempts=0
    local value=""

    while [ -z "$value" ] && [ "$attempts" -lt "$MAX_PROMPT_ATTEMPTS" ]; do
        if [ "$is_secret" = true ]; then
            say "${BLUE}[?] Please enter $label (input will be hidden):${NC}"
            if ! read_hidden value; then
                say "${RED}[✕] Input failed. Is the terminal interactive?${NC}"
                return 1
            fi
        else
            say "${BLUE}[?] Please enter $label:${NC}"
            if ! read_prompt value "➔ "; then
                say "${RED}[✕] Input failed. Is the terminal interactive?${NC}"
                return 1
            fi
        fi

        if [ -z "$value" ]; then
            say "${RED}    $label must not be empty!${NC}"
            attempts=$((attempts + 1))
        fi
    done

    if [ -z "$value" ]; then
        say "${RED}[✕] Too many attempts. Aborting.${NC}"
        return 1
    fi

    printf -v "$var_name" '%s' "$value"
}

# Helper: install and configure the Newt service
install_and_configure() {
    NEWT_PATH=$(command -v newt 2>/dev/null || true)
    if [ -z "$NEWT_PATH" ] && [ -x "$NEWT_BIN" ]; then
        NEWT_PATH="$NEWT_BIN"
    fi

    if [ -z "$NEWT_PATH" ]; then
        say "${YELLOW}[*] Newt not found. Installing...${NC}"
        if ! curl -fsSL https://static.pangolin.net/get-newt.sh | bash; then
            say "${RED}[✕] Error installing Newt. Aborting.${NC}"
            return 1
        fi
        NEWT_PATH=$(command -v newt 2>/dev/null || true)
        if [ -z "$NEWT_PATH" ] && [ -x "$NEWT_BIN" ]; then
            NEWT_PATH="$NEWT_BIN"
        fi
        if [ -z "$NEWT_PATH" ]; then
            say "${RED}[✕] Newt installed but binary not found. Aborting.${NC}"
            return 1
        fi
        say "${GREEN}[✓] Newt installed successfully!${NC}"
    else
        say "${GREEN}[✓] Newt found at: $NEWT_PATH${NC}"
    fi

    echo ""
    say "${WHITE}--- Enter configuration ---${NC}"

    NEWT_ID="${NEWT_ID:-${PANGOLIN_ID:-}}"
    if [ -z "$NEWT_ID" ]; then
        prompt_required NEWT_ID "Newt ID" || return 1
    fi

    NEWT_SECRET="${NEWT_SECRET:-${PANGOLIN_SECRET:-}}"
    if [ -z "$NEWT_SECRET" ]; then
        prompt_required NEWT_SECRET "Newt Secret" true || return 1
    fi

    PANGOLIN_ENDPOINT="${PANGOLIN_ENDPOINT:-}"
    if [ -z "$PANGOLIN_ENDPOINT" ]; then
        say "${BLUE}[?] Enter endpoint [Default: $DEFAULT_ENDPOINT]:${NC}"
        read_prompt PANGOLIN_ENDPOINT "➔ "
        if [ -z "$PANGOLIN_ENDPOINT" ]; then
            PANGOLIN_ENDPOINT=$DEFAULT_ENDPOINT
        fi
    fi

    echo ""
    say "${YELLOW}[*] Creating environment file...${NC}"
    install -d -m 0755 /etc/newt
    printf 'NEWT_ID=%s\nNEWT_SECRET=%s\nPANGOLIN_ENDPOINT=%s\n' \
        "$NEWT_ID" "$NEWT_SECRET" "$PANGOLIN_ENDPOINT" > "$NEWT_ENV_FILE"
    chmod 600 "$NEWT_ENV_FILE"

    echo ""
    say "${YELLOW}[*] Creating/updating systemd service...${NC}"

    cat <<EOF > "/etc/systemd/system/${NEWT_SERVICE}.service"
[Unit]
Description=Newt
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=root
Group=root
EnvironmentFile=$NEWT_ENV_FILE
ExecStart=$NEWT_PATH
Restart=always
RestartSec=2
UMask=0077

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$NEWT_SERVICE"

    say "${GREEN}[✓] Service configured and started successfully!${NC}"
    echo ""
    show_status_brief
}

# Helper: show brief status
show_status_brief() {
    say "${PURPLE}==================================================${NC}"
    say "${WHITE}               Current Service Status             ${NC}"
    say "${PURPLE}==================================================${NC}"
    systemctl status "$NEWT_SERVICE" --no-pager | grep -E "Active:|Main PID:|Tasks:" || true
    echo ""
    say "${CYAN}Tip: You can check the status anytime with 'systemctl status $NEWT_SERVICE'.${NC}"
    say "${PURPLE}==================================================${NC}"
}

# Manage submenu
manage_menu() {
    while true; do
        echo ""
        say "${WHITE}--- Manage Newt Service ---${NC}"
        echo "1) Status"
        echo "2) Start"
        echo "3) Stop"
        echo "4) Restart"
        echo "5) Logs (last 100 lines)"
        echo "6) Enable (start at boot)"
        echo "7) Disable"
        echo "8) Back"
        read_prompt MCHOICE "Select an action ➔ "
        case "$MCHOICE" in
            1)
                systemctl status "$NEWT_SERVICE" --no-pager || echo "Service not found or failed" ;;
            2)
                systemctl start "$NEWT_SERVICE" && echo "Started" || echo "Failed to start" ;;
            3)
                systemctl stop "$NEWT_SERVICE" && echo "Stopped" || echo "Failed to stop" ;;
            4)
                systemctl restart "$NEWT_SERVICE" && echo "Restarted" || echo "Failed to restart" ;;
            5)
                journalctl -u "$NEWT_SERVICE" -n 100 --no-pager || echo "No logs available" ;;
            6)
                systemctl enable "$NEWT_SERVICE" && echo "Enabled" || echo "Failed to enable" ;;
            7)
                systemctl disable "$NEWT_SERVICE" && echo "Disabled" || echo "Failed to disable" ;;
            8)
                break ;;
            *)
                echo "Invalid option" ;;
        esac
    done
}

# Main menu
while true; do
    echo ""
    say "${WHITE}Select an option:${NC}"
    echo "1) Install / Configure service"
    echo "2) Manage service"
    echo "3) Exit"
    read_prompt CHOICE "➔ "
    case "$CHOICE" in
        1)
            install_and_configure ;;
        2)
            manage_menu ;;
        3)
            echo "Exiting."; exit 0 ;;
        *)
            echo "Invalid selection" ;;
    esac
done
