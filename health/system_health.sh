#!/bin/bash

# Re-exec under bash when launched through a shell that ignores the shebang.
if [ -z "${BASH_VERSION-}" ]; then
    exec /usr/bin/env bash "$0" "$@"
fi

# --- Konfiguration ---
BAR_WIDTH="${BAR_WIDTH:-30}"
DELIMITER="╺━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╸"
WATCH=false
WATCH_INTERVAL="${WATCH_INTERVAL:-2}"

print_help() {
    cat <<EOF
Usage: $0 [options]

Options:
  -w, --watch         Update the dashboard live every ${WATCH_INTERVAL} seconds
  -h, --help          Show this help

Environment:
  WATCH_INTERVAL      Set the refresh interval in seconds (default: ${WATCH_INTERVAL})
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--watch)
            WATCH=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        --watch-interval=*)
            WATCH_INTERVAL="${1#*=}"
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help
            exit 1
            ;;
    esac
done

# --- 256-Farben initialisieren (Modern & kontrastreich) ---
init_colors() {
    local n
    n=$(tput colors 2>/dev/null || echo 0)
    if [[ -z "$n" || "$n" -lt 2 ]]; then
        RESET="" BOLD="" BLUE="" CYAN="" PURPLE="" GREEN="" YELLOW="" ORANGE="" RED="" DIM=""
        return
    fi
    RESET=$(tput sgr0)
    BOLD=$(tput bold)
    DIM=$(tput setaf 244)
    
    # Premium Palette (256-Farben)
    BLUE=$(tput setaf 39)       # Neon Blau
    CYAN=$(tput setaf 51)       # Cyber Cyan
    PURPLE=$(tput setaf 141)    # Pastel Violett
    GREEN=$(tput setaf 84)      # Vivid Grün (Safe)
    YELLOW=$(tput setaf 221)    # Sanftes Gelb (Low Warning)
    ORANGE=$(tput setaf 208)    # Intensives Orange (High Warning)
    RED=$(tput setaf 196)       # Neon Rot (Critical)
}
init_colors

# --- Hilfsfunktion: Farbe basierend auf Prozentwert ermitteln ---
get_color_by_pct() {
    local val
    val=$(printf "%.0f" "$1" 2>/dev/null || echo 0)
    if [ "$val" -ge 90 ]; then echo -e "${BOLD}${RED}";
    elif [ "$val" -ge 75 ]; then echo -e "${RED}";
    elif [ "$val" -ge 50 ]; then echo -e "${ORANGE}";
    elif [ "$val" -ge 15 ]; then echo -e "${YELLOW}";
    else echo -e "${GREEN}"; fi
}

# --- Hilfsfunktion: Fortschrittsbalken zeichnen ---
draw_bar() {
    local percent="$1"
    local width="${2:-$BAR_WIDTH}"
    
    # Bereinige Prozentwert für mathematische Operationen
    local num
    num=$(echo "$percent" | sed 's/%//' | cut -d. -f1)
    [[ -z "$num" || ! "$num" =~ ^[0-9]+$ ]] && num=0
    [[ "$num" -gt 100 ]] && num=100

    local filled=$(( (num * width) / 100 ))
    local empty=$(( width - filled ))
    local color
    color=$(get_color_by_pct "$num")

    printf "${DIM}▒${RESET}"
    printf "${color}"
    for ((i=0; i<filled; i++)); do printf "█"; done
    printf "${RESET}${DIM}"
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "${RESET}${DIM}▒${RESET} "
    
    printf "%s" "${color}$(printf "%5s" "${num}%")${RESET}"
}

# --- Hilfsfunktion: Bytes pro Sekunde lesbar formatieren ---
format_rate() {
    awk -v bytes="${1:-0}" 'BEGIN {
        split("B/s KiB/s MiB/s GiB/s TiB/s", units, " ")
        unit = 1
        while (bytes >= 1024 && unit < 5) {
            bytes /= 1024
            unit++
        }
        printf "%.1f %s", bytes, units[unit]
    }'
}

