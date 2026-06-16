#!/bin/bash

set -euo pipefail

# ─── Color Definitions ────────────────────────────────────────────────────────
if [[ -t 1 ]] && command -v tput &>/dev/null; then
    readonly BOLD=$(tput bold)
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly BLUE=$(tput setaf 4)
    readonly MAGENTA=$(tput setaf 5)
    readonly CYAN=$(tput setaf 6)
    readonly DIM=$(tput dim)
    readonly RESET=$(tput sgr0)
else
    readonly BOLD="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" DIM="" RESET=""
fi

# ─── Config ───────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly SCRIPT_NAME=$(basename "$0")
readonly CONFIG_FILE="${CONFIG_DIR:-$SCRIPT_DIR}/hosts.json"
readonly PING_COUNT=5
readonly BAR_WIDTH=30

# ─── Help ─────────────────────────────────────────────────────────────────────
show_help() {
    cat <<EOF
${BOLD}${CYAN}Hetzner Speedtest${RESET} - Measure download speed, latency & jitter
       against Hetzner data centers worldwide.

${BOLD}Usage:${RESET}
  $SCRIPT_NAME [options]

${BOLD}Options:${RESET}
  -s, --size <small|medium|large>  File size to test (default: prompt)
  -h, --help                       Show this help message

${BOLD}Examples:${RESET}
  $SCRIPT_NAME
  $SCRIPT_NAME -s small
  $SCRIPT_NAME --size medium
EOF
    exit 0
}

# ─── Dependency Check ─────────────────────────────────────────────────────────
check_deps() {
    local missing=()
    for cmd in jq curl bc ping; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "${RED}Error: Missing required dependencies: ${missing[*]}${RESET}" >&2
        echo "Install them with your package manager (e.g. apt install ${missing[*]})" >&2
        exit 1
    fi
}

# ─── File Size Selection ──────────────────────────────────────────────────────
choose_size() {
    local choice=$1
    case $choice in
        small|1) size="sm"; size_display="100MB" ;;
        medium|2) size="md"; size_display="1GB" ;;
        large|3) size="lg"; size_display="10GB" ;;
        *)
            echo "${RED}Invalid size: $choice${RESET}" >&2
            echo "Valid options: small (1), medium (2), large (3)" >&2
            exit 1
            ;;
    esac
}

interactive_size_prompt() {
    echo "${BOLD}Choose file size for the test:${RESET}"
    echo "  ${GREEN}1)${RESET} Small  (100MB)"
    echo "  ${YELLOW}2)${RESET} Medium  (1GB)"
    echo "  ${RED}3)${RESET} Large   (10GB)"
    read -p "$(echo -n "Enter your choice ${DIM}(1, 2, or 3)${RESET}: ")" choice
    choose_size "${choice:-2}"
}

# ─── Draw Horizontal Bar ──────────────────────────────────────────────────────
# Usage: draw_bar <value> <max> [label]
draw_bar() {
    local value=$1
    local max=$2
    local label=${3:-}

    local filled=$(echo "scale=0; ($value / $max) * $BAR_WIDTH" | bc 2>/dev/null || echo "0")
    filled=$((filled > BAR_WIDTH ? BAR_WIDTH : filled))
    filled=$((filled < 0 ? 0 : filled))
    local empty=$((BAR_WIDTH - filled))

    local bar=""
    if [[ $filled -gt 0 ]]; then
        printf -v bar '%*s' "$filled" ''
        bar="${bar// /█}"
    fi
    if [[ $empty -gt 0 ]]; then
        printf -v bar '%s%*s' "$bar" "$empty" ''
        bar="${bar// /░}"
    fi

    if [[ -n "$label" ]]; then
        echo "  $bar $label"
    else
        echo "  $bar"
    fi
}

# ─── Color for Speed ──────────────────────────────────────────────────────────
speed_color() {
    local val=$1
    if (($(echo "$val > 80" | bc -l))); then echo "$GREEN"
    elif (($(echo "$val > 30" | bc -l))); then echo "$YELLOW"
    else echo "$RED"
    fi
}

# ─── Color for Latency ────────────────────────────────────────────────────────
latency_color() {
    local val=$1
    if (($(echo "$val < 20" | bc -l))); then echo "$GREEN"
    elif (($(echo "$val < 80" | bc -l))); then echo "$YELLOW"
    else echo "$RED"
    fi
}

