#!/usr/bin/env python3
"""Generate the Super-key layer rules in karabiner.json.

Left Command is "Super". Holding it sends a lazy Right Command, so any
Super+key with no bind below behaves like Command+key (Super+Tab is the real
app switcher, Super+Q quits, ...). Every key in KEYS gets five layers, each
encoded as a modifier combo that apps almost never use, so any app can record
them as shortcuts:

    Super+X         -> ctrl+opt+shift+cmd+X   (hyper, same as the old hyper key)
    Super+Shift+X   -> ctrl+opt+cmd+X
    Super+Alt+X     -> ctrl+shift+cmd+X
    Super+Ctrl+X    -> opt+shift+cmd+X
    Super+Cmd+X     -> ctrl+opt+shift+X       (Cmd = CapsLock held)

BINDS overrides a combo with a Karabiner action (open/toggle an app, run a
shell command). PASSTHROUGH leaves a combo alone so it stays Command+key.
The physical Right Command key is remapped to Left Command so it stays a
normal Command key.

Edit the tables below, then run:  python3 ~/dotfiles/karabiner/gen.py
Karabiner reloads karabiner.json on its own.

Known collisions with macOS defaults (avoid or use on purpose):
    Super+Alt+3/4/5  = ctrl+shift+cmd+3/4/5  screenshot to clipboard
    Super+Ctrl+V     = opt+shift+cmd+V       paste and match style
"""

import json
import os

CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "karabiner.json")
PREFIX = "Super"  # every generated rule's description starts with this

KEYS = (
    list("abcdefghijklmnopqrstuvwxyz")
    + list("1234567890")
    + [
        "hyphen",
        "equal_sign",
        "open_bracket",
        "close_bracket",
        "backslash",
        "semicolon",
        "quote",
        "comma",
        "period",
        "slash",
        "spacebar",
        "return_or_enter",
        "delete_or_backspace",
        "left_arrow",
        "right_arrow",
        "up_arrow",
        "down_arrow",
    ]
)

# layer -> (extra modifiers held with Super, modifiers sent)
LAYERS = {
    "": ([], ["left_control", "left_option", "left_shift", "left_command"]),
    "shift": (["shift"], ["left_control", "left_option", "left_command"]),
    "alt": (["option"], ["left_control", "left_shift", "left_command"]),
    "ctrl": (["control"], ["left_option", "left_shift", "left_command"]),
    "cmd": (["left_command"], ["left_control", "left_option", "left_shift"]),
}


def toggle(bundle_id):
    """Open/focus the app, or hide it (Command+H) if it is already frontmost."""
    return ("toggle", bundle_id)


def shell(command):
    return ("shell", command)


def win(mode):
    """Resize the frontmost window with bin/win ("almost" or "maximize").

    bin/win is built from win.swift:  swiftc -O win.swift -o bin/win
    """
    binary = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "win")
    return shell(f"'{binary}' {mode}")


def vicinae(entrypoint):
    """Launch a Vicinae command by id (list them with `vicinae cmd ls`)."""
    return shell(f"/opt/homebrew/bin/vicinae cmd launch {entrypoint}")


def send(key, *modifiers):
    return ("send", key, list(modifiers))


# (layer, key) -> action. Layers: "", "shift", "alt", "ctrl", "cmd".
BINDS = {
    ("", "b"): toggle("app.zen-browser.zen"),
    ("", "n"): toggle("com.apple.Notes"),
    ("", "y"): toggle("com.apple.findmy"),
    ("", "o"): toggle("com.apple.mobilephone"),
    ("", "r"): toggle("com.apple.reminders"),
    ("", "return_or_enter"): toggle("com.mitchellh.ghostty"),
    ("", "e"): toggle("org.gnu.Emacs"),
    ("", "c"): toggle("com.anthropic.claudefordesktop"),
    ("", "t"): toggle("ru.keepcoder.Telegram"),
    ("", "s"): send("4", "left_command", "left_shift"),  # screenshot a region
    ("shift", "c"): toggle("com.apple.iCal"),
    ("shift", "s"): send(
        "3", "left_command", "left_shift"
    ),  # screenshot the whole screen
    # macOS "Shut down?" dialog (Return confirms, auto shuts down after 60s)
    ("ctrl", "s"): shell(
        "osascript -e 'tell application \"loginwindow\" to «event aevtrsdn»'"
    ),
    # windows: H/L are macOS's native tiling (fn+ctrl+arrow), A/M go through bin/win
    ("", "h"): send("left_arrow", "fn", "left_control"),   # tile left half
    ("", "l"): send("right_arrow", "fn", "left_control"),  # tile right half
    ("", "a"): win("almost"),    # 90% of the screen, centered
    ("", "m"): win("maximize"),  # whole screen
}

