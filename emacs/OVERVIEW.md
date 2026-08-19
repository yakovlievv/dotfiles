# Doom Emacs — system overview

Emacs here does exactly one job: drive the `~/org` vault (notes, tutoring, book
tracker). Not a coding setup.

## Layout

| File | Role |
|---|---|
| `init.el` | Doom module list. Sets `+literate-config-file` → `~/org/roam/config/doom-config.org`. |
| `doom-config.org` | **Source of truth** (symlink into the vault). Tangles to `config.el`. |
| `config.el` | Generated artifact. Never edit. |
| `packages.el` | Extra packages. |
| `+book-gallery.el` | Standalone book-tracker module, `load!`ed at the end of config. |
| `.hunspell_personal` | Personal word list, version-controlled. |
| `.env` | `GOOGLE_BOOKS_API_KEY` for ISBN lookup. |
| `snippets/org-mode/` | 6 yasnippets, all clocktable variants. |
| `minimal-server-conf/` | Separate stripped config for a remote server. |
| `*.mp3` | Skyrim pomodoro sounds. |

## Doom modules (`init.el`)

- **completion** company, vertico +icons
- **ui** tabs, doom, doom-dashboard, doom-quit, emoji +unicode, minimap, ligatures, hl-todo, modeline, nav-flash, ophints, popup, vc-gutter +pretty, treemacs, vi-tilde-fringe, window-select, workspaces, zen
- **editor** format +onsave, evil +everywhere, file-templates, snippets, fold, whitespace, word-wrap, parinfer
- **emacs** dired +icons, electric, ibuffer, undo, vc
- **checkers** syntax, spell +hunspell, grammar
- **tools** eval +overlay, lookup, magit, pdf
- **lang** `org` with `+roam +journal +pomodoro +agenda +habits +present +pretty +pandoc +dragndrop`, emacs-lisp, markdown, sh
- **app** calendar · **config** default +bindings +smartparens, **literate**

Extra packages: org-roam, org-ql, org-roam-ql, org-roam-ui, org-appear, org-modern,
org-fragtog, catppuccin-theme, ob-mermaid, savefold, valign, dirvish, guess-language,
exec-path-from-shell.

## Appearance

Catppuccin theme; JetBrainsMono Nerd Font Mono 16 (variable-pitch variant for prose).
Frame geometry 127×36 at (72, 79) applied to both `initial-frame-alist` and
`default-frame-alist` so later frames match. Visual line numbers, globally on.

## Files & navigation

- **Dirvish** overrides dired everywhere; image previews; nerd-icon attributes.
  Quick access: `o` vault, `r` roam, `m` material. Bound to `SPC e`.
- `my/print-frame-size` — echo current frame geometry (for tuning the values above).

## Spell & grammar

- `ispell-personal-dictionary` pinned to `.hunspell_personal` in the Doom dir —
  spell-fu refuses to add words otherwise.
- **Multilingual EN/RU/UK simultaneously.** `+my/spell-fu-multilang-h` on
  `spell-fu-mode-hook` registers `en_US`, `ru`, `uk`; a word is wrong only if *no*
  dictionary knows it. `+my/aspell-dict-available-p` guards each add.
  Gotcha baked in: spell-fu builds word lists with **aspell**, not hunspell, so the
  names are aspell's (`ru`, not `ru_RU`) — a wrong name silently ingests aspell's
  error text as the word list.
- **writegood**: weasel-word and passive-voice checks neutered by advising their
  `-turn-on` helpers with `ignore`; only duplicate-word detection survives.

## Session persistence

- **savefold** (`org` + `outline` backends, cache under `doom-cache-dir/savefold/`),
  enabled at startup. `org-startup-folded` forced to `showeverything` because
  savefold only *adds* folds on restore.
- **Global evil marks** (`A`–`Z`) persisted by pushing `evil-markers-alist` into
  `savehist-additional-variables`.
- `org-clock-persist` = `history`, with `org-clock-persistence-insinuate`.

