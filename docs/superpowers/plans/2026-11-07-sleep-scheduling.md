# Sleep Scheduling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The vault plans each night (a repeating default plus a per-night `Sleep` copy), Home Assistant follows it, and the phone/Emacs clock the night in and out through vault-api.

**Architecture:** All org logic is elisp in a new standalone module `emacs/+sleep.el` (dotfiles), loaded after `+endgame-capture.el`, so the Mac Emacs and the homelab's headless `vault-emacs` daemon run the same code. vault-api (`~/vault-MCP` on the homelab) gets three thin routes that call `+sleep-*-json` through `emacsclient`, following `core/day.ts`. HA reads `GET /sleep/next` with a REST sensor and receives `sleep_in`/`sleep_out` webhooks.

**Tech Stack:** Emacs Lisp (Doom, org, ert), TypeScript (vault-MCP, `tsx --test`), Home Assistant YAML, iOS Shortcuts.

**Spec:** vault note "sleep scheduling", `~/org/roam/20261107020124-sleep_scheduling.org` (id `f7671870-2e52-4386-8d78-47ee117e7069`).

## Where things live

- dotfiles repo: `liev@server:~/dotfiles` (git, push from there). Emacs module files: `emacs/+sleep.el` (new), `emacs/+endgame-capture.el`, `emacs/tests/`.
- Literate config (habits, journal, keys): `~/org/roam/config/doom-config.org` (vault; `config.el` is generated, never edit it). Tangles on save.
- vault-MCP repo: `liev@server:~/vault-MCP` (git, GitHub `yakovlievv/vault-MCP`). Tests: `npm test`.
- HA: `liev@server:~/smarthome/homeassistant/{configuration.yaml,automations.yaml}`, restart with `cd ~/smarthome && docker compose restart homeassistant`.
- Elisp tests (homelab): `emacs -Q --batch -L ~/.config/emacs/.local/straight/build-31.1/org -L ~/.config/emacs/.local/straight/build-31.1/org-journal -l ~/dotfiles/emacs/tests/<file>.el -f ert-run-tests-batch-and-exit` (same harness as `tests/endgame-capture-test.el`).

## Global Constraints

- The night of bed-day D (the org day, `org-extend-today-until` 05:00) is identified by D everywhere: the copy's `:NIGHT:` property, `/sleep/*` responses, Emacs functions.
- Default source: heading `* Sleep schedule` with an `:ID:` in the sleep optimization system note; stamp `<2026-11-08 Sun 01:00-09:00 +1d>`; elisp `+sleep-source-id`.
- Occurrence date = the date the times fall on: D+1 when the start time is before 05:00, else D. `:SKIP:` holds occurrence dates.
- A copy: `Sleep` heading, child of the day heading (sibling of `DO list`, never inside it), **no TODO keyword**, properties `:ID:`, `:SLEEP_ID:` (source id), `:NIGHT:` (D), `:AREA: sleep`, `:CALDAV_UID:`; body line = plain active stamp (`<D+1 01:00-09:00>`, or `<D 23:30>--<D+1 09:00>` across midnight).
- Making a copy always adds its occurrence date to the source's `:SKIP:`. Skipped with no copy = no sleep planned = no alarm.
- Server-side elisp: `inhibit-interaction t`, wrapped in `+endgame--saving`, returns JSON with `files` (relative), like `+endgame-plan-habit-json`.
- All sleep CLOCK lines are written by the server routes only. Emacs commands call the API; they never `org-clock-in` on Sleep locally.
- Clock lines are text (`CLOCK: [YYYY-MM-DD Day HH:MM]` / `--[…] =>  H:MM`) in the heading's `:LOGBOOK:`, placed with `org-clock-find-position`.
- `SLEEP_TIME` is never written again. Old days keep theirs.
- Morning log: `MORNING_HEADACHE`, `MORNING_FRESHNESS`, `MORNING_MOOD` (1-10) as properties on last night's Sleep copy; notes as plain body text under it (no `MORNING_NOTES`).
- HA: the vault is the only source; `input_datetime.wake_time` and `input_datetime.bed_time` are overwritten on every sync.
- Docs are part of every task that changes behaviour (README/OVERVIEW/doom-config prose/vault notes).

