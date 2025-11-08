#!/usr/bin/env bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()   { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠${NC}  $1"; }
error() { echo -e "${RED}✖${NC}  $1" >&2; exit 1; }

log "Installing packages"
sudo pacman -Syu --noconfirm ripgrep fd tmux neovim bat bat-extras wget fzf eza zoxide starship fastfetch less luarocks zsh-syntax-highlighting zsh-autosuggestions kitty zsh lazygit fnm

. $HOME/dotfiles/symlink_arch.sh

log "Building bat cache"
bat cache --build

log "installing node"
fnm install 24

chsh -s /usr/bin/zsh
log "Changed default shell to zsh"

log "Installing tpm"
TPM_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/plugins/tpm"
git clone --depth=1 https://github.com/tmux-plugins/tpm.git "$TPM_PATH"

log "Installing rust"
export RUSTUP_INIT_SKIP_PATH_CHECK="yes"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

log "Bootstrap complete. Reboot your pc"
