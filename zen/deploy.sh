#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Deploy Zen config from dotfiles into the active Zen profile.
#
#   ./deploy.sh          push dotfiles -> profile (default)
#   ./deploy.sh pull     copy the rewritable files profile -> dotfiles
#                        (run after you tweak keybindings/containers in the UI)
#
# Read-only files (user.js, chrome/) are SYMLINKED so they stay live-synced.
# Rewritable files (keybindings, containers, search, zen-themes.json) are
# COPIED, because Zen rewrites them via atomic-rename which would sever a
# symlink. dotfiles is the source of truth; use `pull` to capture UI edits.
# ---------------------------------------------------------------------------
set -euo pipefail

DOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname)" in
  Darwin) ZEN_BASE="$HOME/Library/Application Support/zen" ;;
  Linux)
    # Native packages use ~/.config/zen; some builds use ~/.zen.
    for cand in "$HOME/.zen" "$HOME/.config/zen"; do
      [ -f "$cand/profiles.ini" ] && ZEN_BASE="$cand" && break
    done
    : "${ZEN_BASE:=$HOME/.zen}"
    ;;
  *) echo "Unsupported OS: $(uname)" >&2; exit 1 ;;
esac

INI="$ZEN_BASE/profiles.ini"
[ -f "$INI" ] || { echo "No profiles.ini at $INI — is Zen installed?" >&2; exit 1; }

# Active profile = the [Install...] section's Default= entry.
REL="$(awk '/^\[Install/{i=1;next} i&&/^Default=/{sub(/^Default=/,"");sub(/\r$/,"");print;exit}' "$INI")"
[ -n "$REL" ] || { echo "Could not resolve default profile from $INI" >&2; exit 1; }
PROFILE="$ZEN_BASE/$REL"
[ -d "$PROFILE" ] || { echo "Profile dir not found: $PROFILE" >&2; exit 1; }

echo "profile: $PROFILE"
pgrep -x zen >/dev/null 2>&1 && echo "note: Zen is running — changes apply on next restart."

REWRITABLE=(zen-keyboard-shortcuts.json containers.json search.json.mozlz4 zen-themes.json)

if [ "${1:-push}" = "pull" ]; then
  for f in "${REWRITABLE[@]}"; do
    [ -e "$PROFILE/$f" ] && cp "$PROFILE/$f" "$DOT/$f" && echo "pulled $f"
  done
  cp -R "$PROFILE/chrome/." "$DOT/chrome/" 2>/dev/null && echo "pulled chrome/"
  echo "done (pull). Commit + Syncthing will propagate."
  exit 0
fi

# --- push: symlink read-only, copy rewritable -------------------------------
link() { # src -> dest, backing up a real (non-symlink) dest
  local src="$1" dest="$2"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mv "$dest" "$dest.bak.$(date +%s)" && echo "backed up $dest"
  fi
  ln -sfn "$src" "$dest" && echo "linked $(basename "$dest")"
}

link "$DOT/user.js" "$PROFILE/user.js"
link "$DOT/chrome"  "$PROFILE/chrome"

for f in "${REWRITABLE[@]}"; do
  cp "$DOT/$f" "$PROFILE/$f" && echo "copied $f"
done

echo "done (push). Restart Zen to apply."
