eval "$(starship init zsh)"
export EDITOR="nvim"
export SUDO_EDITOR="$EDITOR"

export PATH=$PATH:/usr/local/go/bin

HISTFILE=~/.history
HISTSIZE=10000
SAVEHIST=50000

setopt inc_append_history

# Some useful aliases
alias cl="clear"
alias ll="ls -lah"
alias vim="nvim"
alias vi="nvim" 
alias nf="neofetch"
alias ya="yazi" 


# Set language
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# append completions to fpath
fpath=(${ASDF_DIR}/completions $fpath)
# initialise completions with ZSH's compinit
autoload -Uz compinit && compinit
# Enable True Color support
export TERM="xterm-256color"

# Fix tmux color issues (if needed)
export TMUX_COLORS="256color"


[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
