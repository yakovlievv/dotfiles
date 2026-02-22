export XINITRC="$XDG_CONFIG_HOME/x11/xinitrc"
export XPROFILE="$XDG_CONFIG_HOME/x11/xprofile"
export XRESOURCES="$XDG_CONFIG_HOME/x11/xresources"
export GTK2_RC_FILES="$XDG_CONFIG_HOME/gtk-2.0/gtkrc-2.0"

# ┌─ Macos-specific settings:
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Hardcoded brew shellenv (Apple Silicon) — avoids spawning brew on every shell open
    export HOMEBREW_PREFIX="/opt/homebrew"
    export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
    export HOMEBREW_REPOSITORY="/opt/homebrew"
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin${PATH+:$PATH}"
    export MANPATH="/opt/homebrew/share/man${MANPATH+:$MANPATH}:"
    export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"
    export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
fi