## Keybindings

**Navigation/editing**
- `j`/`k` — visual lines bare, logical lines with a count (`my/evil-next-line`,
  `my/evil-previous-line`).
- `C-s` — save + return to normal state (`my/save-and-normal`); isearch unbound.
- `C-q` — close window. `C-h`/`C-l` — cycle centaur tabs.
- `J` — join without moving point. `M` — center line. `H`/`L` — first/last non-blank.
- Visual `>`/`<` keep the selection; visual `J`/`K` drag lines and reindent.
- Leader: `x` kill buffer, `bo` kill other buffers, `e` dirvish, `-`/`|` splits,
  `f M` move file + sync links.

**Ported operators**
- Surround on `gs`: `gsa` add, `gsd` delete, `gsr` replace (`gsa` in visual).
- Easymotion moved from `gs` to `s` (so `ss` = leap-style jump). `evil-snipe-mode` is
  removed from `doom-first-input-hook`; snipe's enhanced `f`/`t` stays on.

**Org local leader**: `l v` link preview, `l m` insert material link, `l e` insert
external link, `l w` add vocab word, `l n` "create new lesson".
Org normal: `+`/`-` inc/dec number at point, `g-`/`g+` in visual.
Leader `n b` book gallery, `n j z`/`n j x` sleep / wake feeling.

## Org link tooling

**Live preview** (`org-open-link-in-vsplit`, `SPC m l v`) — toggle; a
`post-command-hook` previews the link under the cursor in a reused right split.
Images/PDFs are fitted to their rendered width (`my/fit-window-to-image`); id: links
inside `org-roam-directory` are deliberately skipped; a
`window-configuration-change-hook` cleans up if you close the split manually.
Helpers: `my/ensure-vsplit-window`, `my/kill-image-buffers`,
`my/preview-file-in-vsplit`, `my/org-link-target-at-point`, `my/org-link-roam-target-p`.

**Insertion**
- `my/org-insert-material-links` — recursive picker over `material/`, TAB marks
  multiple, idle-timer-debounced preview while scrolling, inserts `file:` links.
- `my/org-insert-external-link` — picks by description from
  `~/org/roam/external-links.org`. `my/migrate-external-links-to-central` is the
  one-shot harvester that built that file from `:material:` notes.

**Opening** — `my/org-ret-dwim` on `RET`: image links open in the macOS default app
via `open`, everything else falls through to `+org/dwim-at-point`. Same `open`
behaviour on `RET` inside `image-mode`.

**Link sync** — `my/org-rewrite-link-paths` rewrites `file:` links across all of
`~/org`, handling both absolute and `~/` forms. `my/org-move-path` (`SPC f M`) moves
a file/dir and rewrites in one step, defaulting its source to the dired file at point
or the link under the cursor. `my/org--rename-link-sync` is around-advice on
`dired-rename-file`, so renames in dirvish never leave dangling links.

## Org core

Vault at `~/org/`; archive to `archive/arch_%s`. `org-habit` loaded; mermaid enabled
via `ob-mermaid`. LaTeX preview off at startup, emphasis markers hidden, native src
fontification, inherited tasks shown in agenda, habit graph at column 50 (30 days
back / 10 forward). Custom agenda sorting; scheduled repeats skipped after deadline.

- `my/org-clock-in-when-doing` on `org-after-todo-state-change-hook` — switching to
  `STRT` auto-clocks in.
- `my/org-kill-stray-buffers` — around-advice on `org-clock-in/out/goto/load`,
  `org-resolve-clocks`, `org-agenda`: kills file buffers a command opened in the
  background (unmodified, not displayed), keeping the bufferline clean.

**Tag inheritance**: `index`, `crypt`, `concept`, `atomic` are excluded, so filetags
describing the whole file don't leak onto heading-level roam nodes (and `crypt` never
cascades into encrypting children).

