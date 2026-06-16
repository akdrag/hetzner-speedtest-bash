# Hetzner Speedtest

A Bash script for measuring **download speed**, **latency**, and **jitter** against Hetzner data centers worldwide. Uses `curl` for bandwidth tests and `ping` for network quality metrics.

## Features

- **Download speed test** against 5 Hetzner locations (Falkenstein, Helsinki, Nuremberg, Ashburn, Hillsboro)
- **Latency & jitter measurement** using 10 consecutive pings
- **3 file sizes**: 100 MB, 1 GB, 10 GB
- **Colorized terminal output** (auto-disabled for non-TTY / piped output)
- **Summary table** after all tests complete
- **Non-interactive mode** with `--size` flag for automation / scripting
- **Dependency validation** at startup
- **JSON validation** for the hosts configuration file

## Prerequisites

| Tool | Purpose |
|------|---------|
| `bash` | Script runtime |
| `curl` | HTTP download speed measurement |
| `ping` | Latency & jitter measurement |
| `jq` | JSON parsing for host configuration |
| `bc` | Floating-point arithmetic |
| `tput` | Terminal color output |

Install missing dependencies via your package manager:

```bash
# Debian / Ubuntu
sudo apt install curl jq bc

# RHEL / Fedora
sudo dnf install curl jq bc

# Alpine
apk add curl jq bc
```

## Installation

```bash
git clone https://github.com/<your-username>/hetzner-speedtest-bash.git
cd hetzner-speedtest-bash
chmod +x hetzner-speedtest.sh
```

## Usage

### Interactive mode

```bash
./hetzner-speedtest.sh
```

You will be prompted to choose a file size:

```
Choose file size for the test:
  1) Small  (100MB)
  2) Medium (1GB)
  3) Large  (10GB)
Enter your choice (1, 2, or 3):
```

### Non-interactive mode

```bash
./hetzner-speedtest.sh --size small
./hetzner-speedtest.sh -s medium
./hetzner-speedtest.sh -s large
```

### Help

```bash
./hetzner-speedtest.sh --help
```

## Output

```
━━━ Hetzner Speedtest ── 100MB ━━━
Testing 5 locations …

▸ fsn1-speed.hetzner.com
  Latency/Jitter: 1.23ms / 0.45ms
  Download:       112.45 MB/s

▸ hel.icmp.hetzner.com
  Latency/Jitter: 45.67ms / 2.10ms
  Download:       89.32 MB/s

━━━ Summary ━━━
Location                       Latency / Jitter      Download
────────────────────────────────────────────────────────────────────
fsn1-speed.hetzner.com         1.23ms / 0.45ms       112.45 MB/s
hel.icmp.hetzner.com           45.67ms / 2.10ms      89.32 MB/s
nbg1-speed.hetzner.com         …
ash-speed.hetzner.com          …
hil-speed.hetzner.com          …
────────────────────────────────────────────────────────────────────
Test completed in 12s
```

## Configuration

Edit `hosts.json` to add, remove, or change test locations. Each entry maps a hostname to URLs for the three file sizes (`sm`, `md`, `lg`):

```json
{
  "fsn1-speed.hetzner.com": {
    "sm": "https://fsn1-speed.hetzner.com/100MB.bin",
    "md": "https://fsn1-speed.hetzner.com/1GB.bin",
    "lg": "https://fsn1-speed.hetzner.com/10GB.bin"
  }
}
```

## Test Locations

| Key | Location | Region |
|-----|----------|--------|
| `fsn1` | Falkenstein | Europe (Germany) |
| `hel` | Helsinki | Europe (Finland) |
| `nbg1` | Nuremberg | Europe (Germany) |
| `ash` | Ashburn | US East |
| `hil` | Hillsboro | US West |

## Caveats

- **Download speeds are measured over a single HTTP connection** and may not reflect the maximum available throughput. Multi-threaded tools like `iperf3` will yield higher numbers.
- **Large file downloads (10 GB)** may incur data charges. Use caution on metered connections.
- **Ping-based latency** uses ICMP packets which may be rate-limited or blocked by some networks.

## License

MIT
