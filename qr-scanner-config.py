#!/usr/bin/env python3
"""Read USB QR scanner settings from a Klipper-style configuration file.

Writes shell variable assignments to stdout for the calling shell script to
evaluate, for example:

    EVENT_DEV=/dev/input/by-id/usb-BF_SCAN_SCAN_KEYBOARD_A-00000-event-kbd
    MOONRAKER_PORT=7125

Every value is quoted with shlex.quote(), so a configuration file cannot inject
shell code into the caller.  That matters here: the Klipper config directory is
served by the web UI, so without quoting, "can write a config file" would become
"can run arbitrary shell as the service user".

The file is parsed exactly the way Klipper parses its own configuration -- a
RawConfigParser with strict=False and ';' and '#' as inline comment prefixes,
matching klippy/configfile.py -- so a file Klipper would accept behaves the same
way here.

Exit status:
    0  settings written (possibly none, if the file does not exist)
    1  the file exists but could not be used
"""

import configparser
import os
import shlex
import sys

SECTION = "qr_scanner"

# Configuration key -> shell variable name.
SETTINGS = {
    "event_dev": "EVENT_DEV",
    "moonraker_scheme": "MOONRAKER_SCHEME",
    "moonraker_host": "MOONRAKER_HOST",
    "moonraker_port": "MOONRAKER_PORT",
    "spoolman_prefix": "SPOOLMAN_PREFIX",
    "moonraker_prefix": "MOONRAKER_PREFIX",
}


def warn(message):
    sys.stderr.write("qr-scanner-config: %s\n" % (message,))


def main(argv):
    if len(argv) != 2:
        warn("usage: %s <config-file>" % (os.path.basename(argv[0]),))
        return 1

    path = argv[1]

    # A missing file is not an error; the defaults in the shell script apply.
    if not os.path.exists(path):
        return 0

    parser = configparser.RawConfigParser(
        strict=False, inline_comment_prefixes=(';', '#'))
    try:
        with open(path, 'r') as handle:
            parser.read_file(handle, source=path)
    except (OSError, configparser.Error) as exc:
        warn("cannot read %s: %s" % (path, exc))
        return 1

    for section in parser.sections():
        if section != SECTION:
            warn("ignoring unrecognised section [%s] in %s" % (section, path))

    if not parser.has_section(SECTION):
        warn("no [%s] section in %s; using defaults" % (SECTION, path))
        return 0

    for key, value in parser.items(SECTION):
        name = SETTINGS.get(key)
        if name is None:
            warn("ignoring unrecognised setting '%s' in %s" % (key, path))
            continue
        sys.stdout.write("%s=%s\n" % (name, shlex.quote(value)))

    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