# ─── Measure Latency & Jitter (ICMP, fallback TCP) ────────────────────────────
measure_latency_jitter() {
    local host=$1
    local tcp_url=$2
    local result_lat result_jitter result_type

    ping_output=$(ping -c "$PING_COUNT" -W 3 "$host" 2>/dev/null | awk -F'time=' '/time=/{print $2}' | cut -d' ' -f1)

    if [[ -n "$ping_output" ]]; then
        result_lat=$(echo "$ping_output" | awk '{sum+=$1; c+=1} END {printf "%.2f", sum/c}')
        result_jitter=$(echo "$ping_output" | awk -v m="$result_lat" '
            {s+=($1-m)^2} END {printf "%.2f", sqrt(s/(NR-1))}
        ')
        result_type="icmp"
    elif [[ -n "$tcp_url" ]]; then
        tcp_time=$(curl -s -o /dev/null -w "%{time_connect}" "$tcp_url" 2>/dev/null || echo "0")
        if (($(echo "$tcp_time > 0" | bc -l))); then
            result_lat=$(echo "scale=2; $tcp_time * 1000" | bc)
            result_jitter="0.00"
            result_type="tcp"
        fi
    fi

    if [[ -z "${result_type:-}" ]]; then
        echo "unreachable||unreachable"
        return
    fi

    echo "${result_lat}|${result_jitter}|${result_type}"
}

# ─── Measure Download Speed ────────────────────────────────────────────────────
measure_speed() {
    local url=$1
    local timeout=$2

    speed=$(curl -s -w "%{speed_download}" -o /dev/null --max-time "$timeout" "$url" 2>/dev/null || echo "0")

    if (($(echo "$speed == 0" | bc -l))); then
        echo "failed"
        return
    fi

    speed_mb=$(echo "scale=2; $speed / 1048576" | bc)
    echo "$speed_mb"
}

# ─── Determine curl timeout by file size ──────────────────────────────────────
get_timeout() {
    case $1 in
        sm) echo 30 ;;
        md) echo 120 ;;
        lg) echo 300 ;;
        *)  echo 60 ;;
    esac
}