# --- Hilfsfunktion: Netzwerktraffic messen ---
get_network_rates() {
    local rx1 tx1 rx2 tx2
    read -r rx1 tx1 < <(
        awk -F'[: ]+' '
            NR > 2 && $1 != "lo" {
                rx += $2
                tx += $10
            }
            END { printf "%s %s", rx + 0, tx + 0 }
        ' /proc/net/dev
    )
    sleep 1
    read -r rx2 tx2 < <(
        awk -F'[: ]+' '
            NR > 2 && $1 != "lo" {
                rx += $2
                tx += $10
            }
            END { printf "%s %s", rx + 0, tx + 0 }
        ' /proc/net/dev
    )

    local rx_rate=$(( rx2 - rx1 ))
    local tx_rate=$(( tx2 - tx1 ))
    (( rx_rate < 0 )) && rx_rate=0
    (( tx_rate < 0 )) && tx_rate=0

    printf "%s|%s" "$rx_rate" "$tx_rate"
}

# --- Hilfsfunktion: Ports und Verbindungen zählen ---
get_port_overview() {
    local ports=(80 443 25)
    local port listen established

    for port in "${ports[@]}"; do
        if command -v ss >/dev/null 2>&1; then
            listen=$(ss -ltnH "sport = :$port" 2>/dev/null | wc -l)
            established=$(ss -tanH state established "sport = :$port" 2>/dev/null | wc -l)
        elif command -v netstat >/dev/null 2>&1; then
            listen=$(netstat -ltn 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" {c++} END {print c+0}')
            established=$(netstat -ant 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" && $6 == "ESTABLISHED" {c++} END {print c+0}')
        else
            listen=0
            established=0
        fi
        printf "%s|%s|%s\n" "$port" "$listen" "$established"
    done
}

# --- Hilfsfunktion: aktive SSH-Sitzungen ---
get_ssh_sessions() {
    who 2>/dev/null | awk '
        $0 ~ /\(.*\)/ {
            host = $NF
            gsub(/[()]/, "", host)
            print $1 "|" $2 "|" $3 " " $4 "|" host
        }
    '
}

# --- Hilfsfunktion: ausstehende Updates zählen ---
get_update_counts() {
    local total security
    total=0
    security=0

    if command -v apt >/dev/null 2>&1; then
        total=$(apt list --upgradable 2>/dev/null | tail -n +2 | sed '/^$/d' | wc -l)
        security=$(apt-get -s upgrade 2>/dev/null | awk '/^Inst / && tolower($0) ~ /security/ {c++} END {print c+0}')
    fi

    printf "%s|%s" "$total" "$security"
}

# --- Hilfsfunktion: fehlgeschlagene Logins zählen ---
get_failed_logins() {
    local count=0
    if [ -r /var/log/auth.log ] || compgen -G "/var/log/auth.log*" >/dev/null; then
        count=$(grep -hEi 'Failed password|authentication failure|Invalid user|Failed publickey' /var/log/auth.log* 2>/dev/null | wc -l)
    elif command -v journalctl >/dev/null 2>&1; then
        count=$(journalctl -p warning --since "24 hours ago" 2>/dev/null | grep -Ei 'Failed password|authentication failure|Invalid user|Failed publickey' | wc -l)
    fi
    echo "$count"
}

# --- Hilfsfunktion: fehlgeschlagene systemd-Dienste ---
get_failed_services() {
    systemctl list-units --failed --type=service --no-legend 2>/dev/null | awk '{print $1 "|" $2 "|" $4}'
}

# --- Hilfsfunktion: CPU-Temperatur ermitteln ---
get_cpu_temp() {
    if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt --quiet >/dev/null 2>&1; then
        return 1
    fi

    local temp
    temp=""

    if command -v sensors >/dev/null 2>&1; then
        temp=$(sensors 2>/dev/null | grep -oE '\+[0-9]+(\.[0-9]+)?°C' | head -1 | tr -d '+°C')
    fi

    if [ -z "$temp" ] && ls /sys/class/thermal/thermal_zone*/temp >/dev/null 2>&1; then
        temp=$(for f in /sys/class/thermal/thermal_zone*/temp; do
            [ -r "$f" ] || continue
            awk '{printf "%.1f\n", $1 / 1000}' "$f"
        done | sort -nr | head -1)
    fi

    [ -n "$temp" ] && echo "$temp"
}

# --- Hilfsfunktion: Disk-I/O messen ---
get_disk_io_rates() {
    local read1 write1 read2 write2
    read -r read1 write1 < <(
        awk '
            $3 ~ /^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$/ {
                r += $6
                w += $10
            }
            END { printf "%s %s", r + 0, w + 0 }
        ' /proc/diskstats
    )
    sleep 1
    read -r read2 write2 < <(
        awk '
            $3 ~ /^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme[0-9]+n[0-9]+|mmcblk[0-9]+)$/ {
                r += $6
                w += $10
            }
            END { printf "%s %s", r + 0, w + 0 }
        ' /proc/diskstats
    )

    local read_rate=$(( (read2 - read1) * 512 ))
    local write_rate=$(( (write2 - write1) * 512 ))
    (( read_rate < 0 )) && read_rate=0
    (( write_rate < 0 )) && write_rate=0

    printf "%s|%s" "$read_rate" "$write_rate"
}

# --- Docker-Schnittstellen aus df filtern ---
get_non_docker_mounts() {
    df -P -h 2>/dev/null | awk '
    NR==1 { next }
    $1 ~ /^\/dev\/loop/ { next }
    $6 ~ /^\/var\/lib\/docker/ { next }
    $1 ~ /^overlay$/ { next }
    $1 ~ /^tmpfs$/ { next }
    $1 ~ /^devtmpfs$/ { next }
    $1 ~ /^squashfs$/ { next }
    $6 == "/dev" { next }
    $6 ~ /^\/snap\// { next }
    {
        pct = $5; gsub(/%/, "", pct)
        print $6 "|" $2 "|" $3 "|" $4 "|" pct
    }' | sort
}

# --- Systemdaten sammeln ---
HOSTNAME=$(hostname -f 2>/dev/null || hostname -s)
KERNEL=$(uname -r)
ARCH=$(uname -m)
CPU_MODEL=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo 2>/dev/null | sed 's/^[ \t]*//')
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(uname -p)

