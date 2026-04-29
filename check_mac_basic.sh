#!/usr/bin/env bash
# No sudo required.
# Outputs a health summary with PASS/WARN/FAIL, then details and benchmarks.

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="mac_report_basic_${TIMESTAMP}.txt"

# ── Helpers ────────────────────────────────────────────────────────────────────

section() { printf "\n══════════════════════════════\n  %s\n══════════════════════════════\n" "$1"; }

pass()    { printf "  [PASS] %s\n" "$*"; }
warn()    { printf "  [WARN] %s\n" "$*"; }
fail()    { printf "  [FAIL] %s\n" "$*"; }
info()    { printf "  [INFO] %s\n" "$*"; }
unknown() { printf "  [????] %s\n" "$*"; }

# ── Data collection ────────────────────────────────────────────────────────────

echo "[1/5] Reading power data..." >&2
POWER_DATA=$(system_profiler SPPowerDataType 2>/dev/null)

echo "[2/5] Reading hardware data..." >&2
HW_DATA=$(system_profiler SPHardwareDataType 2>/dev/null)

echo "[3/5] Reading disk info..." >&2
STORAGE_DATA=$(diskutil info disk0 2>/dev/null)
SMART_STATUS=$(echo "$STORAGE_DATA" | awk -F': ' '/SMART Status/{gsub(/^[ \t]+/,"",$2); print $2}')

echo "[4/5] Reading FileVault status..." >&2
FILEVAULT_STATUS=$(fdesetup status 2>/dev/null)

echo "[5/5] Counting panic reports..." >&2
PANIC_COUNT=$(find /Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports \
                   -name "*.panic" -mtime -30 2>/dev/null | wc -l | tr -d ' ')

echo "Done collecting. Generating report..." >&2

BATTERY_CYCLES=$(echo "$POWER_DATA" | awk '/Cycle Count/{print $NF}')
BATTERY_CAPACITY=$(echo "$POWER_DATA" | awk '/Maximum Capacity/{gsub(/%/,"",$NF); print $NF}')

# ── Evaluation phase (build summary + tally fails/warns) ───────────────────────

SUMMARY_LINES=()
FAIL_COUNT=0
WARN_COUNT=0

add_line() {
  local status="$1" text="$2"
  SUMMARY_LINES+=("  [$status] $text")
  case "$status" in
    FAIL) FAIL_COUNT=$((FAIL_COUNT+1)) ;;
    WARN) WARN_COUNT=$((WARN_COUNT+1)) ;;
  esac
}

# Battery cycles
if [[ -z "$BATTERY_CYCLES" ]]; then
  add_line "????" "Battery cycle count: not available"
elif (( BATTERY_CYCLES < 200 )); then
  add_line "PASS" "Battery cycles: $BATTERY_CYCLES  (excellent — under 200)"
elif (( BATTERY_CYCLES < 500 )); then
  add_line "WARN" "Battery cycles: $BATTERY_CYCLES  (moderate — 200–499)"
elif (( BATTERY_CYCLES < 800 )); then
  add_line "WARN" "Battery cycles: $BATTERY_CYCLES  (aging — 500–799, budget for replacement)"
else
  add_line "FAIL" "Battery cycles: $BATTERY_CYCLES  (near end of life — 800+)"
fi

# Battery capacity
if [[ -z "$BATTERY_CAPACITY" ]]; then
  add_line "????" "Battery capacity: not available"
elif (( BATTERY_CAPACITY >= 80 )); then
  add_line "PASS" "Battery capacity: ${BATTERY_CAPACITY}%  (healthy)"
elif (( BATTERY_CAPACITY >= 60 )); then
  add_line "WARN" "Battery capacity: ${BATTERY_CAPACITY}%  (degraded — 60–79%)"
else
  add_line "FAIL" "Battery capacity: ${BATTERY_CAPACITY}%  (poor — below 60%, replacement needed)"
fi

# SMART status
if [[ "$SMART_STATUS" == "Verified" ]]; then
  add_line "PASS" "SSD SMART status: Verified"
elif [[ -z "$SMART_STATUS" ]]; then
  add_line "????" "SSD SMART status: could not read"
else
  add_line "FAIL" "SSD SMART status: $SMART_STATUS  (drive may be failing)"
fi

# Panic reports
if [[ "$PANIC_COUNT" -eq 0 ]]; then
  add_line "PASS" "Panic reports (last 30 days): 0"
elif [[ "$PANIC_COUNT" -le 2 ]]; then
  add_line "WARN" "Panic reports (last 30 days): $PANIC_COUNT  (investigate cause)"
else
  add_line "FAIL" "Panic reports (last 30 days): $PANIC_COUNT  (hardware instability likely)"
fi

# FileVault
if echo "$FILEVAULT_STATUS" | grep -q "FileVault is Off"; then
  add_line "PASS" "FileVault: Off  (drive was wiped/reset)"
elif echo "$FILEVAULT_STATUS" | grep -q "FileVault is On"; then
  add_line "INFO" "FileVault: On  (encrypted — you have access since you're running this)"
else
  add_line "????" "FileVault: $FILEVAULT_STATUS"
fi

# Verdict
if (( FAIL_COUNT >= 2 )); then
  VERDICT="REJECT"
  VERDICT_TEXT="$FAIL_COUNT critical failures — do not buy."
elif (( FAIL_COUNT == 1 )); then
  VERDICT="AVOID"
  VERDICT_TEXT="1 critical failure — only buy if you can repair, and at a steep discount."
elif (( WARN_COUNT >= 3 )); then
  VERDICT="CAUTION"
  VERDICT_TEXT="$WARN_COUNT warnings — multiple concerns. Negotiate hard."
elif (( WARN_COUNT > 0 )); then
  VERDICT="NEGOTIATE"
  VERDICT_TEXT="$WARN_COUNT warning(s) — minor wear, fair to ask for a small discount."
else
  VERDICT="EXCELLENT"
  VERDICT_TEXT="No issues detected by the script. Proceed with manual checks."
fi

# ── Print sections ─────────────────────────────────────────────────────────────

print_summary() {
  section "HEALTH SUMMARY"
  printf "%s\n" "${SUMMARY_LINES[@]}"
  printf "  [INFO] MDM enrollment: run sudo script to check\n"
  printf "  [INFO] iCloud Activation Lock: verify manually in System Settings > Apple ID\n"
  printf "\n"
}

print_verdict() {
  section "OVERALL VERDICT"
  printf "  >>> %s <<<\n" "$VERDICT"
  printf "  %s\n" "$VERDICT_TEXT"
  printf "  (Critical failures: %d   Warnings: %d)\n" "$FAIL_COUNT" "$WARN_COUNT"
}

print_manual_checks() {
  section "MANUAL CHECKS — the script cannot test these"
  cat <<'EOF'

  PHYSICAL HARDWARE
    [ ] Keyboard — press EVERY key (butterfly keyboards 2016–2019 often fail)
    [ ] Trackpad — click, force-touch, multi-finger gestures, all edges
    [ ] Speakers — play stereo audio, listen for distortion, test L/R balance
    [ ] Microphone — record a short clip
    [ ] Camera — open Photo Booth
    [ ] All ports — plug a charger / USB drive / monitor into each
    [ ] Fans — listen for grinding/rattling under CPU load (see stress test below)
    [ ] Hinge — smooth open/close, no looseness or cracking
    [ ] Chassis — dents, drops, scuffs; check for liquid contact indicators
    [ ] Bottom screws — missing/stripped indicates prior repair
    [ ] Touch ID / power button — register a fingerprint and test

  SCREEN (broken in this case — confirm via external display)
    [ ] Connects to external monitor via USB-C / HDMI adapter
    [ ] LCD itself works if glass is cracked but backlight is on
    [ ] Check for: dead pixels, lines, ghosting, uneven backlight

  RADIOS
    [ ] Wi-Fi — connect to a known network, check signal strength
    [ ] Bluetooth — pair a device (phone, headphones)

  POWER
    [ ] Charges from the original-spec charger
    [ ] Charge port is firm (no wiggle, no spark, no heat)
    [ ] Battery doesn't drain rapidly when idle

  SECURITY / OWNERSHIP
    [ ] Previous owner is signed OUT of iCloud / Apple ID
    [ ] Activation Lock disabled (System Settings > Apple ID)
    [ ] App Store / iTunes / Messages signed out
    [ ] Original receipt or proof of purchase available
    [ ] Verify serial at: https://checkcoverage.apple.com (warranty + theft check)
    [ ] Ask seller to fully erase + reinstall macOS in front of you (best case)

  STRESS TEST (5 minutes, watch for shutdowns / throttling / fan noise)
    Run on the laptop:
      yes > /dev/null & yes > /dev/null & yes > /dev/null & yes > /dev/null
    Wait 5 minutes, then stop:
      killall yes
    Symptoms of trouble: random shutdown, kernel panic, extreme heat, screen
    artifacts, fan grinding/silence (broken fan).
EOF
}