## Review Focus

1. Clocking in at 00:30 (before 05:00) must hit the *previous* org day's Sleep copy, not create one for the calendar day. Test in Task 3.
2. `/sleep/next` between 05:00 and the planned wake (e.g. 06:00 with wake 09:00) must still return last night, not switch HA to tomorrow before the alarm fires. Test in Task 3.
3. Calling `/sleep/in` twice, or `/sleep/out` with nothing open, must change nothing and say so. Test in Task 3.
4. A copy planned in upcoming whose stamp is on D+1 must move into day D, not D+1, and land outside the DO list. Test in Task 2.
5. Mac Emacs with a session clock running when the phone clocks into sleep: after the next Emacs sleep command or file revert, Emacs must not still think the session clock runs. Test in Task 4.

---

### Task 1: Source heading + `+sleep.el` core (plan a night)

**Files:**
- Create: `emacs/+sleep.el`
- Create: `emacs/tests/sleep-test.el` (harness copied from `tests/endgame-capture-test.el`: load config blocks, `+endgame-capture.el`, then `+sleep.el`, throwaway vault with a sleep system note holding the source heading)
- Modify: `~/org/roam/config/doom-config.org` (after the `(load! "+endgame-capture")` block: prose + `(load! "+sleep")`)
- Modify: `~/org/roam/20261025005104-sleep_optimization_system.org` (add `* Sleep schedule` under Components with `org-id-get-create`, stamp per Global Constraints; done in Emacs or on disk, not via vault-MCP which refuses hand-written IDs)

