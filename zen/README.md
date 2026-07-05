# zen

Reproducible Zen (Firefox) config, synced via dotfiles + Syncthing.

## What syncs how, and why

| File | Method | Why |
|------|--------|-----|
| `user.js` | **symlink** | Zen only reads it → link stays live. Declarative settings, distilled from `prefs.js`. |
| `chrome/` | **symlink** (dir) | Mods/themes. A symlinked *directory* survives Zen's atomic writes inside it. |
| `zen-keyboard-shortcuts.json` | **copy** | Zen rewrites it via atomic-rename when you edit a shortcut in the UI → would sever a file symlink. |
| `containers.json` | copy | same |
| `search.json.mozlz4` | copy | same (binary) |
| `zen-themes.json` | copy | same (mod list) |
| `prefs.reference.js` | — | Full original `prefs.js` dump. Reference only, never deployed. |

`prefs.js` itself is **never** synced: Zen rewrites it every shutdown, and it's
99% volatile junk (telemetry IDs, sync state, timestamps, machine-specific ABIs
and device names). The genuine settings are hand-picked into `user.js`.

## Deploy

```sh
./deploy.sh          # push dotfiles -> active Zen profile (symlink + copy)
./deploy.sh pull     # capture UI edits: profile -> dotfiles, then commit
```

Works on macOS (`~/Library/Application Support/zen`) and Linux (`~/.zen`);
the active profile is resolved from `profiles.ini` automatically, so the
random per-machine profile id doesn't matter.

Restart Zen after a push.

## Not covered here

Bookmarks, history, passwords, open tabs, and workspaces are runtime state —
they ride **Firefox Sync** (already signed in), not this repo. Do not point
Syncthing at the profile directory: the sqlite databases are locked while Zen
runs and concurrent writes corrupt them.
