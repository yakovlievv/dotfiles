#!/usr/bin/env bash
set -euo pipefail

export DOTFILES = "$HOME/dots"

if [[ "$OSTYPE" == darwin* ]]; then
    rm -rf "$HOME/Documents/bin"
    ln -sfnv "$DOTFILES/bin" "$HOME/Documents/"
    export PATH="$PATH:$HOME/Documents/bin"

elif [[ "$OSTYPE" == linux-* ]]; then
    rm -rf "$HOME/bin"
    ln -sfnv "$DOTFILES/bin" "$HOME/bin"
    export PATH="$PATH:$HOME/bin"
fi

