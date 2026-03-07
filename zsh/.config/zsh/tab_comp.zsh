# ┌─ Zsh completion
if [[ "$OSTYPE" == "darwin"* ]]; then
    fpath=(/opt/homebrew/share/zsh/site-functions /opt/homebrew/share/zsh-completions $fpath)
elif [[ -d /usr/share/zsh/site-functions ]]; then
    fpath=(/usr/share/zsh/site-functions $fpath)
fi

zmodload -i zsh/complist

zstyle ':completion:*' menu select
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/compinit"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} ma=0\;33
zstyle ':completion:*' squeeze-slashes true

autoload -Uz compinit
compinit -C -d "$ZCOMP_DUMP"
