eval "$(starship init zsh)"
eval "$(zoxide init zsh)"

# ┌─ History
SAVEHIST=100000
HISTSIZE=100000
HISTFILE="$XDG_CACHE_HOME/zsh/history"

# ┌─ zsh tab completion
zmodload zsh/complist
autoload -U compinit && compinit
autoload -U colors && colors
zstyle ':completion:*' menu select
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS} ma=0\;33
zstyle ':completion:*' squeeze-slashes false
# zstyle ':completion:*' special-dirs true 

# ┌─ some options
export KEYTIMEOUT=20
export HOMEBREW_NO_ENV_HINTS=1

setopt append_history inc_append_history share_history
setopt auto_menu menu_complete # autocmp first menu match
setopt autocd # type a dir to cd
setopt auto_param_slash # when a dir is completed, add a / instead of a trailing space
setopt no_case_glob no_case_match # make cmp case insensitive
setopt globdots # include dotfiles
setopt extended_glob # match ~ # ^
setopt interactive_comments # allow comments in shell
unsetopt prompt_sp # don't autoclean blanklines
stty stop undef # disable accidental ctrl s

# ┌─ Macos-specific settings:
if [[ "$OSTYPE" == "darwin"* ]]; then

    # Source fzf
    if [[ ! "$PATH" == */opt/homebrew/opt/fzf/bin* ]]; then
        PATH="${PATH:+${PATH}:}/opt/homebrew/opt/fzf/bin"
    fi
    source <(fzf --zsh)

    # Source zsh-autosuggestions
    source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh

    # Source zsh-syntax-highlighting
    source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

if [[ "$OSTYPE" == "linux"* ]]; then
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    # Source zsh-syntax-highlighting
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

fi
# ┌─ Fzf settings:
export FZF_DEFAULT_OPTS=" \
    --color=spinner:#F5E0DC,hl:#F38BA8 \
    --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
    --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
    --color=selected-bg:#45475A \
    --color=border:#6C7086,label:#CDD6F4"

# ┌─ Source other files:
source "${ZDOTDIR}/catppuccin_theme.zsh"
source "$ZDOTDIR/functions.zsh"
source "$ZDOTDIR/aliases.zsh"

# blank line after each command
# precmd() {
#   echo ""
# }

# ┌─ Bindings:
bindkey -v
bindkey -r '\ec'
bindkey '^F' fzf-cd-widget
bindkey '^Y' autosuggest-accept
bindkey '^E' autosuggest-accept-word

export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
