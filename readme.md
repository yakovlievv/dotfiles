# Dotfiles

Personal configuration for macOS and Arch Linux.

Containes a set of different config files for utilities and well as set of scripts to manage the system, making seting new system up as quick as possible.

## Installation

Clone the repo:

```bash
git clone git@github.com ~/dots
cd ~/dots
```

Source the setup script that will allow you to use advanced scripts for dotfile management.

```bash
source ./setup.sh
```

## Available dotfile management scripts:

- `mac` - will fully bootstrap system for macOS from zero
- `arch` - will fully bootstrap system for arch from zero
- `arch-home` - creates proper home directory structure for arch
- `mac-home` - creates proper home directory structure for mac
- `arch-install` - install the dependencies for arch
- `mac-install` - install the dependencies for mac
- `changeshell` - changes the shell to zsh

## Firefox

To set up firefox (or any other firefox-based browser) follow these steps:

- go to `about:profiles` and create new profile with your name and xdg-complian directory (`~/.config/mozilla/firefox`)

### cool flag for bat

--style="numbers,changes"
