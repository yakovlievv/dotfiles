#!/bin/sh

tmux new-session -d -s default
sleep 0.5
tmux run-shell '~/.tmux/plugins/tmux-resurrect/scripts/restore.sh'
