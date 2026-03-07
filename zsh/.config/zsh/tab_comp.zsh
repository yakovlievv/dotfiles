# ┌─ Zsh completion
zmodload -i zsh/complist

zstyle ':completion:*' menu select
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/compinit"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} ma=0\;33
zstyle ':completion:*' squeeze-slashes true

autoload -Uz compinit
compinit -C -d "$ZCOMP_DUMP"
