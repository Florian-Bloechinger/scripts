#!/bin/sh
# XPipe runs scripts with sh/dash — always re-exec the embedded CLI under bash.
# Self-contained: no dependency on utiliy/ being deployed separately.
for _bash in /bin/bash /usr/bin/bash /usr/local/bin/bash bash; do
    if command -v "$_bash" >/dev/null 2>&1 && "$_bash" -c 'exit 0' 2>/dev/null; then
        exec "$_bash" -s "$@" <<'NEWT_CLI'
PANGOLIN_MANAGER_VERSION="2.3.3"
NEWT_BIN="/usr/local/bin/newt"
NEWT_ENV_FILE="/etc/newt/newt.env"
NEWT_SERVICE="newt"
DEFAULT_ENDPOINT="https://aegis.hivegamez.com"

# Capture one-shot env overrides (non-interactive install); do not reuse later.
_ENV_NEWT_ID="${NEWT_ID:-${PANGOLIN_ID:-}}"
_ENV_NEWT_SECRET="${NEWT_SECRET:-${PANGOLIN_SECRET:-}}"
_ENV_PANGOLIN_ENDPOINT="${PANGOLIN_ENDPOINT:-}"
unset NEWT_ID NEWT_SECRET PANGOLIN_ID PANGOLIN_SECRET PANGOLIN_ENDPOINT

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

if [ "$(id -u)" -ne 0 ]; then
    say "${RED}[✕] Error: Please run this script with sudo or as root!${NC}"
    exit 1
fi

MAX_PROMPT_ATTEMPTS=3

load_existing_config() {
    CFG_NEWT_ID=""
    CFG_NEWT_SECRET=""
    CFG_PANGOLIN_ENDPOINT=""
    if [ ! -f "$NEWT_ENV_FILE" ]; then
        return 0
    fi
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            NEWT_ID=*) CFG_NEWT_ID="${_line#NEWT_ID=}" ;;
            NEWT_SECRET=*) CFG_NEWT_SECRET="${_line#NEWT_SECRET=}" ;;
            PANGOLIN_ENDPOINT=*) CFG_PANGOLIN_ENDPOINT="${_line#PANGOLIN_ENDPOINT=}" ;;
        esac
    done < "$NEWT_ENV_FILE"
}

prompt_with_default() {
    local var_name=$1
    local label=$2
    local default=$3
    local attempts=0
    local value=""

    while [ "$attempts" -lt "$MAX_PROMPT_ATTEMPTS" ]; do
        if [ -n "$default" ]; then
            say "${BLUE}[?] $label [current: $default]:${NC}"
        else
            say "${BLUE}[?] Please enter $label:${NC}"
        fi

        if ! read_prompt value "➔ "; then
            say "${RED}[✕] Input failed. Is the terminal interactive?${NC}"
            return 1
        fi

        if [ -z "$value" ] && [ -n "$default" ]; then
            value=$default
        fi

        if [ -n "$value" ]; then
            printf -v "$var_name" '%s' "$value"
            return 0
        fi

        say "${RED}    $label must not be empty!${NC}"
        attempts=$((attempts + 1))
    done

    say "${RED}[✕] Too many attempts. Aborting.${NC}"
    return 1
}

resolve_newt_path() {
    NEWT_PATH=$(command -v newt 2>/dev/null || true)
    if [ -z "$NEWT_PATH" ] && [ -x "$NEWT_BIN" ]; then
        NEWT_PATH="$NEWT_BIN"
    fi
}

