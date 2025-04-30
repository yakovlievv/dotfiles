eval "$(starship init zsh)"

export EDITOR="nvim"
export SUDO_EDITOR="nvim"
export KEYTIMEOUT=20
export TERM="xterm-256color"
export TMUX_COLORS="256color"
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

HISTFILE="$HOME/.history"
HISTFILE=~/.history
HISTSIZE=10000
SAVEHIST=50000

setopt inc_append_history

alias cl="clear"
alias ll="ls -lah"
alias nf="neofetch"
alias ya="yazi" 
alias vim=nvim
alias vi=nvim

bindkey -v

