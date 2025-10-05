eval "$(starship init zsh)"
eval "$(zoxide init zsh)"

# ┌─ History and settings:
SAVEHIST=100000
HISTSIZE=100000
HISTFILE="$XDG_CACHE_HOME/zsh/history"
setopt append_history inc_append_history share_history
export KEYTIMEOUT=20
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh"

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

# ┌─ Bindings:
bindkey -v
bindkey -r '\ec'
bindkey '^F' fzf-cd-widget
bindkey '^Y' autosuggest-accept
bindkey '^E' autosuggest-accept-word
