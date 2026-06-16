# Hetzner Speedtest

A Bash script for measuring **download speed**, **latency**, and **jitter** against Hetzner data centers worldwide. Uses `curl` for bandwidth tests and `ping` for network quality metrics with automatic TCP fallback.

## Features

- **Download speed test** against 5 Hetzner locations (Falkenstein, Helsinki, Nuremberg, Ashburn, Hillsboro)
- **Latency & jitter** via ICMP ping with automatic TCP fallback (`time_connect`) for networks behind CGNAT or where ICMP is blocked
- **3 file sizes**: 100 MB, 1 GB, 10 GB
- **TUI-style bar chart** visualization of results
- **Colorized terminal output** (auto-disabled for non-TTY / piped output)
- **Summary table** after all tests complete
- **Non-interactive mode** with `--size` flag for automation / scripting
- **Dependency validation** at startup
- **JSON validation** for the hosts configuration file
- **Nix flake** & **Docker** support

## Prerequisites

| Tool | Purpose |
|------|---------|
| `bash` | Script runtime |
| `curl` | HTTP download speed & TCP latency measurement |
| `ping` | ICMP latency & jitter measurement |
| `jq` | JSON parsing for host configuration |
| `bc` | Floating-point arithmetic |
| `tput` | Terminal color output (optional, gracefully degraded) |

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

### Direct

```bash
git clone https://github.com/<your-username>/hetzner-speedtest-bash.git
cd hetzner-speedtest-bash
chmod +x hetzner-speedtest.sh
```

### Nix

```bash
# Run directly (no install needed)
nix run github:<your-username>/hetzner-speedtest-bash -- --size small

# Or enter a dev shell with dependencies & linters
nix develop github:<your-username>/hetzner-speedtest-bash
```

### Docker

```bash
# Build
docker build -t hetzner-speedtest .

# Run (non-interactive)
docker run --rm hetzner-speedtest --size small

# Interactive mode requires -it
docker run --rm -it hetzner-speedtest
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

### Per-host detail during test run

```
━━━ Hetzner Speedtest ── 1GB ━━━
Testing 5 locations …

▸ fsn1-speed.hetzner.com
  Latency:         1.23ms / 0.45ms
  Download:        112.45 MB/s

▸ hil-speed.hetzner.com
  Latency:         182.34ms (TCP) / 0.00ms    ← ICMP blocked, TCP fallback
  Download:        45.10 MB/s

▸ hel.icmp.hetzner.com
  Latency:         unreachable                 ← fully unreachable
  Download:        89.32 MB/s
```

### Bar chart visualization at end

```
━━━ Visual Summary ━━━

Download Speed  (longer bar = faster)
  fsn1-speed.hetzner.com        ████████████████████████████████  112.45 MB/s
  nbg1-speed.hetzner.com        ███████████████████████████████   105.20 MB/s
  hel.icmp.hetzner.com          ███████████████████████           89.32 MB/s
  hil-speed.hetzner.com         ████████████                     45.10 MB/s
  ash-speed.hetzner.com         █████████████████████             78.90 MB/s

Latency  (shorter bar = better, █=ICMP ░=TCP fallback)
  fsn1-speed.hetzner.com        ████████████████████████████████  1.23ms / 0.45ms
  nbg1-speed.hetzner.com        ███████████████████████████████   1.45ms / 0.50ms
  hel.icmp.hetzner.com          ████                              45.67ms / 2.10ms
  ash-speed.hetzner.com         ███████                           78.90ms / 1.20ms
  hil-speed.hetzner.com         ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   182.34ms / 0.00ms
```

### Fallback table

```
━━━ Table ━━━
Location                      Download       Latency
────────────────────────────────────────────────────────────
fsn1-speed.hetzner.com        112.45 MB/s    1.23ms
hel.icmp.hetzner.com          89.32 MB/s     45.67ms
hil-speed.hetzner.com         45.10 MB/s     (TCP) 182.34ms
────────────────────────────────────────────────────────────
Test completed in 24s
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

The script finds `hosts.json` relative to the script itself. Override the path by setting `CONFIG_DIR`:

```bash
CONFIG_DIR=/custom/path ./hetzner-speedtest.sh
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
- **Ping-based latency** uses ICMP packets which may be rate-limited or blocked by some networks. The script falls back to TCP connection time via `curl` when ICMP is unavailable.
- **TCP latency fallback** measures only the TCP handshake time (not round-trip), so values may be slightly lower than actual ICMP RTT.

## Nix Flake

```bash
# Build the package
nix build .

# Run directly
nix run . -- --size small

# Dev shell with shellcheck & shfmt
nix develop
```

## Docker

```bash
# Build
docker build -t hetzner-speedtest .

# Run with small file (non-interactive)
docker run --rm hetzner-speedtest -s small
```

## License

MIT
