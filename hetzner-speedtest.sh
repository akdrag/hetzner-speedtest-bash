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
    readonly WHITE=$(tput setaf 7)
    readonly DIM=$(tput dim)
    readonly RESET=$(tput sgr0)
else
    readonly BOLD="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN="" WHITE="" DIM="" RESET=""
fi

# ─── Config ───────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly SCRIPT_NAME=$(basename "$0")
readonly CONFIG_FILE="${CONFIG_DIR:-$SCRIPT_DIR}/hosts.json"
readonly PING_COUNT=10

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
        small|1)
            size="sm"
            size_display="100MB"
            ;;
        medium|2)
            size="md"
            size_display="1GB"
            ;;
        large|3)
            size="lg"
            size_display="10GB"
            ;;
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

# ─── Measure Latency & Jitter ─────────────────────────────────────────────────
measure_latency_jitter() {
    local host=$1

    ping_output=$(ping -c "$PING_COUNT" "$host" 2>/dev/null | awk -F'time=' '/time=/{print $2}' | cut -d' ' -f1)

    if [[ -z "$ping_output" ]]; then
        echo "${RED}Unreachable${RESET}"
        return
    fi

    latency=$(echo "$ping_output" | awk '{sum+=$1; count+=1} END {if (count > 0) printf "%.2f", sum/count; else print "N/A"}')
    jitter=$(echo "$ping_output" | awk -v mean="$latency" '
        {sum+=($1-mean)^2}
        END {if (NR > 1) printf "%.2f", sqrt(sum/(NR-1)); else print "N/A"}
    ')

    echo "${latency}ms / ${jitter}ms"
}

# ─── Measure Download Speed ────────────────────────────────────────────────────
measure_speed() {
    local url=$1

    speed=$(curl -s -w "%{speed_download}" -o /dev/null "$url" 2>/dev/null || echo "0")

    if [[ "$speed" == "0" ]]; then
        echo "${RED}Failed${RESET}"
        return
    fi

    speed_mb=$(echo "scale=2; $speed / 1048576" | bc)
    echo "$speed_mb"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    local size_arg=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--size)
                size_arg="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo "${RED}Unknown option: $1${RESET}" >&2
                show_help
                ;;
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

    echo
    echo "${BOLD}${CYAN}━━━ Hetzner Speedtest ── ${size_display} ━━━${RESET}"
    echo "${DIM}Testing $(echo "$hosts" | jq -r 'keys | length') locations …${RESET}"
    echo

    # ── Collect results for summary ──────────────────────────────────────────
    declare -A results_latency results_speed

    start_time=$(date +%s)

    while IFS= read -r host; do
        echo "${BOLD}${BLUE}▸ $host${RESET}"

        # Latency & jitter
        echo -n "  ${DIM}Latency/Jitter:${RESET} "
        lat_result=$(measure_latency_jitter "$host")
        results_latency["$host"]="$lat_result"
        echo "$lat_result"

        # Download speed
        url=$(echo "$hosts" | jq -r --arg host "$host" --arg size "$size" '.[$host][$size]')

        if [[ -z "$url" || "$url" == "null" ]]; then
            echo "  ${DIM}Download:${RESET}       ${RED}No URL configured${RESET}"
            results_speed["$host"]="N/A"
        else
            echo -n "  ${DIM}Download:${RESET}       "
            speed_val=$(measure_speed "$url")
            if [[ "$speed_val" == "${RED}Failed${RESET}" ]]; then
                echo "${RED}Download failed${RESET}"
                results_speed["$host"]="Failed"
            else
                echo "${GREEN}${speed_val} MB/s${RESET}"
                results_speed["$host"]="$speed_val MB/s"
            fi
        fi
        echo
    done < <(echo "$hosts" | jq -r 'keys[]')

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # ── Summary table ────────────────────────────────────────────────────────
    echo "${BOLD}${CYAN}━━━ Summary ━━━${RESET}"
    printf "${BOLD}%-30s %-22s %-14s${RESET}\n" "Location" "Latency / Jitter" "Download"
    echo "${DIM}$(printf '%.0s─' {1..68})${RESET}"
    while IFS= read -r host; do
        printf "%-30s %-22s %-14s\n" "$host" "${results_latency[$host]}" "${results_speed[$host]}"
    done < <(echo "$hosts" | jq -r 'keys[]')
    echo "${DIM}$(printf '%.0s─' {1..68})${RESET}"
    echo "${DIM}Test completed in ${duration}s${RESET}"
    echo
}

main "$@"