# Combos left as Command+key. "tab" and "grave_accent_and_tilde" are not in
# KEYS, so every layer of them passes through (Super+Shift+Tab cycles back).
PASSTHROUGH = {
    ("", "q"),  # quit app
    ("", "w"),  # close window
}


def from_event(layer, key):
    extra, _ = LAYERS[layer]
    return {"key_code": key, "modifiers": {"mandatory": ["right_command"] + extra}}


def manipulators(layer, key):
    action = BINDS.get((layer, key))
    if action is None:
        return [
            {
                "from": from_event(layer, key),
                "to": [{"key_code": key, "modifiers": LAYERS[layer][1]}],
                "type": "basic",
            }
        ]
    if action[0] == "send":
        return [
            {
                "from": from_event(layer, key),
                "to": [{"key_code": action[1], "modifiers": action[2]}],
                "type": "basic",
            }
        ]
    if action[0] == "shell":
        return [
            {
                "from": from_event(layer, key),
                "to": [{"shell_command": action[1]}],
                "type": "basic",
            }
        ]
    if action[0] == "toggle":
        bundle_id = action[1]
        regex = "^" + bundle_id.replace(".", "\\.") + "$"
        return [
            {
                "conditions": [
                    {"bundle_identifiers": [regex], "type": "frontmost_application_if"}
                ],
                "from": from_event(layer, key),
                "to": [{"key_code": "h", "modifiers": ["left_command"]}],
                "type": "basic",
            },
            {
                "from": from_event(layer, key),
                "to": [{"shell_command": f"open -b {bundle_id}"}],
                "type": "basic",
            },
        ]
    raise ValueError(f"unknown action {action!r}")


def rules():
    out = [
        {
            "description": f"{PREFIX} key: Left Command → lazy Right Command (Super), Right Command → Left Command [generated by gen.py]",
            "manipulators": [
                {
                    "from": {
                        "key_code": "left_command",
                        "modifiers": {"optional": ["any"]},
                    },
                    "to": [{"key_code": "right_command", "lazy": True}],
                    "type": "basic",
                },
                {
                    "from": {
                        "key_code": "right_command",
                        "modifiers": {"optional": ["any"]},
                    },
                    "to": [{"key_code": "left_command"}],
                    "type": "basic",
                },
            ],
        }
    ]
    for layer in LAYERS:
        ms = []
        for key in KEYS:
            if (layer, key) not in PASSTHROUGH:
                ms += manipulators(layer, key)
        name = "Super" + (f"+{layer.capitalize()}" if layer else "")
        out.append(
            {
                "description": f"{PREFIX} layer: {name}+key [generated by gen.py]",
                "manipulators": ms,
            }
        )
    return out


def dump(value, indent=0):
    """JSON in Karabiner's own style: objects expanded, scalar lists inline."""
    pad = " " * indent
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = [
            f"{pad}    {json.dumps(k, ensure_ascii=False)}: {dump(v, indent + 4)}"
            for k, v in value.items()
        ]
        return "{\n" + ",\n".join(items) + f"\n{pad}}}"
    if isinstance(value, list):
        if all(not isinstance(v, (dict, list)) for v in value):
            return (
                "[" + ", ".join(json.dumps(v, ensure_ascii=False) for v in value) + "]"
            )
        items = [f"{pad}    {dump(v, indent + 4)}" for v in value]
        return "[\n" + ",\n".join(items) + f"\n{pad}]"
    return json.dumps(value, ensure_ascii=False)


def main():
    with open(CONFIG) as f:
        config = json.load(f)
    profile = next(p for p in config["profiles"] if p.get("selected"))
    existing = profile["complex_modifications"]["rules"]
    kept = [r for r in existing if not r["description"].startswith(PREFIX)]
    profile["complex_modifications"]["rules"] = kept + rules()
    with open(CONFIG, "w") as f:
        f.write(dump(config) + "\n")
    count = sum(len(r["manipulators"]) for r in rules())
    print(f"wrote {count} Super manipulators to {CONFIG}")


if __name__ == "__main__":
    main()
