# ┌─ Cache eval helper: caches shell init scripts to avoid spawning subprocesses on every shell start
_cache_eval() {
    local name="$1"
    shift
    (( $+commands[$1] )) || return 0
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/${name}.zsh"
    local bin_path="${commands[$1]}"
    if [[ ! -f "$cache" ]] || [[ -n "$bin_path" && "$bin_path" -nt "$cache" ]]; then
        mkdir -p "${cache:h}"
        "$@" >"$cache"
    fi
    source "$cache"
}

_cache_eval starship starship init zsh
_cache_eval zoxide zoxide init zsh
_cache_eval fnm fnm env --use-on-cd --version-file-strategy=recursive --shell zsh

# ┌─ ssh-agent (macOS: handled by keychain — add UseKeychain+AddKeysToAgent to ~/.ssh/config)
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if ! pgrep -u "$USER" ssh-agent >/dev/null; then
        eval "$(ssh-agent -s)"
        ssh-add ~/.ssh/id_ed25519 2>/dev/null
    fi
fi

# ┌─ History
SAVEHIST=100000
HISTSIZE=100000

setopt append_history inc_append_history share_history
setopt hist_ignore_all_dups hist_reduce_blanks hist_ignore_space
setopt hist_verify

# ┌─ some options
export KEYTIMEOUT=20
export HOMEBREW_NO_ENV_HINTS=1

setopt auto_menu menu_complete # autocmp first menu match
# setopt autocd # type a dir to cd
setopt auto_param_slash           # when a dir is completed, add a / instead of a trailing space
setopt no_case_glob no_case_match # make cmp case insensitive
setopt globdots                   # include dotfiles
setopt extended_glob              # match ~ # ^
setopt interactive_comments       # allow comments in shell
unsetopt prompt_sp                # don't autoclean blanklines
stty stop undef                   # disable accidental ctrl s

# ┌─ Macos-specific settings:
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ ! "$PATH" == */opt/homebrew/opt/fzf/bin* ]]; then
        PATH="${PATH:+${PATH}:}/opt/homebrew/opt/fzf/bin"
    fi
    _cache_eval fzf fzf --zsh
    source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    source "$ZDOTDIR/catppuccin_theme.zsh"
    source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    _cache_eval fzf fzf --zsh
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
    source "$ZDOTDIR/catppuccin_theme.zsh"
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

[ -f "$ZDOTDIR/.zshrc.local" ] && source "$ZDOTDIR/.zshrc.local"


# ┌─ Source other files:
source "$ZDOTDIR/tab_comp.zsh"
source "$ZDOTDIR/functions.zsh"
source "$ZDOTDIR/aliases.zsh"

# ┌─ Bindings:
bindkey -v
bindkey -r '\ec'
bindkey '^F' fzf-cd-widget
bindkey '^Y' autosuggest-accept
bindkey '^E' autosuggest-accept-word

# precmd() { echo "" } # Optional blank line after each thing

# Lazy-load pnpm: defer PATH addition until first use
_lazy_pnpm() {
    unfunction pnpm 2>/dev/null
    export PNPM_HOME="$XDG_DATA_HOME/pnpm"
    export PATH="$PNPM_HOME:$PATH"
    pnpm "$@"
}
function pnpm { _lazy_pnpm "$@" }