**Task states** — Doom's set plus `NEXT`:
`TODO NEXT PROJ LOOP STRT(s!) WAIT(w@/!) HOLD(h@/!) IDEA | DONE(d!) KILL(k@)`, plus
the checkbox and OKAY/YES/NO sequences. `WAIT`/`HOLD`/`KILL` prompt for a note; notes
go into `:LOGBOOK:`. `org-log-note-clock-out` on — clocking out asks where you
stopped. TODO dependencies and checkbox dependencies enforced.
⚠ This list is a *superset* of Doom's; dropping a keyword makes files using it
invisible to the ripgrep agenda scan below.

**Agenda views** (`SPC o a`): `n` next actions · `s` everything started · `S` stale
STRT (via `my/org-stale-strt-skip`, no clock in `my/org-stale-days` = 14, entries with
no clock at all are never skipped) · `b` bug backlog (`:bug:` tag) · `p` parked.

**Pomodoro** — auto-start breaks; `afplay` as the player so the `.mp3`s decode on
macOS; Skyrim skill-level-up on break start, quest-update on break end, both resolved
from `doom-user-dir`.

## Org UI packages

- **org-modern**: no fake checkboxes, `▶`/`▼` fold stars, tag/date/progress faces
  recoloured from `catppuccin-color`.
- **org-appear**: reveal emphasis, links and sub/superscript markers on cursor entry.

## Org-roam

`~/org/roam/`, dailies in `daily/`, DB autosync on. Capture templates: default note,
daily (body read from `~/org/templates/daily.org` at runtime, so the template is
editable without touching the config), and `+org-roam-book-capture-template` — book
notes with AUTHOR / COVER / RATING / PAGES_READ / TOTAL_PAGES properties, `:book:planned:`
tags and a `* Read log` drawer.

**Agenda-file performance layer** (the interesting part):
- `my/org-agenda-scan-files` — ripgrep over `~/org` for a TODO-keyword heading, a
  `CLOCK:` line, or an active timestamp. ~150 of ~330 files, ~10ms, so it's
  recomputed rather than cached. `my/org-agenda--todo-regexp` derives the keyword
  alternation from `org-todo-keywords`. Falls back to the whole roam dir without rg.
- `my/org-roam-refresh-agenda-files` runs as `:before` advice on `org-agenda` and
  `org-dblock-update`.
- `my/org-fast-scan` — `:around` advice on the same two: binds away `org-mode-hook`,
  `find-file-hook`, VC backends and GC for the duration, so scanned files parse raw.
  Deliberately *not* applied to clock commands, which display the file they land in.
- `my/org-files-with-open-clock` + advice on `org-resolve-clocks` — narrows
  `org-files-list` to files with a dangling `CLOCK: [...]` line (usually zero),
  turning the old 3–4s clock-in stall into nothing.
- Also: `org-agenda-inhibit-startup` t, `org-agenda-dim-blocked-tasks` nil.

## Org-journal

Weekly files in `~/org/roam/daily/` (`week%V-%G-%m-%d.org`), day headings inside.
Both levels are roam nodes.
- `+org-journal-file-header` — fires once per file: ID, `#+title: Week NN`,
  `:journal:weekly:` tags, and a week-scoped clocktable pinned to that ISO week.
- `+org-journal-init-day` on `org-journal-after-entry-create-hook` — fires on every
  entry, but the day heading's ID acts as the "already initialised" marker, so only
  the first entry of a day stamps the ID, tags `:daily:`, inserts a day clocktable
  pinned to the parsed date, and offers the sleep/feeling prompts.
- `+org-journal/set-sleep` (`SPC n j z`) — stores `:SLEEP_TIME:` as an *inactive*
  range `[bed]--[wake]`, so `C-c C-y` computes duration and the agenda stays clean.
- `+org-journal/set-wake-feeling` (`SPC n j x`) — `:WAKE_FEELING:` 1–10.
- Carryover: `TODO` and `STRT` items. Agenda integration on, encryption off.

