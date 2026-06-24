#!/usr/bin/env bash

set -u

REFRESH_INTERVAL="${REFRESH_INTERVAL:-2}"
DEFAULT_ENDPOINT="https://aegis.hivegamez.com"
SELECTED_IDX=0
STATUS_MSG=""
MESSAGE_TTL=0

declare -a SVC_NAMES=()
declare -a SVC_ACTIVE=()
declare -a SVC_ENABLED=()
declare -a SVC_ID=()
declare -a SVC_ENDPOINT=()
declare -a SVC_PID=()

init_colors() {
    local n
    n=$(tput colors 2>/dev/null || echo 0)
    if [ -z "$n" ] || [ "$n" -lt 2 ]; then
        RESET="" BOLD="" DIM="" BLUE="" CYAN="" PURPLE="" GREEN="" YELLOW="" RED="" WHITE=""
        return
    fi
    RESET=$(tput sgr0)
    BOLD=$(tput bold)
    DIM=$(tput setaf 244)
    BLUE=$(tput setaf 39)
    CYAN=$(tput setaf 51)
    PURPLE=$(tput setaf 141)
    GREEN=$(tput setaf 84)
    YELLOW=$(tput setaf 221)
    RED=$(tput setaf 196)
    WHITE=$(tput setaf 255)
}

set_status() {
    STATUS_MSG="$1"
    MESSAGE_TTL=3
}

tick_status() {
    [ "$MESSAGE_TTL" -le 0 ] && return
    MESSAGE_TTL=$((MESSAGE_TTL - 1))
    [ "$MESSAGE_TTL" -le 0 ] && STATUS_MSG=""
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: Please run with sudo or as root." >&2
        exit 1
    fi
}

pangolin_bin() {
    command -v pangolin 2>/dev/null
}

ensure_pangolin_cli() {
    local bin
    bin=$(pangolin_bin)
    [ -n "$bin" ] && return 0

    set_status "Installing Pangolin CLI..."
    draw_screen
    if ! curl -fsSL https://static.pangolin.net/get-cli.sh | bash; then
        set_status "Pangolin CLI installation failed."
        return 1
    fi
    set_status "Pangolin CLI installed."
    return 0
}

unit_file_for() {
    local unit="$1"
    echo "/etc/systemd/system/${unit}.service"
}

parse_execstart_field() {
    local line="$1"
    local flag="$2"
    printf '%s\n' "$line" | sed -n "s/.*${flag} \([^ ]*\).*/\1/p" | head -1
}

discover_services() {
    local unit file exec_line active enabled pid id endpoint
    SVC_NAMES=()
    SVC_ACTIVE=()
    SVC_ENABLED=()
    SVC_ID=()
    SVC_ENDPOINT=()
    SVC_PID=()

    for file in /etc/systemd/system/pangolin*.service; do
        [ -f "$file" ] || continue
        unit=$(basename "$file" .service)
        exec_line=$(grep -E '^ExecStart=' "$file" | head -1 | sed 's/^ExecStart=//')
        id=$(parse_execstart_field "$exec_line" --id)
        endpoint=$(parse_execstart_field "$exec_line" --endpoint)
        active=$(systemctl is-active "$unit" 2>/dev/null || echo "unknown")
        enabled=$(systemctl is-enabled "$unit" 2>/dev/null || echo "unknown")
        pid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null || echo "0")
        [ "$pid" = "0" ] && pid="-"

        SVC_NAMES+=("$unit")
        SVC_ACTIVE+=("$active")
        SVC_ENABLED+=("$enabled")
        SVC_ID+=("${id:--}")
        SVC_ENDPOINT+=("${endpoint:--}")
        SVC_PID+=("$pid")
    done
}

clamp_selection() {
    local count="${#SVC_NAMES[@]}"
    [ "$count" -eq 0 ] && SELECTED_IDX=0 && return
    [ "$SELECTED_IDX" -lt 0 ] && SELECTED_IDX=0
    [ "$SELECTED_IDX" -ge "$count" ] && SELECTED_IDX=$((count - 1))
}

status_color() {
    case "$1" in
        active) printf '%s' "$GREEN" ;;
        activating|reloading) printf '%s' "$YELLOW" ;;
        *) printf '%s' "$RED" ;;
    esac
}

truncate_text() {
    local text="$1"
    local width="$2"
    if [ "${#text}" -le "$width" ]; then
        printf "%-${width}s" "$text"
        return
    fi
    printf "%-${width}s" "${text:0:$((width - 1))}…"
}