# Netzwerk (Timeout von 2 Sekunden für externe IP)
INTERNAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "N/A")
EXTERNAL_IP=$(curl -s --max-time 2 https://api.ipify.org 2>/dev/null || echo "N/A")

# CPU Auslastung berechnen
CPU_USAGE=$(top -bn1 2>/dev/null | awk '/%Cpu/ {print 100 - $8}' | head -1)
[[ -z "$CPU_USAGE" ]] && CPU_USAGE=$(vmstat 1 2 | tail -1 | awk '{print 100 - $15}')

# Load, RAM & Swap
LOAD=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
LOAD_1M=$(echo "$LOAD" | cut -d ',' -f1 | tr -d ' ')

TOTAL_RAM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
FREE_RAM=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
USED_RAM=$(( TOTAL_RAM - FREE_RAM ))
RAM_PCT=$(( TOTAL_RAM > 0 ? (USED_RAM * 100) / TOTAL_RAM : 0 ))

TOTAL_SWAP=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
FREE_SWAP=$(awk '/SwapFree/ {print int($2/1024)}' /proc/meminfo)
USED_SWAP=$(( TOTAL_SWAP - FREE_SWAP ))
SWAP_PCT=$(( TOTAL_SWAP > 0 ? (USED_SWAP * 100) / TOTAL_SWAP : 0 ))

UPTIME=$(uptime -p 2>/dev/null | sed 's/^up //' || uptime)
DATE=$(date "+%Y-%m-%d %H:%M:%S")

render_dashboard() {
    # --- UI RENDERING ---
    clear
    echo -e "${PURPLE}${BOLD}╭────────────────────────────────────────────────────────────────╮${RESET}"
    echo -e "${PURPLE}${BOLD}│${RESET}  ${CYAN}${BOLD}⚡ SYSTEM PERFORMANCE DASHBOARD ⚡${RESET}                           ${PURPLE}${BOLD}│${RESET}"
    echo -e "${PURPLE}${BOLD}╰────────────────────────────────────────────────────────────────╯${RESET}"
    echo -e "${DIM}${DELIMITER}${RESET}"

    # Sektion: Host Info
    printf "  ${BLUE}%-18s${RESET} : ${BOLD}${GREEN}%s${RESET}\n" "Hostname" "$HOSTNAME"
    printf "  ${BLUE}%-18s${RESET} : %s (%s)\n" "OS Kernel" "$KERNEL" "$ARCH"
    printf "  ${BLUE}%-18s${RESET} : %s\n" "CPU Typ" "$CPU_MODEL"
    printf "  ${BLUE}%-18s${RESET} : %s\n" "Interne IP" "$INTERNAL_IP"
    printf "  ${BLUE}%-18s${RESET} : %s\n" "Externe IP" "$EXTERNAL_IP"
    printf "  ${BLUE}%-18s${RESET} : %s\n" "System-Uptime" "$UPTIME"
    printf "  ${BLUE}%-18s${RESET} : %s\n" "Zeitstempel" "$DATE"
    echo -e "${DIM}${DELIMITER}${RESET}"

    # Sektion: Live-Ressourcen
    printf "  ${CYAN}%-18s${RESET} : " "CPU Last"
    draw_bar "$CPU_USAGE"
    printf "\n"

    printf "  ${CYAN}%-18s${RESET} : " "Arbeitsspeicher"
    draw_bar "$RAM_PCT"
    printf "  ${DIM}(%s / %s MiB)${RESET}\n" "$USED_RAM" "$TOTAL_RAM"

    if [ "$TOTAL_SWAP" -gt 0 ]; then
        printf "  ${CYAN}%-18s${RESET} : " "Swap Speicher"
        draw_bar "$SWAP_PCT"
        printf "  ${DIM}(%s / %s MiB)${RESET}\n" "$USED_SWAP" "$TOTAL_SWAP"
    fi

    # Sektion: Netzwerk & Traffic
    echo -e "\n  ${PURPLE}${BOLD}➔ NETZWERK & TRAFFIC${RESET}"
    echo -e "${DIM}${DELIMITER}${RESET}"
    IFS='|' read -r RX_RATE TX_RATE < <(get_network_rates)
    printf "  ${CYAN}%-18s${RESET} : ${GREEN}%s${RESET} / ${YELLOW}%s${RESET}\n" \
        "Live-Bandbreite" "$(format_rate "$RX_RATE") RX" "$(format_rate "$TX_RATE") TX"

    echo -e "  ${DIM}Offene Ports / Verbindungen:${RESET}"
    while IFS='|' read -r port listen established; do
        [ -z "$port" ] && continue
        printf "  ${BLUE}Port %-13s${RESET} : Listen %s | Aktiv %s\n" "$port" "$listen" "$established"
    done < <(get_port_overview)

    # Sektion: Sicherheit & Benutzer
    echo -e "\n  ${PURPLE}${BOLD}➔ SICHERHEIT & BENUTZER${RESET}"
    echo -e "${DIM}${DELIMITER}${RESET}"

    echo -e "  ${DIM}Aktive SSH-Sitzungen:${RESET}"
    SSH_SESSIONS=$(get_ssh_sessions)
    if [ -n "$SSH_SESSIONS" ]; then
        printf "%s\n" "$SSH_SESSIONS" | while IFS='|' read -r user tty login host; do
            [ -z "$user" ] && continue
            printf "  ${GREEN}%-12s${RESET} %-8s %-16s %s\n" "$user" "$tty" "$login" "$host"
        done
    else
        echo -e "  ${DIM}Keine aktiven SSH-Sitzungen gefunden.${RESET}"
    fi

    IFS='|' read -r UPDATE_TOTAL UPDATE_SECURITY < <(get_update_counts)
    printf "  ${CYAN}%-18s${RESET} : ${BOLD}%s verfügbar${RESET} | ${YELLOW}%s Sicherheitsupdates${RESET}\n" \
        "Updates" "${UPDATE_TOTAL:-0}" "${UPDATE_SECURITY:-0}"

    FAILED_LOGINS=$(get_failed_logins)
    printf "  ${CYAN}%-18s${RESET} : ${RED}%s${RESET}\n" "Fehlgeschlagene Logins" "${FAILED_LOGINS:-0}"

    # Sektion: System-Gesundheit (Deep Dive)
    echo -e "\n  ${PURPLE}${BOLD}➔ SYSTEM-GESUNDHEIT (DEEP DIVE)${RESET}"
    echo -e "${DIM}${DELIMITER}${RESET}"

    FAILED_SERVICE_LINES=$(get_failed_services)
    FAILED_SERVICE_COUNT=$(printf "%s\n" "$FAILED_SERVICE_LINES" | sed '/^$/d' | wc -l)
    printf "  ${CYAN}%-18s${RESET} : ${RED}%s${RESET}\n" "Failed Services" "${FAILED_SERVICE_COUNT}"
    if [ "$FAILED_SERVICE_COUNT" -gt 0 ]; then
        printf "%s\n" "$FAILED_SERVICE_LINES" | head -3 | while IFS='|' read -r service load active; do
            [ -z "$service" ] && continue
            printf "  ${DIM}  - %s (%s | %s)${RESET}\n" "$service" "$load" "$active"
        done
    fi

    CPU_TEMP=$(get_cpu_temp)
    if [ -n "$CPU_TEMP" ]; then
        printf "  ${CYAN}%-18s${RESET} : ${GREEN}%s°C${RESET}\n" "Temperatur" "$CPU_TEMP"
    else
        printf "  ${CYAN}%-18s${RESET} : ${DIM}N/A${RESET}\n" "Temperatur"
    fi

    IFS='|' read -r DISK_READ_RATE DISK_WRITE_RATE < <(get_disk_io_rates)
    printf "  ${CYAN}%-18s${RESET} : ${GREEN}%s${RESET} / ${YELLOW}%s${RESET}\n" \
        "Disk I/O" "$(format_rate "$DISK_READ_RATE") Read" "$(format_rate "$DISK_WRITE_RATE") Write"

    # Load Average Skalierung (Annahme: 4 Cores Basis für 100%)
    LOAD_PCT=$(echo "scale=0; ($LOAD_1M * 100) / 4" | bc 2>/dev/null || echo 0)
    printf "  ${CYAN}%-18s${RESET} : " "Load Average"
    draw_bar "$LOAD_PCT"
    printf "  ${DIM}(1m:${RESET}$(get_color_by_pct $(( ${LOAD_1M%.*} * 20 )))${LOAD_1M}${RESET}${DIM})${RESET}\n"

    # Sektion: Top 3 System Prozesse (Außerhalb Docker)
    echo -e "\n  ${PURPLE}${BOLD}➔ TOP 3 SYSTEM PROZESSE (CPU & RAM)${RESET}"
    echo -e "${DIM}${DELIMITER}${RESET}"
    printf "  ${DIM}%-25s %-12s %-15s${RESET}\n" "  PROZESS" "CPU %" "RAM %"
    echo -e "  ${DIM}──────────────────────────────────────────────────────────────${RESET}"
    ps -eo comm,pcpu,pmem --sort=-pcpu | head -n 4 | tail -n 3 | while read -r proc cpu mem; do
        printf "  ⚙️ %-23s %-12s %-15s\n" "$(echo "$proc" | cut -c1-22)" "${cpu}%" "${mem}%"
    done

    # Sektion: Speicherlaufwerke (Frei von Docker-Mounts)
    echo -e "\n  ${PURPLE}${BOLD}➔ SPEICHERMEDIEN (Physisch / Mounts)${RESET}"
    echo -e "${DIM}${DELIMITER}${RESET}"
    while IFS='|' read -r mount size used avail use_pct; do
        [ -z "$mount" ] && continue
        if [ ${#mount} -gt 18 ]; then
            printf "  ${BLUE}%s${RESET}\n                     : " "$mount"
        else
            printf "  ${BLUE}%-18s${RESET} : " "$mount"
        fi
        draw_bar "$use_pct"
        printf "  ${DIM}[%s / %s frei]${RESET}\n" "$avail" "$size"
    done <<< "$(get_non_docker_mounts)"

    # Sektion: DOCKER HEALTH METRICS
    echo -e "\n  ${PURPLE}${BOLD}➔ DOCKER ENGINE CONTAINER HEALTH${RESET}"
    echo -e "${DIM}${DELIMITER}${RESET}"

    if command -v docker >/dev/null 2>&1 && systemctl is-active docker >/dev/null 2>&1; then
        DOCKER_TOTAL=$(docker ps -a -q | wc -l)
        DOCKER_RUNNING=$(docker ps -q | wc -l)
        DOCKER_STOPPED=$((DOCKER_TOTAL - DOCKER_RUNNING))

        printf "  %-18s : ${GREEN}${BOLD}%s Running${RESET} | ${YELLOW}%s Stopped${RESET} | Total: %s\n" "Container Status" "$DOCKER_RUNNING" "$DOCKER_STOPPED" "$DOCKER_TOTAL"
        
        if [ "$DOCKER_RUNNING" -gt 0 ]; then
            echo -e "  ${DIM}──────────────────────────────────────────────────────────────${RESET}"
            printf "  %-25s %-12s %-15s\n" "  CONTAINER" "CPU %" "MEM USAGE"
            echo -e "  ${DIM}──────────────────────────────────────────────────────────────${RESET}"
            
            docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}" | sort -t'|' -k2 -nr | head -5 | while IFS='|' read -r name cpu mem; do
                cpu_num=$(echo "$cpu" | sed 's/%//' | cut -d. -f1)
                c_color=$(get_color_by_pct "$cpu_num")
                printf "  🐳 %-22s ${c_color}%-11s${RESET} %-15s\n" "$(echo "$name" | cut -c1-22)" "$cpu" "$mem"
            done
        else
            echo -e "  ${DIM}[i] Keine Container aktiv am Laufen.${RESET}"
        fi
    else
        echo -e "  ${RED}✖ Docker-Dienst ist offline oder nicht installiert.${RESET}"
    fi

    # Sektion: Letzte Events (Bugfix angewendet)
    echo -e "\n  ${PURPLE}${BOLD}➔ LETZTE SYSTEM EVENTS (Reboots/Shutdowns)${RESET}"
    echo -e "${DIM}${DELIMITER}${RESET}"
    (
        last -x 2>/dev/null | grep -E "reboot|shutdown" | head -4 | while read -r line; do
            if echo "$line" | grep -q "reboot"; then
                echo -e "  ${GREEN}🔄 Reboot:${RESET} ${DIM}${line:22}${RESET}"
            else
                echo -e "  ${RED}🛑 Shutdown:${RESET} ${DIM}${line:24}${RESET}"
            fi
        done
    ) || echo "  Keine Log-Einträge gefunden."
    echo -e "${DIM}${DELIMITER}${RESET}\n"
}

if [ "$WATCH" = true ]; then
    trap 'exit 0' INT TERM
    while true; do
        render_dashboard
        sleep "$WATCH_INTERVAL"
    done
else
    render_dashboard
fi