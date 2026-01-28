#!/usr/bin/env bash
set -euo pipefail
rm -rf "$HOME/bin"
ln -sfnv "dotfiles/bin" "$HOME/bin"
export PATH="$PATH:$HOME/bin"