# ─── Render Bar Chart ─────────────────────────────────────────────────────────
render_chart() {
    local title=$1
    local unit=$2
    local max_val=$3
    shift 3
    local -a hosts=("$@")

    local half=$(( (${#hosts[@]} + 1) / 2 ))
    local i

    echo
    echo "${BOLD}${CYAN}─── $title ─────${RESET}"

    # Header
    printf "${DIM}%-28s %s${RESET}\n" "Location" "$unit"
    echo "${DIM}$(printf '─%.0s' $(seq 1 68))${RESET}"

    if (($(echo "$max_val == 0" | bc -l))); then
        echo " ${RED}No data available${RESET}"
        return
    fi

    for ((i = 0; i < ${#hosts[@]}; i++)); do
        local host="${hosts[$i]}"
        local val="${data_vals[$i]}"
        local label="${data_labels[$i]}"

        if [[ "$val" == "N/A" || "$val" == "0" ]]; then
            printf "%-28s %s\n" "$host" "${DIM}no data${RESET}"
            continue
        fi

        local color
        if [[ "$title" == "Download Speed" ]]; then
            color=$(speed_color "$val")
        else
            color=$(latency_color "$val")
        fi

        printf "%-28s" "$host"
        draw_bar "$val" "$max_val"
        printf "${color}%s${RESET}\n" "$label"
    done | paste -d '' - - | while IFS= read -r line; do
        # Re-align: paste merges the two lines per host
        echo "$line"
    done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    local size_arg=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--size) size_arg="$2"; shift 2 ;;
            -h|--help) show_help ;;
            *) echo "${RED}Unknown option: $1${RESET}" >&2; show_help ;;
        esac
    done

    check_deps

    # ── Load config ──────────────────────────────────────────────────────────
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "${RED}Error: $CONFIG_FILE not found.${RESET}" >&2
        exit 1
    fi

    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        echo "${RED}Error: $CONFIG_FILE contains invalid JSON.${RESET}" >&2
        exit 1
    fi

    hosts=$(cat "$CONFIG_FILE")

    # ── Choose file size ─────────────────────────────────────────────────────
    if [[ -n "$size_arg" ]]; then
        choose_size "$size_arg"
    else
        echo
        interactive_size_prompt
    fi

    local timeout
    timeout=$(get_timeout "$size")

    echo
    echo "${BOLD}${CYAN}━━━ Hetzner Speedtest ── ${size_display} ━━━${RESET}"
    echo "${DIM}Testing $(echo "$hosts" | jq -r 'keys | length') locations …${RESET}"
    echo

    # ── Collect results ──────────────────────────────────────────────────────
    declare -A result_lat result_jitter result_lat_type result_speed
    local -a hosts_ordered=()

    start_time=$(date +%s)

    while IFS= read -r host; do
        hosts_ordered+=("$host")
        echo "${BOLD}${BLUE}▸ $host${RESET}"

        url=$(echo "$hosts" | jq -r --arg h "$host" --arg s "$size" '.[$h][$s]')

        # Latency & jitter (with TCP fallback)
        echo -n "  ${DIM}Latency:${RESET}         "
        lat_raw=$(measure_latency_jitter "$host" "${url:-}")
        IFS='|' read -r lat_val jitter_val lat_type <<< "$lat_raw"

        if [[ "$lat_type" == "unreachable" ]]; then
            echo "${RED}unreachable${RESET}"
            result_lat["$host"]=""
            result_jitter["$host"]=""
            result_lat_type["$host"]="unreachable"
        else
            local lat_label="${lat_val}ms"
            if [[ "$lat_type" == "tcp" ]]; then
                lat_label+=" ${DIM}(TCP)${RESET}"
            fi
            lat_label+=" / ${jitter_val}ms"
            echo "$lat_label"
            result_lat["$host"]="$lat_val"
            result_jitter["$host"]="$jitter_val"
            result_lat_type["$host"]="$lat_type"
        fi

        # Download speed
        if [[ -z "$url" || "$url" == "null" ]]; then
            echo "  ${DIM}Download:${RESET}       ${RED}no URL${RESET}"
            result_speed["$host"]=""
        else
            echo -n "  ${DIM}Download:${RESET}       "
            speed_val=$(measure_speed "$url" "$timeout")
            if [[ "$speed_val" == "failed" ]]; then
                echo "${RED}failed${RESET}"
                result_speed["$host"]=""
            else
                local speed_label="${speed_val} MB/s"
                echo "${GREEN}${speed_val} MB/s${RESET}"
                result_speed["$host"]="$speed_val"
            fi
        fi
        echo
    done < <(echo "$hosts" | jq -r 'keys[]')

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # ── Bar chart: Download Speed ────────────────────────────────────────────
    local max_speed=1
    for host in "${hosts_ordered[@]}"; do
        local s="${result_speed[$host]}"
        if [[ -n "$s" ]]; then
            if (($(echo "$s > $max_speed" | bc -l))); then
                max_speed=$s
            fi
        fi
    done

    echo "${BOLD}${CYAN}━━━ Visual Summary ━━━${RESET}"

    echo
    echo "${BOLD}Download Speed${RESET}  ${DIM}(longer bar = faster)${RESET}"
    for host in "${hosts_ordered[@]}"; do
        local s="${result_speed[$host]}"
        printf "  %-28s" "$host"
        if [[ -z "$s" ]]; then
            echo " ${DIM}no data${RESET}"
        else
            local c; c=$(speed_color "$s")
            draw_bar "$s" "$max_speed"
            echo "${c}${s} MB/s${RESET}"
        fi
    done | paste -d '' - -

    echo
    echo "${BOLD}Latency${RESET}  ${DIM}(shorter bar = better, █=ICMP ░=TCP fallback)${RESET}"
    local max_lat=1
    for host in "${hosts_ordered[@]}"; do
        local l="${result_lat[$host]}"
        if [[ -n "$l" ]]; then
            if (($(echo "$l > $max_lat" | bc -l))); then
                max_lat=$l
            fi
        fi
    done

    for host in "${hosts_ordered[@]}"; do
        local l="${result_lat[$host]}"
        local lt="${result_lat_type[$host]}"
        local j="${result_jitter[$host]}"
        printf "  %-28s" "$host"
        if [[ "$lt" == "unreachable" || -z "$l" ]]; then
            echo " ${RED}unreachable${RESET}"
        else
            local lat_c; lat_c=$(latency_color "$l")
            # Invert bar: lower latency = fuller bar
            local inv_lat; inv_lat=$(echo "scale=2; $l / $max_lat * $BAR_WIDTH" | bc)
            local bar_char="█"
            [[ "$lt" == "tcp" ]] && bar_char="░"
            local filled=$(echo "$inv_lat / 1" | bc 2>/dev/null || echo "0")
            filled=$((filled > BAR_WIDTH ? BAR_WIDTH : filled))
            filled=$((filled < 0 ? 0 : filled))
            local empty=$((BAR_WIDTH - filled))

            local bar=""
            printf -v bar '%*s' "$filled" ''; bar="${bar// /$bar_char}"
            printf -v bar '%s%*s' "$bar" "$empty" ''; bar="${bar// / }"

            echo "  $bar ${lat_c}${l}ms${RESET} ${DIM}/ ${j}ms${RESET}"
        fi
    done

    # ── Summary table ────────────────────────────────────────────────────────
    echo
    echo "${BOLD}${CYAN}━━━ Table ━━━${RESET}"
    printf "${BOLD}%-28s %-14s %-14s${RESET}\n" "Location" "Download" "Latency"
    echo "${DIM}$(printf '─%.0s' $(seq 1 60))${RESET}"
    for host in "${hosts_ordered[@]}"; do
        local s="${result_speed[$host]}"
        local l="${result_lat[$host]}"
        local lt="${result_lat_type[$host]}"

        local speed_display="${DIM}N/A${RESET}"
        if [[ -n "$s" ]]; then
            speed_display="${s} MB/s"
        fi

        local lat_display="${RED}unreachable${RESET}"
        if [[ "$lt" != "unreachable" && -n "$l" ]]; then
            local icmp_tag=""
            [[ "$lt" == "tcp" ]] && icmp_tag="${DIM}(TCP)${RESET} "
            lat_display="${icmp_tag}${l}ms"
        fi

        printf "%-28s %-14s %-14s\n" "$host" "$speed_display" "$lat_display"
    done
    echo "${DIM}$(printf '─%.0s' $(seq 1 60))${RESET}"
    echo "${DIM}Test completed in ${duration}s${RESET}"
    echo
}

main "$@"
