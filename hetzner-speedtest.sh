#!/bin/bash

#download speed
measure_speed() {
    local url=$1
    local size=$2
    speed=$(curl -s -w "%{speed_download}" -o /dev/null "$url" || echo "0")
    if [[ "$speed" == "0" ]]; then
        echo "Download failed"
    else
        speed=$(echo "scale=2; $speed / 1048576" | bc)
        echo "$speed MB/s ($size)"
    fi
}

# measure latency and jitter
measure_latency_jitter() {
    local host=$1
    ping_output=$(ping -c 10 "$host" | awk -F'time=' '/time=/{print $2}' | cut -d' ' -f1)
    
    # average latency and jitter (standard deviation)
    latency=$(echo "$ping_output" | awk '{sum+=$1; count+=1} END {if (count > 0) print sum/count; else print "N/A"}')
    jitter=$(echo "$ping_output" | awk -v mean=$latency '{sum+=($1-mean)^2} END {if (NR > 1) print sqrt(sum/(NR-1)); else print "N/A"}')

    echo "Latency: ${latency}ms, Jitter: ${jitter}ms"
}

# host data from JSON file
if [[ ! -f hosts.json ]]; then
    echo "Error: hosts.json file not found."
    exit 1
fi
hosts=$(cat hosts.json)

# file size choice
echo "Choose file size for the test:"
echo "1) Small (100MB)"
echo "2) Medium (1GB)"
echo "3) Large (10GB)"
read -p "Enter your choice (1, 2, or 3): " choice

# Set size based on choice
case $choice in
    1) size="sm"; size_display="100MB" ;;
    2) size="md"; size_display="1GB" ;;
    3) size="lg"; size_display="10GB" ;;
    *) echo "Invalid choice. Exiting."; exit 1 ;;
esac

echo "Running tests with $size_display files"
echo

# Loop through each host and perform tests
echo "$hosts" | jq -r 'keys[]' | while read -r host; do
    echo "Testing $host"
    echo "-------------"
    
    # Measure latency and jitter
    measure_latency_jitter "$host"
    
    # Measure download speed
    url=$(echo "$hosts" | jq -r ".\"$host\".$size")
    if [[ -z "$url" || "$url" == "null" ]]; then
        echo "Error: URL for $size_display file not found for host $host."
    else
        echo "Download speed:"
        echo "  $(measure_speed "$url" "$size_display")"
    fi
    echo
done