draw_horizontal_rule() {
    local width="$1"
    local i
    printf '╠'
    for ((i = 0; i < width - 2; i++)); do printf '═'; done
    printf '╣\n'
}

draw_header() {
    local cols="$1"
    local bin pad
    bin=$(pangolin_bin)
    [ -z "$bin" ] && bin="not installed"

    printf '%s%b' "$CYAN" "╔"
    for ((pad = 0; pad < cols - 2; pad++)); do printf '═'; done
    printf '╗%s\n' "$RESET"

    printf '%s%b Pangolin Manager%b' "$CYAN" "║" "$RESET"
    pad=$((cols - 24))
    [ "$pad" -lt 0 ] && pad=0
    printf '%*s%s%b q quit %s\n' "$pad" "" "$CYAN" "║" "$RESET"

    draw_horizontal_rule "$cols"
    printf '%s%b Services: %-3s %b│%b CLI: %s\n' \
        "$CYAN" "║" "${#SVC_NAMES[@]}" "$DIM" "$RESET" "$bin"
    draw_horizontal_rule "$cols"
}

draw_table_header() {
    printf '%s%b  %-22s %-10s %-14s %-10s %-8s %b║%s\n' \
        "$CYAN" "║" "SERVICE" "STATE" "ID" "BOOT" "PID" "$RESET" "$CYAN" "$RESET"
    draw_horizontal_rule "$(tput cols)"
}

draw_service_rows() {
    local count="$1"
    local idx name active enabled pid id state_color

    for ((idx = 0; idx < count; idx++)); do
        name="${SVC_NAMES[$idx]}"
        active="${SVC_ACTIVE[$idx]}"
        enabled="${SVC_ENABLED[$idx]}"
        pid="${SVC_PID[$idx]}"
        id="${SVC_ID[$idx]}"
        state_color=$(status_color "$active")

        if [ "$idx" -eq "$SELECTED_IDX" ]; then
            printf '%s%b %s%-22s %s%-10s %b%-14s %b%-10s %b%-8s %b║%s\n' \
                "$CYAN" "║" "$BOLD$BLUE" "$(truncate_text "$name" 22)" "$state_color" "$(truncate_text "$active" 10)" \
                "$DIM" "$(truncate_text "$id" 14)" "$RESET" "$(truncate_text "$enabled" 10)" "$DIM" "$(truncate_text "$pid" 8)" \
                "$CYAN" "$RESET"
            continue
        fi

        printf '%s%b  %-22s %s%-10s %b%-14s %b%-10s %b%-8s %b║%s\n' \
            "$CYAN" "║" "$(truncate_text "$name" 22)" "$state_color" "$(truncate_text "$active" 10)" \
            "$DIM" "$(truncate_text "$id" 14)" "$RESET" "$(truncate_text "$enabled" 10)" "$DIM" "$(truncate_text "$pid" 8)" \
            "$CYAN" "$RESET"
    done
}

draw_empty_state() {
    printf '%s%b%*s%b║%s\n' "$CYAN" "║" 30 "" "$CYAN" "$RESET"
    printf '%s%b  %-58s %b║%s\n' "$CYAN" "║" "No Pangolin services registered yet." "$CYAN" "$RESET"
    printf '%s%b  %-58s %b║%s\n' "$CYAN" "║" "Press [n] to register a new service." "$CYAN" "$RESET"
    printf '%s%b%*s%b║%s\n' "$CYAN" "║" 30 "" "$CYAN" "$RESET"
}

draw_details_panel() {
    local cols="$1"
    local name active enabled id endpoint

    [ "${#SVC_NAMES[@]}" -eq 0 ] && return
    clamp_selection

    name="${SVC_NAMES[$SELECTED_IDX]}"
    active="${SVC_ACTIVE[$SELECTED_IDX]}"
    enabled="${SVC_ENABLED[$SELECTED_IDX]}"
    id="${SVC_ID[$SELECTED_IDX]}"
    endpoint="${SVC_ENDPOINT[$SELECTED_IDX]}"

    draw_horizontal_rule "$cols"
    printf '%s%b Selected: %s%-20s %bEndpoint: %s%s\n' \
        "$CYAN" "║" "$BOLD" "$name" "$RESET" "$DIM" "$(truncate_text "$endpoint" $((cols - 40)))" "$CYAN" "$RESET"
}

draw_footer() {
    local cols="$1"
    draw_horizontal_rule "$cols"
    printf '%s%b ↑↓/jk move  s start  x stop  r restart  l logs  e enable  d disable %b║%s\n' \
        "$CYAN" "║" "$CYAN" "$RESET"
    printf '%s%b n new  D delete  i install CLI  R refresh  Enter details       %b║%s\n' \
        "$CYAN" "║" "$CYAN" "$RESET"
    if [ -n "$STATUS_MSG" ]; then
        printf '%s%b %s%-58s %b║%s\n' "$CYAN" "║" "$YELLOW" "$(truncate_text "$STATUS_MSG" 58)" "$CYAN" "$RESET"
    fi
    printf '%s%b%*s%b╝%s\n' "$CYAN" "╚" $((cols - 2)) "" "$CYAN" "$RESET"
}

draw_screen() {
    local cols rows count idx blank_lines
    cols=$(tput cols 2>/dev/null || echo 80)
    rows=$(tput lines 2>/dev/null || echo 24)
    count="${#SVC_NAMES[@]}"

    tput cup 0 0
    tput ed 2>/dev/null || clear

    draw_header "$cols"
    draw_table_header

    if [ "$count" -eq 0 ]; then
        draw_empty_state
    else
        draw_service_rows "$count"
    fi

    blank_lines=$((rows - count - 12))
    [ "$blank_lines" -lt 0 ] && blank_lines=0
    for ((idx = 0; idx < blank_lines; idx++)); do
        printf '%s%b%*s%b║%s\n' "$CYAN" "║" $((cols - 2)) "" "$CYAN" "$RESET"
    done

    draw_details_panel "$cols"
    draw_footer "$cols"
    tick_status
}

read_key() {
    local key key2
    IFS= read -rsn1 -t "$REFRESH_INTERVAL" key || return 1
    [ -z "$key" ] && return 1

    if [ "$key" = $'\x1b' ]; then
        IFS= read -rsn2 -t 0.05 key2 || return 0
        case "$key2" in
            '[A') printf 'up' ;;
            '[B') printf 'down' ;;
            *) printf 'esc' ;;
        esac
        return 0
    fi

    printf '%s' "$key"
}

prompt_line() {
    local prompt="$1"
    local __var="$2"
    local value=""
    tput rmcup 2>/dev/null || true
    printf '%s' "$prompt"
    IFS= read -r value || value=""
    tput smcup 2>/dev/null || true
    printf -v "$__var" '%s' "$value"
}

read_hidden_line() {
    local prompt="$1"
    local __var="$2"
    local value=""
    tput rmcup 2>/dev/null || true
    printf '%s' "$prompt"
    if [ -t 0 ]; then
        stty -echo 2>/dev/null || true
        IFS= read -r value || value=""
        stty echo 2>/dev/null || true
        printf '\n'
    else
        IFS= read -r value || value=""
    fi
    tput smcup 2>/dev/null || true
    printf -v "$__var" '%s' "$value"
}

selected_unit() {
    [ "${#SVC_NAMES[@]}" -eq 0 ] && return 1
    clamp_selection
    printf '%s' "${SVC_NAMES[$SELECTED_IDX]}"
}

run_service_action() {
    local action="$1"
    local unit
    unit=$(selected_unit) || return 1
    if ! systemctl "$action" "$unit" 2>/dev/null; then
        set_status "Failed: systemctl $action $unit"
        return 1
    fi
    set_status "OK: systemctl $action $unit"
}

show_logs() {
    local unit
    unit=$(selected_unit) || return 1
    tput rmcup 2>/dev/null || true
    journalctl -u "$unit" -n 100 --no-pager | ${PAGER:-less -R}
    tput smcup 2>/dev/null || true
}

show_details() {
    local unit
    unit=$(selected_unit) || return 1
    tput rmcup 2>/dev/null || true
    systemctl status "$unit" --no-pager
    printf '\nUnit file: %s\n' "$(unit_file_for "$unit")"
    printf '\nPress Enter to return...'
    IFS= read -r _
    tput smcup 2>/dev/null || true
}

delete_selected_service() {
    local unit file
    unit=$(selected_unit) || return 1
    file=$(unit_file_for "$unit")

    tput rmcup 2>/dev/null || true
    printf 'Delete service %s? [y/N] ' "$unit"
    IFS= read -r confirm
    tput smcup 2>/dev/null || true

    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && return 0

    systemctl disable --now "$unit" 2>/dev/null || true
    rm -f "$file"
    systemctl daemon-reload
    SELECTED_IDX=0
    set_status "Deleted $unit"
}

