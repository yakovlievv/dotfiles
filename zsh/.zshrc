eval "$(starship init zsh)"
eval "$(zoxide init zsh)"

# ┌─ Some settings:
export EDITOR="nvim"
export SUDO_EDITOR="nvim"
export KEYTIMEOUT=20
export TERM="xterm-256color"
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export PATH="$HOME/scripts:$PATH"


# ┌─ Functions:
yazi-cd() { # Change directories with yazi
  local temp_file
  temp_file=$(mktemp)

  yazi --cwd-file="$temp_file" "$@"

  if [[ -s "$temp_file" ]]; then
    local new_dir
    new_dir=$(<"$temp_file")
    cd "$new_dir" || echo "Failed to cd into $new_dir"
  fi

  rm -f "$temp_file"
}

# ┌─ History:
HISTFILE=~/.history
HISTSIZE=10000
SAVEHIST=50000
setopt inc_append_history

# ┌─ Plugins:
source ~/.config/zsh/catppuccin_theme.zsh
source ~/.config/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.config/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# ┌─ Fzf settings:
# export FZF_DEFAULT_COMMAND="fd --hidden --strip-cwd-prefix --exclude .git"
# export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND" 
# export FZF_ALT_C_COMMAND="fd --type=d --hidden --strip-cwd-prefix --exclude .git"
# export FZF_DEFAULT_OPTS="\
  # --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
  # --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
  # --color=selected-bg:#45475A \
  # --color=border:#313244,label:#CDD6F4 --height 50% --layout=default --border" 

# ┌─ Set default manpager to bat:
export MANPAGER="sh -c 'sed -u -e \"s/\\x1B\[[0-9;]*m//g; s/.\\x08//g\" | bat -p -lman'"

# ┌─ Aliases:
alias cl="clear"
alias nf="neofetch"
alias ya="yazi"
alias vi="nvim"
alias gs="git status"
alias gc="git commit -m"
alias ga="git add"
alias gp="git push"
alias tm="tmux"
alias yz="yazi-cd"

# ┌─ Bindings:
bindkey -v
# Swap ^C ^c
bindkey -r '\ec'
bindkey '^F' fzf-cd-widget

# ┌─ FZF source
# if installed via github
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# If installed via homebrew
[ -f /opt/homebrew/opt/fzf/shell/key-bindings.zsh ] && source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
[ -f /opt/homebrew/opt/fzf/shell/completion.zsh ] && source /opt/homebrew/opt/fzf/shell/completion.zsh
# If installed via pacman
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
[ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh


