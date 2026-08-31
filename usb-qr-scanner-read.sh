#!/bin/bash

# Set the HID device path (update if needed)
EVENT_DEV="/dev/input/by-id/usb-TMS_HIDKeyBoard_1234567890abcd-event-kbd"
MOONRAKER_SCHEME="http"
MOONRAKER_HOST="localhost"
MOONRAKER_PORT="7125"
SPOOLMAN_PREFIX="web+spoolman:s-"
MOONRAKER_PREFIX="web+moonraker:"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Optional user overrides.  Any setting in this file wins over the defaults
# above.  It defaults to the standard Klipper config directory so it can be
# edited from Mainsail/Fluidd and is captured by config backups, and so it
# survives updates of this repository.
#
# The file uses Klipper's own config format and is parsed by the helper script
# with the same configparser settings Klipper uses, so a file that Klipper would
# accept behaves the same way here.
QR_SCANNER_CONF="${QR_SCANNER_CONF:-$HOME/printer_data/config/qr-scanner.conf}"

if [ -e "$QR_SCANNER_CONF" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required to read $QR_SCANNER_CONF" >&2
        exit 1
    fi

    # Capture the helper's output rather than sourcing it.  Sourcing a process
    # substitution (". <(helper)") discards the helper's exit status, so a
    # config file the helper could not read would silently fall back to the
    # defaults above and then fail later with a "device not found" naming a
    # device the user never configured.
    if ! qr_scanner_settings="$(python3 "$SCRIPT_DIR/qr-scanner-config.py" "$QR_SCANNER_CONF")"; then
        echo "Error: could not read $QR_SCANNER_CONF" >&2
        exit 1
    fi

    # The helper shell-quotes every value, so a config file cannot inject shell
    # code here -- worth care, because the config directory is served by the web
    # UI.  Check the shape of what came back before evaluating it, which is only
    # possible because it was captured rather than sourced.
    if [ -n "$qr_scanner_settings" ] && grep -qvE '^[A-Z_]+=' <<< "$qr_scanner_settings"; then
        echo "Error: unexpected output from qr-scanner-config.py" >&2
        exit 1
    fi

    eval "$qr_scanner_settings"
fi

# Check if evtest is installed
if ! command -v evtest >/dev/null 2>&1; then
    echo "Error: evtest is not installed or not in PATH."
    exit 1
fi

# Check device exists
if [ ! -e "$EVENT_DEV" ]; then
    echo "Error: scanner input device not found:"
    echo "    $EVENT_DEV"
    echo
    echo "Set 'event_dev' in the [qr_scanner] section of:"
    echo "    $QR_SCANNER_CONF"
    echo "(copy qr-scanner.conf.example from this repository to get started)."
    echo
    echo "Keyboard-like input devices currently attached:"
    found=0
    for dev in /dev/input/by-id/*-event-kbd; do
        [ -e "$dev" ] || continue
        echo "    $dev"
        found=1
    done
    if [ "$found" -eq 0 ]; then
        echo "    (none found - is the scanner plugged in?)"
    fi
    exit 1
fi

post_next_spool_id() {
    local SPOOL_ID="$1"
    curl -X POST "${MOONRAKER_SCHEME}://${MOONRAKER_HOST}:${MOONRAKER_PORT}/printer/gcode/script" \
        -H "Content-Type: application/json" \
        -d "{\"script\": \"SET_NEXT_SPOOL_ID SPOOL_ID=${SPOOL_ID}\"}"
}

set_moonraker_target() {
    local target_raw="$1"
    local target
    local host
    local port

    # Strip whitespace so accidental spaces in a scan do not break parsing.
    target="$(echo "$target_raw" | tr -d '[:space:]')"

    if [[ -z "$target" ]]; then
        echo "Ignoring Moonraker target: empty value"
        return 1
    fi

    # Parse and strip optional scheme (http:// or https://).
    if [[ "$target" == https://* ]]; then
        MOONRAKER_SCHEME="https"
        target="${target#https://}"
    elif [[ "$target" == http://* ]]; then
        MOONRAKER_SCHEME="http"
        target="${target#http://}"
    fi

    # Strip any trailing path (anything from the first / onward).
    target="${target%%/*}"

    # Split into host and optional port, then validate each part separately.
    host="${target%%:*}"
    port="${target#"$host"}"
    port="${port#:}"  # strip leading colon, leaving just the number (or empty)

    if [[ ! "$host" =~ ^[A-Za-z0-9.-]+$ ]]; then
        echo "Ignoring Moonraker target: invalid host '$host'"
        return 1
    fi

    if [[ -n "$port" && ! "$port" =~ ^[0-9]+$ ]]; then
        echo "Ignoring Moonraker target: invalid port '$port'"
        return 1
    fi

    if [[ -n "$port" && ( "$port" -lt 1 || "$port" -gt 65535 ) ]]; then
        echo "Ignoring Moonraker target: invalid port '$port'"
        return 1
    fi

    MOONRAKER_HOST="$host"
    if [[ -n "$port" ]]; then
        MOONRAKER_PORT="$port"
    fi

    echo "Moonraker target set to ${MOONRAKER_SCHEME}://${MOONRAKER_HOST}:${MOONRAKER_PORT}"
    return 0
}

process_line() {
    local line="$1"
    if [[ "$line" == "$SPOOLMAN_PREFIX"* ]]; then
        echo "Magic code Scanned"
        SPOOL_ID="${line#$SPOOLMAN_PREFIX}"
        post_next_spool_id "${SPOOL_ID}"
    elif [[ "$line" == "http"* ]]; then
        echo "URL Scanned"
        SPOOL_ID=`echo $line | cut -d'/' -f6`
        post_next_spool_id "${SPOOL_ID}"
    elif [[ "$line" == "$MOONRAKER_PREFIX"* ]]; then
        echo "Moonraker code Scanned"
        set_moonraker_target "${line#$MOONRAKER_PREFIX}"
    fi
}

echo "Reading from $EVENT_DEV (Ctrl+C to stop)..."

# Keycode to character mapping (partial, add more as needed)
KEYS=( "" "ESC" "1" "2" "3" "4" "5" "6" "7" "8" "9" "0" "-" "=" "BACKSPACE" "TAB"
    "q" "w" "e" "r" "t" "y" "u" "i" "o" "p" "[" "]" "ENTER" "CTRL"
    "a" "s" "d" "f" "g" "h" "j" "k" "l" ";" "'" "\`" "LSHIFT" "\\" "z" "x"
    "c" "v" "b" "n" "m" "," "." "/" "RSHIFT" "*" "ALT" "SPACE" )

buffer=""

evtest "$EVENT_DEV" 2>/dev/null | \
while read -r line; do
    # Only process key press events
    if [[ "$line" =~ "EV_KEY" ]] && [[ "$line" =~ "value 1" ]]; then
        # Extract keycode number
        keycode=$(echo "$line" | sed -n 's/.*code \([0-9]\+\) (.*/\1/p')

        # Map keycode to index in KEYS array if possible
        if [[ "$keycode" =~ ^[0-9]+$ ]]; then
            keyname="${KEYS[$keycode]}"

            # Track shift state
            if [[ "$keyname" == "LSHIFT" || "$keyname" == "RSHIFT" ]]; then
                shift_active=1
            elif [[ "$keyname" == "ENTER" ]]; then
                echo "Scanned code: $buffer"
                process_line "$buffer"
                buffer=""
            elif [[ -n "$keyname" ]]; then
                # Handle shift for letters and some symbols
                if [[ "$shift_active" == "1" ]]; then
                    # Uppercase letters
                    if [[ "$keyname" =~ ^[a-z]$ ]]; then keyname=$(echo "$keyname" | tr '[:lower:]' '[:upper:]')
                    # Shifted numbers/symbols
                    elif [[ "$keyname" == "1" ]]; then keyname="!"
                    elif [[ "$keyname" == "2" ]]; then keyname="@"
                    elif [[ "$keyname" == "3" ]]; then keyname="#"
                    elif [[ "$keyname" == "4" ]]; then keyname="$"
                    elif [[ "$keyname" == "5" ]]; then keyname="%"
                    elif [[ "$keyname" == "6" ]]; then keyname="^"
                    elif [[ "$keyname" == "7" ]]; then keyname="&"
                    elif [[ "$keyname" == "8" ]]; then keyname="*"
                    elif [[ "$keyname" == "9" ]]; then keyname="("
                    elif [[ "$keyname" == "0" ]]; then keyname=")"
                    elif [[ "$keyname" == "-" ]]; then keyname="_"
                    elif [[ "$keyname" == "=" ]]; then keyname="+"
                    elif [[ "$keyname" == "[" ]]; then keyname="{"
                    elif [[ "$keyname" == "]" ]]; then keyname="}"
                    elif [[ "$keyname" == "\\" ]]; then keyname="|"
                    elif [[ "$keyname" == ";" ]]; then keyname=":"
                    elif [[ "$keyname" == "'" ]]; then keyname="\""
                    elif [[ "$keyname" == "," ]]; then keyname="<"
                    elif [[ "$keyname" == "." ]]; then keyname=">"
                    elif [[ "$keyname" == "/" ]]; then keyname="?"
                    fi
                    shift_active=0
                fi
                echo "Key pressed: $keyname"
                buffer+="$keyname"
            fi
        fi
    fi
done
