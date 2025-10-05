#!/usr/bin/env zsh

# ┌─ Functions:
yazi-cd() { # Change directories with yazi
    local temp_file
    temp_file=$(mktemp)

    yazi --cwd-file="$temp_file" "$@"

    if [[ -s "$temp_file" ]]; then
        local new_dir
        new_dir=$(<"$temp_file")
        cd "$new_dir" || echo "Failed to cd into $new_dir"
    fi

    rm -f "$temp_file"
}

batdiff() {
    git diff --name-only --relative --diff-filter=d -z | xargs -0 bat --diff --style=full
}