# ── Detail sections ────────────────────────────────────────────────────────────

print_details() {
  section "OS VERSION"
  sw_vers

  section "HARDWARE"
  echo "$HW_DATA" | grep -E "Model Name|Model Identifier|Model Number|Chip|Processor|Total Number|Memory:|Serial Number|Hardware UUID"

  section "BATTERY DETAIL"
  echo "$POWER_DATA" | grep -E "Cycle Count|Maximum Capacity|Condition|Charging|Full Charge Capacity|Design Capacity|State of Charge"
  echo ""
  pmset -g batt

  section "MEMORY USAGE"
  TOTAL_RAM=$(sysctl -n hw.memsize | awk '{printf "%.0f GB\n", $1/1024/1024/1024}')
  echo "  Total RAM: $TOTAL_RAM"
  echo ""
  vm_stat | awk '
    /page size/              { ps = $8 }
    /Pages free/             { free = $3+0 }
    /Pages active/           { active = $3+0 }
    /Pages inactive/         { inactive = $3+0 }
    /Pages wired/            { wired = $4+0 }
    /Pages occupied by comp/ { comp = $5+0 }
    /Pageouts/               { pageouts = $2+0 }
    END {
      gb = 1024^3
      printf "  Free:        %.2f GB\n",  (free   * ps) / gb
      printf "  Active:      %.2f GB\n",  (active * ps) / gb
      printf "  Wired:       %.2f GB\n",  (wired  * ps) / gb
      printf "  Compressed:  %.2f GB\n",  (comp   * ps) / gb
      if (pageouts > 0)
        printf "  [WARN] Pageouts detected (%d) — system has swapped to disk\n", pageouts
      else
        printf "  [PASS] No pageouts — RAM has been sufficient\n"
    }
  '

  section "DISK"
  echo "  SMART: $SMART_STATUS"
  echo ""
  df -h | grep -v "^map\|^devfs\|^/dev/disk[0-9]s[0-9]*s"
  echo ""
  echo "$STORAGE_DATA" | grep -E "Device / Media Name|Disk Size|Protocol|SMART|Solid State|TRIM"

  section "GPU (from hardware overview)"
  echo "$HW_DATA" | grep -E "Chip|Graphics|GPU"
  echo "  (display probe skipped — screen reported as broken)"

  section "UPTIME"
  uptime

  section "RECENT PANIC REPORTS (last 30 days)"
  if [[ "$PANIC_COUNT" -eq 0 ]]; then
    echo "  None found."
  else
    find /Library/Logs/DiagnosticReports ~/Library/Logs/DiagnosticReports \
         -name "*.panic" -mtime -30 2>/dev/null
  fi

  section "CRASH REPORTS (last 10 files)"
  ls -lt ~/Library/Logs/DiagnosticReports/ 2>/dev/null | head -11 \
    || echo "  No crash reports found."
}

# ── Benchmarks ─────────────────────────────────────────────────────────────────

print_benchmarks() {
  section "BENCHMARKS"

  echo "  --- CPU (OpenSSL RSA-2048, 3 seconds) ---"
  echo "  Higher sign/s = better. Healthy Apple Silicon: 2000+ sign/s"
  openssl speed -seconds 3 rsa2048 2>&1 | grep -E "rsa2048|^Doing"

  echo ""
  echo "  --- Memory bandwidth (write 1 GB to /dev/null) ---"
  echo "  Healthy Apple Silicon: 20 GB/s+"
  { time dd if=/dev/zero bs=1m count=1024 of=/dev/null 2>&1; } 2>&1

  echo ""
  echo "  --- Disk write + read (512 MB via /tmp) ---"
  echo "  Healthy NVMe SSD: 1000 MB/s+ read"
  TMP_FILE="/tmp/_mac_disk_bench_$$"
  echo "  Write:"
  dd if=/dev/zero bs=1m count=512 of="$TMP_FILE" 2>&1
  echo "  Read:"
  dd if="$TMP_FILE" of=/dev/null bs=1m 2>&1
  rm -f "$TMP_FILE"
}

# ── Main ───────────────────────────────────────────────────────────────────────

{
  echo "Mac Diagnostic — Basic (no sudo)"
  echo "Generated : $(date)"
  echo "Hostname  : $(hostname)"

  print_summary
  print_details
  print_benchmarks
  print_manual_checks
  print_verdict

  section "END OF REPORT"
} | tee "$OUTPUT_FILE"

echo ""
echo "Report saved to: $OUTPUT_FILE"
