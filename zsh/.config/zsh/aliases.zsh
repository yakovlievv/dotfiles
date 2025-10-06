#!/usr/bin/env zsh

# ┌─ Aliases:
# help with bat:
alias -g -- -h='-h 2>&1 | bat --language=help --style=plain'
alias -g -- --help='--help 2>&1 | bat --language=help --style=plain'

alias cl="clear"
alias nf="neofetch"
alias ya="yazi"
alias vi="nvim"

# git
alias gs="git status --short"
alias gl="git log"
alias gd="batdiff"

alias ga="git add"
alias gc="git commit -m"

alias gp="git push"
alias gp="git pull"

alias gcl="git clone"

alias tm='tmux has-session -t default 2>/dev/null || tmux new-session -s default "echo; neofetch; zsh"; tmux attach -t default'
alias yz="yazi-cd"
alias man="batman"
alias ls="ls --color"