slugify_name() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g;s/--*/-/g;s/^-//;s/-$//'
}

register_new_service() {
    local pangolin_path instance raw_name unit p_id p_secret p_endpoint file tries
    pangolin_path=$(pangolin_bin)
    if [ -z "$pangolin_path" ]; then
        ensure_pangolin_cli || return 1
        pangolin_path=$(pangolin_bin)
    fi
    [ -z "$pangolin_path" ] && return 1

    tput rmcup 2>/dev/null || true
    printf '\n%s\n' "--- Register new Pangolin service ---"

    prompt_line "Instance name [pangolin]: " raw_name
    [ -z "$raw_name" ] && raw_name="pangolin"
    instance=$(slugify_name "$raw_name")
    [ -z "$instance" ] && instance="pangolin"
    unit="$instance"
    case "$unit" in
        pangolin) ;;
        pangolin-*) ;;
        *) unit="pangolin-${unit}" ;;
    esac

    file=$(unit_file_for "$unit")
    if [ -f "$file" ]; then
        printf 'Service %s already exists.\n' "$unit"
        printf 'Press Enter to return...'
        IFS= read -r _
        tput smcup 2>/dev/null || true
        return 1
    fi

    tries=0
    while [ -z "${p_id:-}" ]; do
        tries=$((tries + 1))
        [ "$tries" -gt 5 ] && return 1
        prompt_line "Pangolin ID: " p_id
        [ -n "$p_id" ] && break
        printf 'ID must not be empty.\n'
    done

    tries=0
    while [ -z "${p_secret:-}" ]; do
        tries=$((tries + 1))
        [ "$tries" -gt 5 ] && return 1
        read_hidden_line "Pangolin Secret (hidden): " p_secret
        [ -n "$p_secret" ] && break
        printf 'Secret must not be empty.\n'
    done

    prompt_line "Endpoint [${DEFAULT_ENDPOINT}]: " p_endpoint
    [ -z "$p_endpoint" ] && p_endpoint="$DEFAULT_ENDPOINT"

    cat <<EOF > "$file"
[Unit]
Description=Pangolin Network Service (${unit})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${pangolin_path} up --id ${p_id} --secret ${p_secret} --endpoint ${p_endpoint} --attach
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now "$unit"
    tput smcup 2>/dev/null || true
    set_status "Registered and started $unit"
}

move_selection() {
    local direction="$1"
    [ "${#SVC_NAMES[@]}" -eq 0 ] && return
    if [ "$direction" = "up" ]; then
        SELECTED_IDX=$((SELECTED_IDX - 1))
    else
        SELECTED_IDX=$((SELECTED_IDX + 1))
    fi
    clamp_selection
}

handle_key() {
    local key="$1"
    case "$key" in
        q|Q) exit 0 ;;
        up|k|K) move_selection up ;;
        down|j|J) move_selection down ;;
        s|S) run_service_action start ;;
        x|X) run_service_action stop ;;
        r) run_service_action restart ;;
        R) set_status "Refreshed" ;;
        l|L) show_logs ;;
        e|E) run_service_action enable ;;
        d) run_service_action disable ;;
        D) delete_selected_service ;;
        n|N) register_new_service ;;
        i|I) ensure_pangolin_cli ;;
        ''|$'\n'|$'\r') show_details ;;
    esac
}

cleanup() {
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    stty sane 2>/dev/null || true
}

run_fallback_menu() {
    discover_services
    echo "Pangolin Manager (non-interactive terminal)"
    if [ "${#SVC_NAMES[@]}" -eq 0 ]; then
        echo "No services found. Run on a TTY for full TUI."
        exit 0
    fi
    local idx
    for ((idx = 0; idx < ${#SVC_NAMES[@]}; idx++)); do
        printf '%s  active=%s  enabled=%s  id=%s\n' \
            "${SVC_NAMES[$idx]}" "${SVC_ACTIVE[$idx]}" "${SVC_ENABLED[$idx]}" "${SVC_ID[$idx]}"
    done
}

main() {
    local key
    require_root
    init_colors

    if [ ! -t 0 ] || [ ! -t 1 ]; then
        run_fallback_menu
        exit 0
    fi

    trap cleanup EXIT INT TERM
    tput smcup 2>/dev/null || true
    tput civis 2>/dev/null || true

    while true; do
        discover_services
        clamp_selection
        draw_screen
        key=$(read_key) || continue
        handle_key "$key"
    done
}

main "$@"