configure_newt() {
    local cfg_id cfg_secret cfg_endpoint
    local newt_id newt_secret pangolin_endpoint

    load_existing_config
    cfg_id="$CFG_NEWT_ID"
    cfg_secret="$CFG_NEWT_SECRET"
    cfg_endpoint="${CFG_PANGOLIN_ENDPOINT:-$DEFAULT_ENDPOINT}"

    if [ -f "$NEWT_ENV_FILE" ]; then
        say "${CYAN}Press Enter to keep current values.${NC}"
    fi

    if [ -n "$_ENV_NEWT_ID" ] && [ -n "$_ENV_NEWT_SECRET" ] && [ -n "$_ENV_PANGOLIN_ENDPOINT" ]; then
        newt_id="$_ENV_NEWT_ID"
        newt_secret="$_ENV_NEWT_SECRET"
        pangolin_endpoint="$_ENV_PANGOLIN_ENDPOINT"
        say "${CYAN}Using credentials from environment.${NC}"
    else
        prompt_with_default newt_id "Newt ID" "$cfg_id" || return 1
        prompt_with_default newt_secret "Newt Secret" "$cfg_secret" || return 1
        prompt_with_default pangolin_endpoint "Endpoint" "$cfg_endpoint" || return 1
    fi

    echo ""
    say "${YELLOW}[*] Updating environment file...${NC}"
    install -d -m 0755 /etc/newt
    printf 'NEWT_ID=%s\nNEWT_SECRET=%s\nPANGOLIN_ENDPOINT=%s\n' \
        "$newt_id" "$newt_secret" "$pangolin_endpoint" > "$NEWT_ENV_FILE"
    chmod 600 "$NEWT_ENV_FILE"

    if [ -n "$NEWT_PATH" ]; then
        echo ""
        say "${YELLOW}[*] Updating systemd service...${NC}"
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
    fi

    systemctl daemon-reload
    systemctl enable "$NEWT_SERVICE" 2>/dev/null || true
    systemctl restart "$NEWT_SERVICE"

    say "${GREEN}[✓] Configuration updated and service restarted.${NC}"
    echo ""
    show_status_brief
}

reconfigure_credentials() {
    resolve_newt_path
    if [ -z "$NEWT_PATH" ]; then
        say "${RED}[✕] Newt is not installed. Use Install / Configure first.${NC}"
        return 1
    fi
    echo ""
    say "${WHITE}--- Reconfigure credentials ---${NC}"
    configure_newt
}

install_and_configure() {
    resolve_newt_path

    if [ -z "$NEWT_PATH" ]; then
        say "${YELLOW}[*] Newt not found. Installing...${NC}"
        if ! curl -fsSL https://static.pangolin.net/get-newt.sh | bash; then
            say "${RED}[✕] Error installing Newt. Aborting.${NC}"
            return 1
        fi
        resolve_newt_path
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
    configure_newt
}

show_status_brief() {
    say "${PURPLE}==================================================${NC}"
    say "${WHITE}               Current Service Status             ${NC}"
    say "${PURPLE}==================================================${NC}"
    systemctl status "$NEWT_SERVICE" --no-pager | grep -E "Active:|Main PID:|Tasks:" || true
    echo ""
    say "${CYAN}Tip: You can check the status anytime with 'systemctl status $NEWT_SERVICE'.${NC}"
    say "${PURPLE}==================================================${NC}"
}

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
        echo "8) Reconfigure credentials"
        echo "9) Back"
        read_prompt MCHOICE "Select an action ➔ "
        case "$MCHOICE" in
            1) systemctl status "$NEWT_SERVICE" --no-pager || echo "Service not found or failed" ;;
            2) systemctl start "$NEWT_SERVICE" && echo "Started" || echo "Failed to start" ;;
            3) systemctl stop "$NEWT_SERVICE" && echo "Stopped" || echo "Failed to stop" ;;
            4) systemctl restart "$NEWT_SERVICE" && echo "Restarted" || echo "Failed to restart" ;;
            5) journalctl -u "$NEWT_SERVICE" -n 100 --no-pager || echo "No logs available" ;;
            6) systemctl enable "$NEWT_SERVICE" && echo "Enabled" || echo "Failed to enable" ;;
            7) systemctl disable "$NEWT_SERVICE" && echo "Disabled" || echo "Failed to disable" ;;
            8) reconfigure_credentials ;;
            9) break ;;
            *) echo "Invalid option" ;;
        esac
    done
}

while true; do
    echo ""
    say "${WHITE}Select an option:${NC}"
    echo "1) Install / Configure service"
    echo "2) Manage service"
    echo "3) Exit"
    read_prompt CHOICE "➔ "
    case "$CHOICE" in
        1) install_and_configure ;;
        2) manage_menu ;;
        3) echo "Exiting."; exit 0 ;;
        *) echo "Invalid selection" ;;
    esac
done
NEWT_CLI
    fi
done

printf 'Error: bash is required.\n' >&2
exit 1
