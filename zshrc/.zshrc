eval "$(starship init zsh)"
eval "$(zoxide init zsh)"

export FZF_DEFAULT_OPTS=" \
  --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
  --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
  --color=selected-bg:#45475A \
  --color=border:#313244,label:#CDD6F4"
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
alias nf="neofetch"
alias ya="yazi" 
alias vim=nvim
alias vi="nvim"

bindkey -v
export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND" 
export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"
export FZF_DEFAULT_OPTS="\
  --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
  --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
  --color=selected-bg:#45475A \
  --color=border:#313244,label:#CDD6F4 --height 50% --layout=default --border" 
export MANPAGER="sh -c 'sed -u -e \"s/\\x1B\[[0-9;]*m//g; s/.\\x08//g\" | bat -p -lman'"
source ~/.config/zsh/catppuccin_mocha-zsh-syntax-highlighting.zsh
source ~/.config/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.config/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
