#!/usr/bin/env python3
"""External monitor brightness (DDC/CI) for waybar.

Usage: monitor.py [status|toggle]
  status -> waybar JSON (glyph, class on/off, brightness in tooltip)
  toggle -> brightness 0 (`ddcutil setvcp 10 0`), or back to the level it had
            before it was blacked out

The pre-blackout level lives in $XDG_RUNTIME_DIR; if it's missing (fresh login
while the monitor is at 0) it comes back at DEFAULT. After a change the module
is refreshed with SIGRTMIN+10.
"""
import json
import os
import re
import subprocess
import sys

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "waybar-monitor")
DEFAULT = 100
SIGNAL = 10
DDC = ["ddcutil", "--sleep-multiplier", ".5"]

ON = "\U000F00E0"   # md-brightness_7
OFF = "\U000F00DB"  # md-brightness_2


def get():
    out = subprocess.run([*DDC, "getvcp", "10"], capture_output=True, text=True).stdout
    m = re.search(r"current value =\s*(\d+)", out)
    return int(m.group(1)) if m else None


def set_(value):
    subprocess.run([*DDC, "setvcp", "10", str(value)], capture_output=True)


def saved():
    try:
        return int(open(STATE).read())
    except (OSError, ValueError):
        return DEFAULT


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    level = get()

    if action == "status":
        if level is None:
            print(json.dumps({"text": ON, "class": "unknown", "tooltip": "monitor: no DDC/CI"}))
            return
        on = level > 0
        print(json.dumps({
            "text": ON if on else OFF,
            "class": "on" if on else "off",
            "tooltip": f"monitor brightness {level}%" if on else f"monitor off (restores to {saved()}%)",
        }))
        return

    if action != "toggle":
        sys.exit(f"unknown action: {action}")
    if level is None:
        sys.exit("ddcutil: could not read brightness")

    if level > 0:
        with open(STATE, "w") as f:
            f.write(f"{level}\n")
        set_(0)
    else:
        set_(saved())
    subprocess.run(["pkill", f"-RTMIN+{SIGNAL}", "-x", "waybar"])


if __name__ == "__main__":
    main()
