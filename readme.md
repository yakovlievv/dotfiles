# Dotfiles

Personal configuration for macOS and Arch Linux with a single Rust-powered CLI to set everything up.

## Installation

Clone the repo and build the CLI (requires a working Rust toolchain with `cargo`):

```bash
git clone git@github.com ~/dots
cd ~/dots
source ./setup.sh
```

`setup.sh` links `~/bin` to this repository, ensures it is on your `PATH`, and builds the `dots` binary (`cargo build --release`). After sourcing the script, wrappers like `mac` or `arch` are available for backwards compatibility, but the recommended entry point is the `dots` binary itself.

## `dots` CLI

Run `dots --help` for the full flag list. Key operations:

- `dots --bootstrap` – full setup: home layout, packages, shell, Node.js, Rust, tmux plugins.
- `dots --home` – create missing XDG directories and symlink configuration files.
- `dots --install` – install required packages (`brew` on macOS, `pacman` on Arch) and rebuild the `bat` cache.
- `dots --shell` – set the default shell to zsh (overridable via `--shell-path`).
- `dots --node` / `dots --rust` / `dots --tpm` – run individual tooling installers.
- `dots --dry-run ...` – preview actions without making changes.

The CLI auto-detects macOS vs Arch Linux and adapts paths, symlinks, and package commands. Use `--root` to target a different dotfiles checkout.

## Firefox

To set up Firefox (or any Firefox-based browser) follow these steps:

- Open `about:profiles` and create a new profile that uses an XDG-compliant directory (`~/.config/mozilla/firefox`).

### nice flag for bat

```bash
--style="numbers,changes"
```
