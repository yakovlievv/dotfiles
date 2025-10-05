#!/usr/bin/env zsh

# ┌─ Aliases:
# help with bat:
alias -g -- -h='-h 2>&1 | bat --language=help --style=plain'
alias -g -- --help='--help 2>&1 | bat --language=help --style=plain'

alias cl="clear"
alias nf="neofetch"
alias ya="yazi"
alias vi="nvim"
alias gs="git status"
alias gc="git commit -m"
alias ga="git add"
alias gp="git push"
alias tm='tmux has-session -t default 2>/dev/null || tmux new-session -s default; tmux attach -t default'
alias yz="yazi-cd"
alias gd="batdiff"
alias man="batman"
alias ls="ls --color"
