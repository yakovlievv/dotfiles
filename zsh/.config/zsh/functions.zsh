#!/usr/bin/env zsh

# ┌─ Functions:
function yz() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# Pick the fastfetch logo based on the OS.
function fastfetch() {
	local logo
	if [[ "$OSTYPE" == "darwin"* ]]; then
		logo="$HOME/dotfiles/ascii/mac.txt"
	elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
		logo="$HOME/dotfiles/ascii/arch.txt"
	fi
	if [[ -n "$logo" && -f "$logo" ]]; then
		command fastfetch --logo "$logo" "$@"
	else
		command fastfetch "$@"
	fi
}
