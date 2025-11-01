# ┌─ Lazy-load Zsh completion
# Only load compinit when Tab is pressed
zmodload -i zsh/complist  # load module silently

autoload -Uz colors
colors 2>/dev/null

# Completion styles
zstyle ':completion:*' menu select
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/compinit"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} ma=0\;33
zstyle ':completion:*' squeeze-slashes true

# Lazy-load compinit
_compinit_lazy() {
    autoload -Uz compinit
    compinit -C
    unfunction _compinit_lazy  # remove after first use
}

# Bind Tab to trigger lazy compinit
zle -N expand-or-complete
autoload -Uz +X bashcompinit && bashcompinit  # if you need bash completion

# Hook to initialize compinit on first completion
zle-line-init() {
    if ! type compinit &>/dev/null; then
        _compinit_lazy
    fi
}
zle -N zle-line-init