**Interfaces:**
- Produces:
  - `+sleep-source-id` (defvar, string)
  - `(+sleep-occurrence-date NIGHT &optional start)` → `"YYYY-MM-DD"`; NIGHT `"YYYY-MM-DD"`, START `"HH:MM"` (default: the source's start)
  - `(+sleep-night-of-time TIME)` → NIGHT string for an Emacs time (05:00 rule)
  - `(+sleep-copy NIGHT)` → marker at NIGHT's copy (daily note or upcoming, matched by `:NIGHT:` + `:SLEEP_ID:`) or nil
  - `(+sleep-skipped-p NIGHT)` → non-nil when NIGHT's occurrence date is in the source's `:SKIP:`
  - `(+sleep-plan NIGHT &optional start end)` → marker at the copy. Adds the SKIP date; existing copy + START → retimed in place; no day note → into upcoming
  - `(+sleep-plan-json NIGHT &optional start end)` → JSON `{file, line, id, where: "day"|"upcoming", files}`

- [ ] **Step 1: Write failing tests** in `tests/sleep-test.el`:
  - `sleep-occurrence-after-midnight`: source 01:00-09:00 → `(+sleep-occurrence-date "2031-01-07")` = `"2031-01-08"`; with start `"23:30"` = `"2031-01-07"`.
  - `sleep-night-of-time`: 2031-01-08 00:30 → `"2031-01-07"`; 2031-01-08 06:00 → `"2031-01-08"`.
  - `sleep-plan-into-day`: day 2031-01-07 exists → copy is a level-2 child of the day heading, not under `DO list`, has no TODO keyword, `:NIGHT: 2031-01-07`, stamp `<2031-01-08 Wed 01:00-09:00>`, source `:SKIP:` contains `2031-01-08`.
  - `sleep-plan-into-upcoming`: no day note → copy is a top-level heading in upcoming with the same properties.
  - `sleep-plan-retime`: second `(+sleep-plan "2031-01-07" "23:30" "08:00")` → same copy id, stamp `<2031-01-07 Tue 23:30>--<2031-01-08 Wed 08:00>`, SKIP holds only the original date plus `2031-01-07`.
- [ ] **Step 2: Run** the test command on `sleep-test.el`. Expected: FAIL, `+sleep-plan` void.
- [ ] **Step 3: Implement** the Interfaces above in `emacs/+sleep.el`. Reuse `+repeat-skip-add`, `+endgame--day-marker`, `+endgame--append-to-upcoming`, `+endgame--uid`, `+endgame--find-id`. The day child goes after the day's last child via `org-end-of-subtree`.
- [ ] **Step 4: Run** tests. Expected: all PASS; `endgame-capture-test.el` and `habits-test.el` still PASS.
- [ ] **Step 5: Commit** dotfiles (`emacs/+sleep.el`, `emacs/tests/sleep-test.el`): `emacs: +sleep module, plan a night's Sleep copy`. Vault files are committed by the vault's own baseline.

### Task 2: Day making, staging and the last-night prompt

**Files:**
- Modify: `emacs/+endgame-capture.el` (`+endgame-stage-into-day` ~414, `+endgame-day-ensure` ~571, `+endgame--put-sleep` ~545, `+endgame--put-morning`)
- Modify: `~/org/roam/config/doom-config.org` (`+org-journal-init-day` prompts, `+org-journal/set-sleep` removed, `+org-journal/set-morning-log` retargeted, `SPC j z`/`SPC j x` keys)
- Modify: `emacs/+sleep.el`
- Test: `emacs/tests/sleep-test.el`, `emacs/tests/endgame-capture-test.el:357,368`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `(+sleep-ensure-night NIGHT)` → marker at the copy, or nil when the night is skipped without a copy. Called by day creation for the new day.
  - `(+sleep-night-logged-p NIGHT)` → non-nil when NIGHT's copy has a closed CLOCK line
  - `(+sleep-log-night NIGHT BED WAKE)` → writes a closed CLOCK line `[BED]--[WAKE] =>  H:MM` on NIGHT's copy, making the copy (via `+sleep-plan`) when missing. BED/WAKE as `org-read-date` reads them.
  - `(+sleep-put-morning NIGHT MORNING)` → MORNING is `(HEADACHE FRESHNESS MOOD NOTES)`: three properties, NOTES appended as body text
- Behaviour changes:
  - `+endgame-stage-into-day`: a staged heading with `:SLEEP_ID:` is matched by its `:NIGHT:` (not its stamp date) and goes in as a child of the day, not into the DO list.
  - Day creation (both `+endgame-day-ensure` and the Emacs init hook): after staging, `(+sleep-ensure-night D)`.
  - Emacs day init: asks bed/wake **only when** `(+sleep-night-logged-p (D-1))` is nil ("Log last night?"), then `+sleep-log-night`. Morning questions are asked as now and go to `+sleep-put-morning (D-1)`.
  - `+endgame-day-ensure` SLEEP arg → `+sleep-log-night (D-1)`; MORNING arg → `+sleep-put-morning (D-1)`. The POST /day shape stays the same.
  - `+org-journal/set-sleep` deleted; `SPC j x` calls `+sleep-put-morning` on last night with the same prompts.

- [ ] **Step 1: Write failing tests**:
  - `sleep-staged-copy-moves-by-night`: copy for night 2031-01-07 in upcoming (stamp on 01-08) → `(+endgame-day-ensure "2031-01-07")` moves it into 01-07 as a day child; `(+endgame-day-ensure "2031-01-08")` does not take it.
  - `sleep-day-creation-copies-default`: `(+endgame-day-ensure "2031-01-07")` on a non-skipped night → day has one Sleep child; calling again → still one.
  - `sleep-day-creation-skipped-night`: source SKIP has 2031-01-08 and no copy → day 2031-01-07 has no Sleep child.
  - `sleep-log-night-writes-clock`: `(+sleep-log-night "2031-01-07" "2031-01-07 23:30" "2031-01-08 07:10")` → copy LOGBOOK has `CLOCK: [2031-01-07 Tue 23:30]--[2031-01-08 Wed 07:10] =>  7:40`; `(+sleep-night-logged-p "2031-01-07")` non-nil; no `SLEEP_TIME` anywhere.
  - Update `endgame-capture-test.el:357,368`: POST-/day-style call with sleep `("2031-01-07 23:30" "2031-01-08 07:10")` on day 01-08 → the CLOCK line above on night 01-07's copy; morning `(3 7 6 "ok")` → `MORNING_MOOD` = `"6"` on that copy and `ok` in its body.
- [ ] **Step 2: Run** `sleep-test.el` and `endgame-capture-test.el`. Expected: the new tests FAIL.
- [ ] **Step 3: Implement** the behaviour changes above.
- [ ] **Step 4: Run** all three test files. Expected: PASS.
- [ ] **Step 5: Commit** dotfiles: `emacs: days get their Sleep copy; last-night prompt and morning log on Sleep`.

### Task 3: Server elisp — clock in/out and the next night

**Files:**
- Modify: `emacs/+sleep.el`
- Test: `emacs/tests/sleep-test.el`

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces (all take an optional NOW, an Emacs time, for tests):
  - `(+sleep-clock-in-json &optional now)` → `{"state": "in"|"already", "night", "id", "closed": [{"file","heading"}], "files"}`. Night = `(+sleep-night-of-time now)`; ensures the day (no prompts) and the copy (`+sleep-plan` even when skipped: clocking in means sleeping); closes every open CLOCK line in the vault at NOW first (rg `^\s*CLOCK: \[[^]]*\]\s*$` over `+endgame-vault-dir`, archives excluded); `already` when the copy itself has the open clock.
  - `(+sleep-clock-out-json &optional now)` → `{"state": "out"|"none", "night", "id", "minutes", "files"}`; closes the open clock on the most recent copy that has one.
  - `(+sleep-next-json &optional now)` → `{"night", "bed", "wake"}` with local `"YYYY-MM-DD HH:MM"` or `bed`/`wake` null. Rule: for N in (night(now)-1, night(now)): plan(N) = the copy's stamp, else the source projected unless skipped. Return N = night(now)-1 if its wake > now; otherwise night(now) (nulls when skipped without copy).

- [ ] **Step 1: Write failing tests**:
  - `sleep-clock-in-after-midnight`: day 2031-01-07 exists, now 2031-01-08 00:30 → `state` `"in"`, `night` `"2031-01-07"`, open `CLOCK: [2031-01-08 Wed 00:30]` on that night's copy.
  - `sleep-clock-in-closes-other-clock`: an open `CLOCK: [2031-01-07 Tue 22:00]` on some task → after clock-in at 23:00 it reads `--[2031-01-07 Tue 23:00] =>  1:00` and is listed in `closed`.
  - `sleep-clock-in-twice`: second call → `"already"`, file unchanged.
  - `sleep-clock-in-makes-day`: no day note for 2031-01-07, now 22:00 → day created, copy has the open clock.
  - `sleep-clock-out`: after clock-in at 00:30, out at 08:45 → `"out"`, `minutes` 495. Out again → `"none"`.
  - `sleep-next-before-wake`: default 01:00-09:00, now 2031-01-08 06:00 → `night` `"2031-01-07"`, `wake` `"2031-01-08 09:00"`.
  - `sleep-next-after-wake`: now 2031-01-08 10:00 → `night` `"2031-01-08"`, `wake` `"2031-01-09 09:00"`.
  - `sleep-next-skipped`: SKIP 2031-01-09, no copy, now 2031-01-08 10:00 → `night` `"2031-01-08"`, `bed`/`wake` null.
  - `sleep-next-moved`: SKIP 2031-01-09 + copy for night 01-08 at `07:00-10:00` → `wake` `"2031-01-09 10:00"`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** all elisp tests. Expected: PASS.
- [ ] **Step 5: Commit** dotfiles: `emacs: sleep clock in/out and next-night JSON for vault-api`.

### Task 4: Emacs commands + area source

**Files:**
- Modify: `emacs/+sleep.el`, `emacs/+endgame-capture.el` (`+endgame-area-sources` ~755)
- Modify: `~/org/roam/config/doom-config.org` (keys), `~/org/roam/20261031030150-areas.org` (Sleep `:SOURCES: prop:SLEEP_ID`; docs line for the new kind)
- Test: `emacs/tests/sleep-test.el`

**Interfaces:**
- Consumes: Task 3 (the routes from Task 5 at runtime).
- Produces:
  - `+sleep-api-url` (defvar, default `"http://server:8788"`); token from `(auth-source-pick-first-password :host "vault-api")`
  - `+sleep/clock-in`, `+sleep/clock-out` (interactive): POST `/sleep/in` / `/sleep/out` with `url-retrieve-synchronously`, message the result, then `(+sleep--resync)`
  - `(+sleep--resync)`: revert unmodified vault buffers whose files changed; if `org-clock-marker`'s line is now closed, drop the in-memory clock (markers to nil, `org-clock-start-time` nil, mode line updated) without writing anything
  - SOURCES kind `prop:KEY` in `+endgame-area-sources`: every heading carrying KEY in journal files → `(FILE . ID)` entries
  - Keys: `SPC j z` → `+sleep/clock-in`, `SPC j Z` → `+sleep/clock-out` (the old `SPC j z` set-sleep is gone)

- [ ] **Step 1: Write failing tests**:
  - `sleep-resync-drops-stale-clock`: clock into a task with `org-clock-in`, then close that CLOCK line on disk (simulating the server), `(+sleep--resync)` → `(org-clocking-p)` nil and the file is not modified by Emacs.
  - `area-sources-prop`: two days with Sleep copies → `(+endgame-area-sources "sleep")` (SOURCES `prop:SLEEP_ID`) returns both `(FILE . ID)`; `+endgame-area-clocked` for that day = the clocked minutes inside the day's range.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** The HTTP call is not unit-tested; it's checked live in Task 7.
- [ ] **Step 4: Run** all elisp tests. Expected: PASS.
- [ ] **Step 5: Commit** dotfiles: `emacs: SPC j z/Z clock sleep through vault-api; prop: area sources`.

### Task 5: vault-api routes

**Files:**
- Create: `src/core/sleep.ts`
- Modify: `src/http/routes.ts` (next to `POST /day`), `src/http/config.ts` (`VAULT_HA_WEBHOOK_URL`), `src/core/journal.ts:40` (`sleep` flag → last night logged), `.env.example`, `README.md` (HTTP API section)
- Test: `test/api.test.ts` (same emacs stub the `/day` tests use)

**Interfaces:**
- Consumes: Task 3 JSON shapes.
- Produces:
  - `sleepIn(vault, writer, emacs, ha?) / sleepOut(...)`: `writer.external` + `emacsJson` like `ensureDay` (commit the files Emacs reports, summary `sleep in <night>` / `sleep out <night>`), then fire-and-forget POST `${VAULT_HA_WEBHOOK_URL}/sleep_in|sleep_out` with `{night}`; a webhook failure is logged, never fails the route
  - `sleepNext(emacs)`: read-only `emacsJson("(+sleep-next-json)")`
  - Routes: `POST /sleep/in`, `POST /sleep/out`, `GET /sleep/next`; same bearer auth as every route
  - `journal.ts`: `sleep` = the day's night-before is logged (`(+sleep-night-logged-p)` semantics: a closed CLOCK on the previous night's copy, or the old `SLEEP_TIME`)

