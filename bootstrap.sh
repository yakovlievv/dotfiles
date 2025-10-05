#!/usr/bin/env zsh

# make plugins folder
mkdir zsh/.config/zsh/plugins

# clone zsh plugins
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git zsh/.config/zsh/plugins/zsh-autosuggestions
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git zsh/.config/zsh/plugins/zsh-syntax-highlighting

# clone tpm
git clone --depth=1 https://github.com/tmux-plugins/tpm.git ~/.config/tmux/tpm/
