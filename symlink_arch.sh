#!/usr/bin/env bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $1"; }
error() { echo -e "${RED}✖${NC}  $1" >&2; exit 1; }

log "Symlinking dotfiles"

DOTFILES="$HOME/Dots"
source "$DOTFILES/zsh/.zshenv"
mkdir -p "$XDG_CONFIG_HOME"

# List of directories to symlink directly
dirs=(fastfetch bat kitty nvim zathura yazi wofi wlogout wget prettier git swaync waybar hypr lazygit)

for dir in "${dirs[@]}"; do
    target="$XDG_CONFIG_HOME/$dir"
    src="$DOTFILES/$dir"

    [ -e "$target" ] && rm -rf "$target"

    ln -sfn "$src" "$target"
    log "Linked $src → $target"
done

ln -sfn "$DOTFILES/starship/starship.toml" "$XDG_CONFIG_HOME/starship.toml"
log "Linked starship"

ln -sfn "$DOTFILES/tmux/.tmux.conf" "$HOME/.tmux.conf"
ln -sfn "$DOTFILES/tmux/.config/tmux" "$XDG_CONFIG_HOME/tmux"
log "Linked tmux"

ln -sfn "$DOTFILES/zsh/.zshenv" "$HOME/.zshenv"
ln -sfn "$DOTFILES/zsh/.config/zsh" "$XDG_CONFIG_HOME/zsh"
log "Linked zsh"