- [ ] **Step 1: Write failing tests**: `POST /sleep/in` calls `(+sleep-clock-in-json)` and returns its JSON; commits only reported files; webhook URL called with `/sleep_in` when set and not called when unset; `POST /sleep/out` likewise; `GET /sleep/next` returns `{night, bed, wake}` and writes nothing; 401 without token.
- [ ] **Step 2: Run** `npm test`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npm run typecheck && npm test`. Expected: PASS.
- [ ] **Step 5: Commit, merge to main, push**; `npm run build && sudo systemctl restart vault-api vault-emacs`; `curl -H "Authorization: Bearer $T" http://127.0.0.1:8788/sleep/next` returns tonight.

### Task 6: CalDAV — the sleep default and its copies

**Files:**
- Modify: `src/caldav/events.ts` (new calendar `SLEEP`: the source heading as a repeating event with its `:SKIP:` as EXDATEs, copies as single events), `src/caldav/apply.ts` (an override of one sleep occurrence → `(+sleep-plan-json NIGHT START END)`; EXDATE → existing `+endgame-skip-json`; a drag of a copy → stamp edit in place, `:NIGHT:` untouched)
- Test: `test/caldav.test.ts`

**Interfaces:**
- Consumes: `+sleep-plan-json` (Task 1).

- [ ] **Step 1: Write failing tests**: the source shows once in the `Sleep` calendar with RRULE daily and EXDATEs from SKIP; an occurrence override at 07:00-10:00 on 2031-01-09 calls `+sleep-plan-json "2031-01-08" "07:00" "10:00"`; deleting one occurrence adds the EXDATE via `+endgame-skip-json`; moving a copy rewrites its stamp only.
- [ ] **Step 2: Run** `npm test`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npm run typecheck && npm test`. Expected: PASS.
- [ ] **Step 5: Commit, merge, push**; restart `vault-caldav`; check that the Sleep calendar appears on the phone.

### Task 7: Home Assistant + iPhone, end to end

**Files:**
- Modify: `~/smarthome/homeassistant/configuration.yaml` (back it up first as `configuration.yaml.bak-20261107-sleep`), `automations.yaml` (back up likewise)

**Interfaces:**
- Consumes: `GET /sleep/next`, webhooks `sleep_in`/`sleep_out` (Task 5).
- Adds:
  - `rest` sensor `sensor.sleep_next`: `http://127.0.0.1:8788/sleep/next`, bearer token from `secrets.yaml`, `scan_interval: 300`, attributes `night`, `bed`, `wake`
  - helpers: `input_datetime.bed_time`, `input_boolean.alarm_on`
  - automation `Sleep sync`: on sensor change → set `wake_time`/`bed_time`, `alarm_on` = wake not null
  - `Sunrise` and `Wake light`: add condition `alarm_on` is on
  - `Evening light`: starts 90 min before `bed_time`, the bedside lamp steps toward 2700 K and low brightness until `bed_time`
  - `Sleep in` (webhook `sleep_in`): bedside lamp off
  - notifications to `notify.proxima`: 21:00 "No alarm tomorrow" when `alarm_on` is off; 12:00 "Sleep clock still open" when the last `sleep_in` webhook has no `sleep_out` after it
  - `VAULT_HA_WEBHOOK_URL=http://127.0.0.1:8123/api/webhook` in `~/.config/vault-mcp/env`
