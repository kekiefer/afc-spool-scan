#!/bin/bash

# Set the HID device path (update if needed)
EVENT_DEV="/dev/input/by-id/usb-TMS_HIDKeyBoard_1234567890abcd-event-kbd"
MOONRAKER_HOST="localhost"
MOONRAKER_PORT="7125"
SPOOLMAN_PREFIX="web+spoolman:s-"

# Check if evtest is installed
if ! command -v evtest >/dev/null 2>&1; then
    echo "Error: evtest is not installed or not in PATH."
    exit 1
fi

# Check device exists
if [ ! -e "$EVENT_DEV" ]; then
    echo "Device $EVENT_DEV not found."
    exit 1
fi

post_next_spool_id() {
    local SPOOL_ID="$1"
    curl -X POST "http://${MOONRAKER_HOST}:${MOONRAKER_PORT}/printer/gcode/script" \
        -H "Content-Type: application/json" \
        -d "{\"script\": \"SET_NEXT_SPOOL_ID SPOOL_ID=${SPOOL_ID}\"}"
}

process_line() {
    local line="$1"
    if [[ "$line" == "$SPOOLMAN_PREFIX"* ]]; then
        SPOOL_ID="${line#$SPOOLMAN_PREFIX}"
        post_next_spool_id "${SPOOL_ID}"
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
