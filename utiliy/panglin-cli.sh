#!/bin/bash

# XPipe and other runners may invoke this script with sh/dash; re-exec with bash.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo "Error: This script requires bash." >&2
    exit 1
fi

# --- Color definitions for the fancy look ---
NC='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

# --- Banner ---
clear
echo -e "${PURPLE}==================================================${NC}"
echo -e "${CYAN}    ██████╗  █████╗ ███╗   ██╗ ██████╗  ██╗     ██╗███╗   ██╗${NC}"
echo -e "${CYAN}    ██╔══██╗██╔══██╗████╗  ██║██╔════╝  ██║     ██║████╗  ██║${NC}"
echo -e "${CYAN}    ██████╔╝███████║██╔██╗ ██║██║  ███╗ ██║     ██║██╔██╗ ██║${NC}"
echo -e "${CYAN}    ██╔═══╝ ██╔══██║██║╚██╗██║██║   ██║ ██║     ██║██║╚██╗██║${NC}"
echo -e "${CYAN}    ██║     ██║  ██║██║ ╚████║╚██████╔╝ ███████╗██║██║ ╚████║${NC}"
echo -e "${CYAN}    ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚══════╝╚═╝╚═╝  ╚═══╝${NC}"
echo -e "${PURPLE}==================================================${NC}"
echo -e "${WHITE}          Pangolin Service Manager & Installer     ${NC}"
echo -e "${PURPLE}==================================================${NC}"
echo ""
echo -e "${PURPLE}==================================================${NC}"

read_hidden() {
    local __var_name="$1"
    local __value=""

    printf "➔ "
    if [ -t 0 ]; then
        stty -echo 2>/dev/null || true
        IFS= read -r __value || __value=""
        stty echo 2>/dev/null || true
        printf "\n"
    else
        IFS= read -r __value || __value=""
    fi

    printf -v "$__var_name" '%s' "$__value"
}

# --- Ensure root privileges for actions that require it ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[✕] Error: Please run this script with sudo or as root!${NC}"
    exit 1
fi

# Helper: install and configure the service (original flow)
install_and_configure() {
    PANGOLIN_PATH=$(which pangolin)
    if [ -z "$PANGOLIN_PATH" ]; then
        echo -e "${YELLOW}[*] Pangolin CLI not found. Installing...${NC}"
        curl -fsSL https://static.pangolin.net/get-cli.sh | bash
        PANGOLIN_PATH=$(which pangolin)
        if [ -z "$PANGOLIN_PATH" ]; then
            echo -e "${RED}[✕] Error installing Pangolin. Aborting.${NC}"
            return 1
        fi
        echo -e "${GREEN}[✓] Pangolin installed successfully!${NC}"
    else
        echo -e "${GREEN}[✓] Pangolin CLI found at: $PANGOLIN_PATH${NC}"
    fi

    echo ""
    echo -e "${WHITE}--- Enter configuration ---${NC}"

    # ID
    while [ -z "$P_ID" ]; do
        echo -e "${BLUE}[?] Please enter Pangolin ID:${NC}"
        read -p "➔ " P_ID
        if [ -z "$P_ID" ]; then
            echo -e "${RED}    ID must not be empty!${NC}"
        fi
    done

    # Secret
    while [ -z "$P_SECRET" ]; do
        echo -e "${BLUE}[?] Please enter Pangolin Secret (input will be hidden):${NC}"
        read_hidden P_SECRET
        if [ -z "$P_SECRET" ]; then
            echo -e "${RED}    Secret must not be empty!${NC}"
        fi
    done

    # Endpoint
    DEFAULT_ENDPOINT="https://aegis.hivegamez.com"
    echo -e "${BLUE}[?] Enter endpoint [Default: $DEFAULT_ENDPOINT]:${NC}"
    read -p "➔ " P_ENDPOINT
    if [ -z "$P_ENDPOINT" ]; then
        P_ENDPOINT=$DEFAULT_ENDPOINT
    fi

    echo ""
    echo -e "${YELLOW}[*] Creating/updating systemd service...${NC}"

    cat <<EOF > /etc/systemd/system/pangolin.service
[Unit]
Description=Pangolin Network Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$PANGOLIN_PATH up --id $P_ID --secret $P_SECRET --endpoint $P_ENDPOINT --attach
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now pangolin

    echo -e "${GREEN}[✓] Service configured and started successfully!${NC}"
    echo ""
    show_status_brief
}

# Helper: show brief status
show_status_brief() {
    echo -e "${PURPLE}==================================================${NC}"
    echo -e "${WHITE}               Current Service Status             ${NC}"
    echo -e "${PURPLE}==================================================${NC}"
    systemctl status pangolin --no-pager | grep -E "Active:|Main PID:|Tasks:" || true
    echo ""
    echo -e "${CYAN}Tip: You can check the status anytime with 'systemctl status pangolin'.${NC}"
    echo -e "${PURPLE}==================================================${NC}"
}

# Manage submenu
manage_menu() {
    while true; do
        echo ""
        echo -e "${WHITE}--- Manage Pangolin Service ---${NC}"
        echo "1) Status"
        echo "2) Start"
        echo "3) Stop"
        echo "4) Restart"
        echo "5) Logs (last 100 lines)"
        echo "6) Enable (start at boot)"
        echo "7) Disable"
        echo "8) Back"
        read -p "Select an action ➔ " MCHOICE
        case "$MCHOICE" in
            1)
                systemctl status pangolin --no-pager || echo "Service not found or failed" ;;
            2)
                systemctl start pangolin && echo "Started" || echo "Failed to start" ;;
            3)
                systemctl stop pangolin && echo "Stopped" || echo "Failed to stop" ;;
            4)
                systemctl restart pangolin && echo "Restarted" || echo "Failed to restart" ;;
            5)
                journalctl -u pangolin -n 100 --no-pager || echo "No logs available" ;;
            6)
                systemctl enable pangolin && echo "Enabled" || echo "Failed to enable" ;;
            7)
                systemctl disable pangolin && echo "Disabled" || echo "Failed to disable" ;;
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
    echo -e "${WHITE}Select an option:${NC}"
    echo "1) Install / Configure service"
    echo "2) Manage service"
    echo "3) Exit"
    read -p "➔ " CHOICE
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