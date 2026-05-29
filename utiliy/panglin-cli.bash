#!/bin/bash

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

# --- Check for root privileges ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[✕] Error: Please run this script with sudo or as root!${NC}"
    exit 1
fi

# --- Check Pangolin installation ---
PANGOLIN_PATH=$(which pangolin)
if [ -z "$PANGOLIN_PATH" ]; then
    echo -e "${YELLOW}[*] Pangolin CLI not found. Installing...${NC}"
    curl -fsSL https://static.pangolin.net/get-cli.sh | bash
    PANGOLIN_PATH=$(which pangolin)
    if [ -z "$PANGOLIN_PATH" ]; then
        echo -e "${RED}[✕] Error installing Pangolin. Aborting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}[✓] Pangolin installed successfully!${NC}"
else
    echo -e "${GREEN}[✓] Pangolin CLI found at: $PANGOLIN_PATH${NC}"
fi

echo ""
echo -e "${WHITE}--- Enter configuration ---${NC}"

# --- Input: ID ---
while [ -z "$P_ID" ]; do
    echo -e "${BLUE}[?] Please enter Pangolin ID:${NC}"
    read -p "➔ " P_ID
    if [ -z "$P_ID" ]; then
        echo -e "${RED}    ID must not be empty!${NC}"
    fi
done

# --- Input: Secret ---
while [ -z "$P_SECRET" ]; do
    echo -e "${BLUE}[?] Please enter Pangolin Secret (input will be hidden):${NC}"
    read -s -p "➔ " P_SECRET
    echo ""
    if [ -z "$P_SECRET" ]; then
        echo -e "${RED}    Secret must not be empty!${NC}"
    fi
done

# --- Input: Endpoint ---
DEFAULT_ENDPOINT="https://aegis.hivegamez.com"
echo -e "${BLUE}[?] Enter endpoint [Default: $DEFAULT_ENDPOINT]:${NC}"
read -p "➔ " P_ENDPOINT
if [ -z "$P_ENDPOINT" ]; then
    P_ENDPOINT=$DEFAULT_ENDPOINT
fi

echo ""
echo -e "${YELLOW}[*] Creating/updating systemd service...${NC}"

# --- Write service file ---
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

# --- Update and start systemd ---
systemctl daemon-reload
systemctl enable --now pangolin

echo -e "${GREEN}[✓] Service configured and started successfully!${NC}"
echo ""
echo -e "${PURPLE}==================================================${NC}"
echo -e "${WHITE}               Current Service Status             ${NC}"
echo -e "${PURPLE}==================================================${NC}"
echo ""

# Show status (trimmed to the most important lines)
systemctl status pangolin --no-pager | grep -E "Active:|Main PID:|Tasks:"

echo ""
echo -e "${CYAN}Tip: You can check the status anytime with 'systemctl status pangolin'.${NC}"
echo -e "${PURPLE}==================================================${NC}"