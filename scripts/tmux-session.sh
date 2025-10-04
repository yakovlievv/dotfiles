#!/usr/bin/env bash

# Directories to look for projects
DIRS=(
    "$HOME"
    "$HOME/neovim/.config"
    "$HOME/uni"
    "$HOME/projects"
)

# Select directory if not passed as argument
if [[ $# -eq 1 ]]; then
    selected="$1"
else
    # Correct fd usage for macOS
    options=$(for dir in "${DIRS[@]}"; do
        fd . "$dir" --type d --max-depth 1
    done | sed "s|$HOME/||" | fzf)

    [[ -n $options ]] || exit 0
    selected="$HOME/$options"
fi

# Safe session name
session_name=$(basename "$selected" | tr . _)

# Create session if needed
if ! tmux has-session -t "$session_name" 2>/dev/null; then
    tmux new-session -ds "$session_name" -c "$selected"
fi

# Switch to the session
tmux switch-client -t "$session_name"
