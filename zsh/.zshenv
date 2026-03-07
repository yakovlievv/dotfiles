export SHELL_SESSIONS_DISABLE=1
export EDITOR="nvim"
export SUDO_EDITOR="nvim"
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_BIN_HOME="$HOME/.local/bin"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DOWNLOAD_DIR="$HOME/down"

export PATH="$XDG_BIN_HOME:$HOME/bin:$XDG_CONFIG_HOME/emacs/bin:$PATH"

# moving other files to correct paths
export HISTDIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d "$HISTDIR" ]] || mkdir -p "$HISTDIR"
export HISTFILE="$HISTDIR/zsh_history"
export LY_LOG="$XDG_STATE_HOME/ly/session.log"
export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
export PRETTIER_CONFIG="$XDG_CONFIG_HOME/.prettierrc"
export LESSHISTFILE="$XDG_CACHE_HOME/less/less_history"
export PYTHON_HISTORY="$XDG_DATA_HOME/python/history"
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"
export PYTHONSTARTUP="$XDG_CONFIG_HOME/python/pythonrc"
export GNUPGHOME="$XDG_DATA_HOME/gnupg"
export CARGO_HOME="$XDG_DATA_HOME/cargo"
export RUSTUP_HOME="$XDG_DATA_HOME/rustup"
export GOPATH="$XDG_DATA_HOME/go"
export GOBIN="$GOPATH/bin"
export GOMODCACHE="$XDG_CACHE_HOME/go/mod"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export NVM_DIR="$XDG_DATA_HOME/nvm"
export GRADLE_USER_HOME="$XDG_DATA_HOME/gradle"
export NUGET_PACKAGES="$XDG_CACHE_HOME/NuGetPackages"
# export _JAVA_OPTIONS=-Djava.util.prefs.userRoot="$XDG_CONFIG_HOME/java"
# export _JAVA_AWT_WM_NONREPARENTING=1
export PARALLEL_HOME="$XDG_CONFIG_HOME/parallel"
export FFMPEG_DATADIR="$XDG_CONFIG_HOME/ffmpeg"
export WINEPREFIX="$XDG_DATA_HOME/wineprefixes/default"
export CLANG_FORMAT_STYLE=file
export CLANG_FORMAT_CONFIG_FILE="$HOME/.config/clang-format"

# bootstrap .zshrc to ~/.config/zsh/.zshrc, any other zsh config files can also reside here
export ZCOMP_DUMP="$XDG_CACHE_HOME/zsh/zcompdump"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# ┌─ Fzf settings:
export FZF_DEFAULT_OPTS=" \
--color=spinner:#F5E0DC,hl:#F38BA8 \
--color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#B4BEFE \
--color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
--color=selected-bg:#45475A \
--color=border:#6C7086,label:#CDD6F4 \
--color=gutter:#181825,bg+:#1e1e2e \
--pointer='❯' --marker='✓' \
--height=40% --layout=reverse"

if command -v fd >/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
fi

# Lazy-load cargo and pnpm: defer PATH additions until first use
_lazy_cargo() {
    unfunction cargo rustc rustup rustfmt clippy 2>/dev/null
    [ -f "$CARGO_HOME/env" ] && source "$CARGO_HOME/env"
    "$0" "$@"
}
for _cmd in cargo rustc rustup rustfmt clippy; do
    function $_cmd { _lazy_cargo "$@" }
done
unset _cmd
