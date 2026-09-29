#!/usr/bin/env python3
"""hyprsunset control for waybar.

Usage: sunset.py [status|toggle|warmer|cooler]
  status  -> waybar JSON (bulb glyph, class on/off, temperature in tooltip)
  toggle  -> switch the filter on at the saved temperature, or off (identity)
  warmer / cooler -> step the temperature; turns the filter on if it was off

State (on/off + temperature) lives in $XDG_RUNTIME_DIR so it resets on logout,
just like hyprsunset itself. hyprsunset is started on first use if it isn't
running. After a change the module is refreshed with SIGRTMIN+8.
"""
import json
import os
import subprocess
import sys
import time

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "waybar-sunset")
MIN, MAX, STEP, DEFAULT = 2500, 6500, 250, 4000
SIGNAL = 8

OFF = "\U000F0336"  # md-lightbulb_outline
ON = "\U000F06E8"   # md-lightbulb_on


def load():
    try:
        on, temp = open(STATE).read().split()
        return on == "1", int(temp)
    except (OSError, ValueError):
        return False, DEFAULT


def save(on, temp):
    with open(STATE, "w") as f:
        f.write(f"{int(on)} {temp}\n")


def running():
    return subprocess.run(["pgrep", "-x", "hyprsunset"], capture_output=True).returncode == 0


def apply(on, temp):
    if not running():
        args = ["hyprsunset", "-t", str(temp)] if on else ["hyprsunset", "-i"]
        subprocess.Popen(args, start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    cmd = ["temperature", str(temp)] if on else ["identity"]
    subprocess.run(["hyprctl", "hyprsunset", *cmd], capture_output=True)


def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    on, temp = load()

    if action == "status":
        print(json.dumps({
            "text": ON if on else OFF,
            "class": "on" if on else "off",
            "tooltip": f"night light {temp}K" if on else f"night light off ({temp}K)",
        }))
        return

    if action == "toggle":
        on = not on
    elif action in ("warmer", "cooler"):
        temp += -STEP if action == "warmer" else STEP
        temp = max(MIN, min(MAX, temp))
        on = True
    else:
        sys.exit(f"unknown action: {action}")

    save(on, temp)
    apply(on, temp)
    subprocess.run(["pkill", f"-RTMIN+{SIGNAL}", "-x", "waybar"])


if __name__ == "__main__":
    main()