## Encryption

**org-crypt, per-heading not per-file.** Tag a heading `:crypt:` (`SPC m q`), save →
body becomes a PGP block; `C-c C-r` decrypts, re-encrypting on next save. Headings,
tags and `:PROPERTIES:` stay plaintext on purpose so roam IDs, the `:daily:` tag and
sleep/feeling properties remain visible to `org-roam-db-autosync` and clocktables.
`org-crypt-key` set to this machine's key (no passphrase to encrypt);
`org-crypt-disable-auto-save` prevents plaintext spill.

## Tutoring

**Lessons.** Each student/group file carries a `#+SCHEDULE:` header.
- `my/parse-schedule` — parses `tue,thu 18:15-19:15` (shared time),
  `tue 19:15-20:15, fri 16:00-17:00` (per-day), or a single day.
- `my/create-next-lesson` — finds the highest `* Lesson N`, computes the next slot
  within 14 days, appends the subtree: `** Pre-lesson` (with a deadlined
  `TODO prepare for lesson N` and a `*** Print [0/0]`), `** Lesson`, `** Post-lesson`.
  Refuses on `:inactive:` files.
- `my/last-lesson-end-time` — parses the newest lesson's end (or start) timestamp.
- `my/auto-create-next-lesson-maybe` — rolls files forward once a lesson has ended.
  Runs on a timer 5 min after startup, then hourly (it opens and may *save* files, so
  it's deliberately off the hot path).

**Vocab.** `my/vocab-add-word` — prompts for word + translation, appends a row to the
first `* Vocab` table in the file with today's date stamped in column 4, from anywhere
in the buffer. Bound to `SPC m l w`.

## Book gallery (`+book-gallery.el`)

A `special-mode` buffer (`*yako's library*`, `SPC n b`) rendering org-roam `:book:`
notes as a cover-art grid.

- **Data**: `book-gallery--query-books` reads the roam DB; clock time is parsed
  straight out of the files (`--file-clock-minutes`, `--this-week`, `--today`,
  `--year`, `--file-last-read`, `--file-started`, `--file-link-count`).
- **Header**: weekly goal (`book-gallery-weekly-goal-minutes`, set to 180 in the
  config), reading streak (`--calculate-streak`), and a 12-week contribution heatmap
  (`--render-heatmap`, `book-gallery-heatmap-weeks`).
- **Entries**: cover images downloaded and cached under `--cover-dir`, SVG status
  badges, star ratings, progress bars.
- **ISBN**: `book-gallery-new-from-isbn` / `-fill-from-isbn` hit Google Books
  (`GOOGLE_BOOKS_API_KEY` read from `.env` via `--read-env-var`).
- **Keys (evil normal)**: `j`/`k` navigate (with `--snap-to-title` on
  `post-command-hook`), `RET` open, `o`/`O` open in h/v split, `n` new, `I` new from
  ISBN, `i` fill from ISBN, `D`/`A`/`P` mark done/active/planned, `p` set pages,
  `c` toggle clock, `1`–`5` rate, `/` search, `?` help, `g r` refresh, `q` quit.
  Local leader: `f a|s|t` filter (all/status/tag), `s t|a|r|s` sort.
- Auto-refreshes every `book-gallery-refresh-interval` (300s) via a timer cancelled
  in `kill-buffer-hook`.

## Known rough edges

- `my/auto-create-next-lesson-maybe` guards on `lesson-dashboard--find-lesson-files`,
  which **is not defined anywhere** in this config — so the hourly timer currently
  does nothing.
- The org-mode localleader `l n`, described as "Create new lesson", is actually bound
  to `my/vocab-add-word` (same as `l w`); `my/create-next-lesson` has no binding.
- `org-pomodoro-lengh` is a typo for `org-pomodoro-length`, so the 45-minute setting
  never takes effect (defaults to 25).
- Live tracker of remaining work lives in the *Maintenance List* section at the top of
  `doom-config.org`.
