export EDITOR="nvim"
export SUDO_EDITOR="nvim"

export TERM="xterm-256color"
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_BIN_HOME="$HOME/.local/bin"
export XDG_CACHE_HOME="$HOME/.cache"

# bootstrap .zshrc to ~/.config/zsh/.zshrc, any other zsh config files can also reside here
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export PATH="$XDG_BIN_HOME:$PATH"

# ┌─ Macos-specific settings:
if [[ "$OSTYPE" == "darwin"* ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    export PATH="/opt/local/bin:/opt/local/sbin:$PATH"
fi

. "$HOME/.cargo/env"
