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

# ┌─ Linux-specific settings:
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "i'm on linux"

# ┌─ Macos-specific settings:
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "i'm on macos"

fi

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

batdiff() {
    git diff --name-only --relative --diff-filter=d -z | xargs -0 bat --diff --style=full
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
export FZF_DEFAULT_OPTS=" \
--color=spinner:#F5E0DC,hl:#F38BA8 \
--color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
--color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
--color=selected-bg:#45475A \
--color=border:#6C7086,label:#CDD6F4"
# ┌─ Set default manpager to bat:
export MANPAGER="sh -c 'sed -u -e \"s/\\x1B\[[0-9;]*m//g; s/.\\x08//g\" | bat -p -lman'"

# ┌─ Aliases:
# alias -g -- -h='-h 2>&1 | bat --language=help --style=plain'
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

# ┌─ Bindings:
bindkey -v
# Swap ^C ^c
bindkey -r '\ec'
bindkey '^F' fzf-cd-widget
bindkey '^Y' autosuggest-accept
bindkey '^E' autosuggest-accept-word

# ┌─ FZF source
# if installed via github
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
# If installed via homebrew
[ -f /opt/homebrew/opt/fzf/shell/key-bindings.zsh ] && source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
[ -f /opt/homebrew/opt/fzf/shell/completion.zsh ] && source /opt/homebrew/opt/fzf/shell/completion.zsh
# If installed via pacman
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
[ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh
