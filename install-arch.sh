#!/usr/bin/env bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $1"; }
error() { echo -e "${RED}✖${NC}  $1" >&2; exit 1; }

log "Installing packages"
sudo pacman -Syu --noconfirm ripgrep fd tmux neovim bat bat-extras wget fzf eza zoxide starship fastfetch less luarocks zsh-syntax-highlighting zsh-autosuggestions kitty zsh lazygit

chsh -s /usr/bin/zsh
log "Changed default shell to zsh"

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

ln -sfn "$DOTFILES/bin" "$XDG_BIN_HOME"
log "Linked scripts"

log "Building bat cache"
bat cache --build

log "Installing node"
mkdir -p $NVM_DIR
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
. "$NVM_DIR/nvm.sh"
nvm install 24

log "Installing tpm"
TPM_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins/tpm"
git clone --depth=1 https://github.com/tmux-plugins/tpm.git "$TPM_PATH"

log "Installing rust"
export RUSTUP_INIT_SKIP_PATH_CHECK="yes"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

log "Bootstrap complete. Reboot your pc"