- iPhone (Vlad sets up, steps written into the vault note): Shortcut "Sleep" → POST `/sleep/in` (Get Contents of URL, tailnet URL, bearer header) on the home screen; automation "When charger is disconnected" → Choose from Menu "Are you awake?" → Yes → POST `/sleep/out`.

- [ ] **Step 1:** Back up both files, add the config, `docker compose restart homeassistant`, and check Settings → System → Logs shows no config errors.
- [ ] **Step 2: Live check:** `sensor.sleep_next` shows tonight; `wake_time` matches; drag tonight's Sleep in the calendar → within 5 min `wake_time` follows; skip tomorrow → `alarm_on` off.
- [ ] **Step 3: Live check:** `curl -X POST …/sleep/in` → lamp off and the copy has an open clock; `…/sleep/out` → closed. `SPC j z` / `SPC j Z` from the Mac do the same.
- [ ] **Step 4:** Update the vault notes "home assistant" and "current sleep setup" (helpers, automations, read-only sliders). Commit by the baseline.

### Task 8: Docs and ticket

**Files:**
- Modify: `emacs/OVERVIEW.md` (Org-journal section: drop set-sleep, add +sleep), `doom-config.org` prose for the module, vault notes "journaling system" (day making, morning log on Sleep, switch date 2026-11-07), Daily note in "the system", "sleep scheduling" (Status: built; iPhone setup steps; delete "What gets built"), "sleep optimization system" (Sleep log component → Sleep copies)
- Ticket "wake time logs itself": DONE

- [ ] **Step 1:** Write the doc changes above.
- [ ] **Step 2:** `grep -rn "SLEEP_TIME\|set-sleep" ~/dotfiles/emacs ~/vault-MCP/src` shows only read-only/compat uses.
- [ ] **Step 3:** Commit dotfiles, merge to main, push. Ticket → DONE with `vault_set_todo`.
