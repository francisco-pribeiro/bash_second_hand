# bash_second_hand

Two bash scripts to inspect a second-hand MacBook before buying it.

The scripts check battery health, SSD SMART status, kernel panic history, FileVault, and (with sudo) MDM enrollment — then produce a `PASS / WARN / FAIL` summary, a quick CPU/memory/disk benchmark, a manual-checks checklist, and an overall verdict.

## Run remotely (recommended)

On the seller's Mac, with internet access:

```bash
# Basic — no sudo required
curl -fsSL https://raw.githubusercontent.com/francisco-pribeiro/bash_second_hand/main/check_mac_basic.sh | bash

# Full — requires sudo (adds MDM, thermal/fan/power)
curl -fsSL https://raw.githubusercontent.com/francisco-pribeiro/bash_second_hand/main/check_mac_sudo.sh | sudo bash
```

`curl | bash` avoids macOS quarantine on downloaded files. Read the script first by opening the raw URL in a browser.

## Run locally

```bash
git clone https://github.com/francisco-pribeiro/bash_second_hand.git
cd bash_second_hand

./check_mac_basic.sh
sudo ./check_mac_sudo.sh
```

Each run also writes a timestamped report to `mac_report_basic_<timestamp>.txt` or `mac_report_full_<timestamp>.txt`.

## Stress test (manual, 5 minutes)

The scripts give a snapshot. To catch thermal throttling, fan problems, or random shutdowns, run a sustained CPU load:

```bash
# Start (one process per CPU core — adjust the number to match your core count)
yes > /dev/null & yes > /dev/null & yes > /dev/null & yes > /dev/null

# Wait 5 minutes — listen to the fans, feel the chassis temperature

# Stop
killall yes
```

Watch for: random shutdown, kernel panic, extreme heat, fan grinding or silence (broken fan), screen artifacts on external display.

## Verdict tiers

| Verdict   | Trigger                  |
|-----------|--------------------------|
| EXCELLENT | 0 fails, 0 warnings      |
| NEGOTIATE | 0 fails, 1–2 warnings    |
| CAUTION   | 0 fails, 3+ warnings     |
| AVOID     | 1 critical failure       |
| REJECT    | 2+ critical failures     |

## What the scripts cannot test

The report ends with a manual-checks checklist covering keyboard, trackpad, speakers, mic, camera, ports, fans, hinge, chassis, Wi-Fi/Bluetooth radios, charging port, and ownership/security (iCloud sign-out, Activation Lock, theft check at [checkcoverage.apple.com](https://checkcoverage.apple.com)). Always verify those by hand.
