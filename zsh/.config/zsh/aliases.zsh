#!/usr/bin/env zsh

# ┌─ Aliases:
# help with bat:
alias -g -- -h='-h 2>&1 | bat --language=help --style=plain'
alias -g -- --help='--help 2>&1 | bat --language=help --style=plain'

# run utilities
alias ff="fastfetch"
alias y="yazi"
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

alias lg="lazygit"
# modern replacements
alias man="batman"

alias ls="eza --icons --group-directories-first"
alias lsmax="eza --icons -lah --git --group-directories-first --total-size"

alias tree="eza --tree --icons --level=3"
# alias treepage="tree --color=always| less -R"

alias cd="z"
alias cdi="zi"

# utilities
alias cl="clear"
alias tm='tmux has-session -t default 2>/dev/null || tmux new-session -s default "echo; fastfetch; zsh"; tmux attach -t default'
