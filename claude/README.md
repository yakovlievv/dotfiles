# Claude Code setup

Shared across machines. Symlink these two files only, never the whole `~/.claude`
(it holds login state, history and caches).

```sh
mkdir -p ~/.claude
for f in CLAUDE.md settings.json; do
  [ -e ~/.claude/$f ] && [ ! -L ~/.claude/$f ] && mv ~/.claude/$f ~/.claude/$f.bak
  ln -sfn ~/dotfiles/claude/$f ~/.claude/$f
done
```

## Per machine (not in dotfiles)

- `~/.claude/machine.md`: instructions for this machine only, imported by `CLAUDE.md`.
- `~/.config/zsh/.zshrc.local`: machine environment variables. It sits inside
  dotfiles, so add `zsh/.config/zsh/.zshrc.local` to `~/dotfiles/.stignore`
  on every machine (Syncthing does not sync `.stignore` itself).

## Not copied

- claude.ai connectors (including the vault) follow the account.
- Plugins are declared in `settings.json`. Auto-install on a fresh machine is untested.
