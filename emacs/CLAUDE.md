# Doom Emacs config — literate, auto-tangled

**This is a literate config. NEVER edit `config.el` directly.**

`config.el` is a generated artifact. The source of truth is the org file
`doom-config.org`, which tangles to `config.el`. Editing `config.el`
directly will be silently overwritten on the next tangle — which is why
such edits appear to "not take effect" after a reload or `doom sync`.

## Where to make changes

- **Edit:** `doom-config.org` — add/modify code inside the relevant
  `#+begin_src emacs-lisp` block (each block has a prose explanation
  above it; keep that pattern).
- `doom-config.org` here is a **symlink** into the org vault. The real
  file is `~/org/roam/config/doom-config.org` — write to that path
  (the symlink is refused for writes).
- `config.el` (and `~/.config/doom/config.el`, also a symlink to this
  repo) are **outputs only** — leave them alone.

## After editing

The config auto-tangles, then needs to be reloaded. Note that
`doom/reload` does **not** reliably re-run `after!` bodies for
already-loaded packages — a full Emacs restart does. To test a change
immediately without restarting, evaluate the affected block manually
(e.g. `M-:` or eval the `src` block).

## Scope

Emacs here is used for exactly one thing: the `~/org` vault (notes,
tutoring lesson plans, a book tracker). Tailor suggestions to
org-centric workflows, not general programming setup.

## Details

- org-roam-dailies is not activitely used. I use org-journal now
