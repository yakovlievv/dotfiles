#!/usr/bin/env python3
"""One waybar button for one Hyprland workspace.

Prints waybar JSON whenever the workspace changes:
  empty            -> a dot
  1-3 windows      -> one glyph per window (a dot for an unknown app)
  more than 3      -> the first two glyphs and a "+"
A special workspace prints nothing (hidden) unless it is toggled in.

Usage: workspace.py <name>    e.g. workspace.py 3  |  workspace.py special:ayugram
"""
import json
import os
import re
import select
import socket
import subprocess
import sys

WS = sys.argv[1]
SPECIAL = WS.startswith("special:")

DOT = "\U000F09DE"      # md-circle_medium
MAX_ICONS = 3
OVERFLOW = "+"
UNKNOWN = DOT           # unknown apps look like an empty slot

# window class regex -> glyph; first match wins
ICONS = [
    (r"^zen$|^firefox$", "\U000F0239"),                    # md-firefox
    (r"^com\.mitchellh\.ghostty$|^kitty$|wezterm", "\U000F018D"),  # md-console
    (r"^[Ee]macs", ""),                              # custom-emacs
    (r"^[Cc]ode", "\U000F0A1E"),                           # md-vscode
    (r"^steam$", "\U000F04D3"),                            # md-steam
    (r"^steam_app_", "\U000F0297"),                        # md-gamepad_variant
    (r"ayugram|telegram", "\U000F048A"),                   # md-send
    (r"^obsidian$", ""),                             # custom-obsidian
    (r"^thunar$", "\U000F024B"),                           # md-folder
    (r"zathura", "\U000F0226"),                            # md-file_pdf_box
    (r"^mpv$", "\U000F040C"),                              # md-play_circle
    (r"[Ss]potify", "\U000F04C7"),                         # md-spotify
]
ICONS = [(re.compile(p), g) for p, g in ICONS]

EVENTS = {
    "workspace", "workspacev2", "focusedmon", "focusedmonv2", "activespecial", "activespecialv2",
    "openwindow", "closewindow", "movewindow", "movewindowv2", "windowtitle", "windowtitlev2",
    "createworkspace", "destroyworkspace", "urgent",
}

urgent = False


def hyprctl(cmd):
    out = subprocess.run(["hyprctl", "-j", cmd], capture_output=True, text=True).stdout
    return json.loads(out or "[]")


def glyph(win):
    for pat, g in ICONS:
        if pat.search(win.get("class") or win.get("initialClass") or ""):
            return g
    return UNKNOWN


def emit():
    global urgent
    wins = [c for c in hyprctl("clients") if c["workspace"]["name"] == WS and c.get("mapped", True)]
    mons = hyprctl("monitors")
    if SPECIAL:
        visible = any(m["specialWorkspace"]["name"] == WS for m in mons)
        if not visible:
            print(json.dumps({"text": ""}), flush=True)
            return
        active = True
    else:
        active = any(m["activeWorkspace"]["name"] == WS and m.get("focused") for m in mons)
        visible = any(m["activeWorkspace"]["name"] == WS for m in mons)
    if active:
        urgent = False

    if not wins:
        text = DOT
    elif len(wins) <= MAX_ICONS:
        text = " ".join(glyph(w) for w in wins)
    else:
        text = " ".join(glyph(w) for w in wins[:MAX_ICONS - 1]) + OVERFLOW

    classes = ["empty" if not wins else "occupied"]
    if active:
        classes.append("active")
    elif visible:
        classes.append("visible")
    if urgent:
        classes.append("urgent")

    tooltip = "\n".join(c["title"] for c in wins) or f"workspace {WS}"
    print(json.dumps({"text": text, "class": classes, "tooltip": tooltip}), flush=True)


def main():
    global urgent
    emit()
    path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr",
                        os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket2.sock")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(path)
    my_addrs = set()
    buf = b""
    while True:
        data = sock.recv(4096)
        if not data:
            break
        buf += data
        dirty = False
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            ev, _, payload = line.decode(errors="replace").partition(">>")
            if ev == "urgent":
                # payload is a window address; flag only if the window lives here
                addrs = {c["address"][2:] for c in hyprctl("clients") if c["workspace"]["name"] == WS}
                if payload in addrs:
                    urgent = True
                    dirty = True
            elif ev in EVENTS:
                dirty = True
        # coalesce bursts of events into one refresh
        while dirty and select.select([sock], [], [], 0.03)[0]:
            more = sock.recv(4096)
            if not more:
                break
            buf += more
            buf = buf[buf.rfind(b"\n") + 1:] if b"\n" in buf else buf
        if dirty:
            emit()


if __name__ == "__main__":
    main()
