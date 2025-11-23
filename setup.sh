#!/usr/bin/env bash
set -euo pipefail

ROOT="${DOTFILES_ROOT:-$HOME/dots}"
BIN_DIR="$ROOT/bin"
TARGET_BIN="$ROOT/dots-cli/target/release/dots"

rm -rf "$HOME/bin"
ln -s "$BIN_DIR" "$HOME/bin"
export PATH="$PATH:$HOME/bin"

if [[ ! -x "$TARGET_BIN" ]]; then
  echo "Building dots CLI..."
  cargo build --release --manifest-path "$ROOT/dots-cli/Cargo.toml"
fi

ln -sfn "$TARGET_BIN" "$BIN_DIR/dots"
