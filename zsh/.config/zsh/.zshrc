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

fi

# ┌─ Fzf settings:
export FZF_DEFAULT_OPTS=" \
    --color=spinner:#F5E0DC,hl:#F38BA8 \
    --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
    --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
    --color=selected-bg:#45475A \
    --color=border:#6C7086,label:#CDD6F4"

# ┌─ Source other files:
source "$ZDOTDIR/functions.zsh"
source "$ZDOTDIR/aliases.zsh"

# ┌─ Plugin loader:
for plugin in $ZDOTDIR/plugins/*(/); do
    plugin_name=$(basename "$plugin")
    [[ -f "$plugin/$plugin_name.zsh" ]] && source "$plugin/$plugin_name.zsh" || echo "Plugin $plugin_name not found"
done

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
