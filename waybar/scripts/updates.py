#!/usr/bin/env python3
"""Pending Arch updates for waybar: repo (checkupdates) + AUR (yay -Qua).

Prints nothing when the system is up to date, so the module hides itself.
The tooltip lists the packages. Refreshed with SIGRTMIN+9 after an upgrade.
"""
import json
import subprocess

GLYPH = "\U000F03D7"  # md-package_up
TOOLTIP_MAX = 20


def lines(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.TimeoutExpired):
        return []
    return [l for l in out.splitlines() if l.strip()]


repo = lines(["checkupdates"])
aur = lines(["yay", "-Qua"])
total = len(repo) + len(aur)

if total == 0:
    print(json.dumps({"text": "", "class": "none"}))
else:
    pkgs = repo + [f"{l}  (aur)" for l in aur]
    tip = pkgs[:TOOLTIP_MAX]
    if len(pkgs) > TOOLTIP_MAX:
        tip.append(f"… and {len(pkgs) - TOOLTIP_MAX} more")
    print(json.dumps({
        "text": f"{GLYPH} {total}",
        "class": "many" if total >= 50 else "some",
        "tooltip": f"{len(repo)} repo, {len(aur)} aur\n\n" + "\n".join(tip),
    }))
