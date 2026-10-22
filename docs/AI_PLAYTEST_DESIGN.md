# AI Playtest Design

Status: revision 7, 2026-10-21. M0, M1, and M2 are implemented and their exit
criteria are met (§8.1–§8.3), re-verified after the F-M2 game fixes. M3 is
proposed in §14, measured against baselines and pending maintainer decisions.
- Revision 2 folds in an adversarial review by three reviewers: a staff
  engineer, an engineering manager, and a 6502 performance specialist.
- Maintainer decisions are in §13.
- This design replaces the approach in the `ai-training`
  (`../moria8-ai-wip`), `../moria8.more_ai_training_wip`, and `ai-playtest`
  (`../moria8-ai-playtest`) worktrees. Those stay in place and are ignored.

The document has two parts:

- **Part I (binding)** specifies M0–M2 only: the infrastructure plus the first
  three goals. Nothing outside Part I is authorized work.
- **Part II (vision, non-binding)** records where this is meant to go
  (deep-game brain, assisted track, full dashboard, class/race matrix, other
  platforms). It exists so that Part I does not paint the project into a
  corner. It is re-planned goal by goal and is not a commitment.

## 1. Goal

The long-term aim is an automated player that plays the real C64 build in VICE
from character creation to character level 40 and a Balrog kill, working as a
playtester along the way:

- It finds crashes, hangs, state and render bugs, and balance problems.
- It turns each finding into a reproducible artifact.
- A dashboard shows progress.

The near-term aim (Part I) is far smaller. The test system defines goals
(§7), and a session runs until its goal is reached. The first batch is:

1. `enter_dungeon`: reach DL1.
2. `reach_dl2`: reach DL2.
3. `reach_clvl2`: reach character level 2.

No further goals are added until all three work.

**These goals are bring-up, not progress over prior work.** The old bot
already reached DL2 and clvl 2 in an 11.5 s run (`phase10-seed100-session.json`:
`max_depth_reached` 2, `player_level` 2). It did so by stair-scumming with
privileged map knowledge, on a modified build, under `x64`. What the first
batch proves is different: a fair-play bot on the unmodified shipping build,
driven through a sync layer that does not desync.

## 2. Why the prior attempts failed

| # | Failure | Evidence |
|---|---|---|
| F1 | **The problem was treated as machine learning.** Effort went into PPO, behavior cloning, promotion registries, frozen holdouts, and SHA-pinned policy bundles. | `ai-training`: 82 commits, 12 phases (`docs/AI_PLAN.md`), datasets of about 1,000–1,400 transitions. Best open-play result (seeds 100–109) was total depth 23 and max XP 111 across 10 runs; half died within 1,000 turns. Phase 12 was spent rotating holdout seed blocks. |
| F2 | **Long horizons were never run.** The 30 s runtime-verification rule was applied to evaluations, so nothing ran beyond 1,000 turns. | `AI_PLAN.md` Phase 9: "Each batch uses fresh VICE processes and remains under the 30-second ceiling." |
| F3 | **The I/O layer was brittle.** Addresses were hard-coded, the binary-monitor opcodes were wrong, and the newest attempt parses text-monitor dumps. | `memory_map.py:15` `ZP_PLAYER_X = 0x2B`. `vice_bridge.py:33-36` labels `0x82`/`0x83` as snapshot save/load (they are *banks available* / *registers available*; dump/undump are `0x41`/`0x42`) and gives `CMD_MONITOR_COMMAND` the `0xAA` code of `CMD_EXIT`. `ai_playtest_smoke.py` regex-parses `m` output through a `script` pty. |
| F4 | **The UI mode was ambiguous.** A whole phase went to "prompt-safe" transactions. The stack-return-address check covered one site. | `game_interface.py:125-140`. |
| F5 | **Nothing persisted.** Every episode got a fresh VICE and there were no checkpoints, so no failure could be revisited. | `run_playtest.py` launches "a fresh VICE process per episode". (That broken opcodes are *why* snapshots stayed optional is inference.) |
| F6 | **The bot cheated.** Privileged stair coordinates and the full map make balance findings meaningless. | `AI_PLAN.md` Phase 2: "use privileged stair coordinates". |
| F7 | **The dashboard was a pygame window** fed by lossy UDP, with no history. | `scripts/moria_dashboard.py`. |
| F8 | **The success metric was wrong.** Promotion meant beating a scripted baseline on toy scenarios, not progress into the game or bugs found. | Phases 5–12. |

**Throughput was never measured meaningfully.** The often-quoted figure is
1,000 steps in 11.5 s, but it is not a baseline for this design:

- About 900 of the 1,000 steps were stair up/down moves.
- It ran under `x64`, not `x64sc` (`runtime.py`), with true-drive 1541 and no
  REU.
- It used a build carrying AI hooks.
- It made about 20 separate memory reads per step (`game_interface.py`), so it
  was probably bound by socket round trips.

M0 measures throughput from scratch (§9).

## 3. Prior art outside this repo

Hand-written expert systems are the bots that have reached roguelike endgames:

- **APWBorg (Angband Borg)** has won Angband, which descends from Moria. It
  reads the screen and keeps its own model, and it has:
  - per-grid *danger* computed from known monsters;
  - *depth readiness* checklists that gate diving;
  - a fixed priority stack (flee/heal, fight, upkeep, explore/dive);
  - gear scoring;
  - Word of Recall town cycles.
  Wins are rare and came after years of rule tuning.
- **AutoAscend**, a hand-coded NetHack bot, won the NeurIPS 2021 NetHack
  Challenge by a wide margin over neural agents.

This design builds a deterministic, explainable rule-based player and makes
reinforcement learning a non-goal. The learning loop lives in development
(§7.3).

## 4. Principles

1. **The game is the system under test; the bot is a measuring instrument.**
   Every decision records goal, reason, and inputs, so a death can be
   attributed to either the bot or the game.
2. **The product binary is unmodified.** There are no bot hooks and no test
   `#if`s. Observation and synchronization happen from the emulator side.
   The only writes the playtester makes are the RNG seed (§6.3) and, in
   future gym scenarios, explicitly labeled setup pokes. Neither is used to
   obtain information.
3. **Fair play.** The decision-maker sees only what a player could know
   (§6.5). Privileged state goes to the auditor only.
4. **Nothing is hard-coded.** Addresses come from the build's `.vs`. Struct
   offsets come from a checked table (§6.2).
5. **Determinism is a hypothesis until M0 proves it.** The target is that
   (build hash, VICE resource set, seed, bot version) determines a run, and
   that a snapshot plus brain state plus key log replays exactly. Nothing is
   built on this until the M0 replay test passes.
6. **Sessions are unbounded; responses are not.** A session runs until its
   goal is reached. Every monitor command and every resume has deadlines
   (§6.7). Code-change gates stay at 30 s or less.
7. **Build only what the current goal needs.** A component enters Part I only
   when one of the three goals requires it.

# Part I — Binding scope: M0–M2

## 5. Shape, location, dependencies

```
 goal (Python fn) ─► session loop ─► brain v0 ─► one key
                        ▲                         │
          fair-play view│                         ▼
                game model ◄── state reads ── VICE client ──► x64sc (warp, REU)
                        │                         ▲
                 auditor v0 ── findings           │ checkpoints, dump/undump
                        │                         │
                 recorder (JSONL + snapshots + brain state) ─► dashboard v0
```

- **Location.** Top-level `playtest/`, with Python package `moria_playtest`.
  All outputs go under `build/playtest/` (AGENTS rule 6).
- **Packaging.** Run with `PYTHONPATH=playtest`, not `pip install -e`, so that
  no `*.egg-info` lands in the source tree.
- **Dependencies.** Python ≥ 3.11 standard library only through M2: `socket`,
  `select`, `struct`, `json`, `gzip`, `sqlite3` (optional), `http.server`,
  `subprocess`. Any third-party package needs a measured reason and goes
  through a design update.
- **Size signpost.** Runtime playtester code should stay at about 3,500
  lines of Python through M2. Unit tests and the M0 measurement tooling
  (`m0.py`, `fuzz.py`) are not counted.
  - This is a warning, not a hard stop (maintainer decision, §13).
  - Crossing it means pausing to ask whether the code is sprawling the way the
    old 13k-line attempt did, then simplifying or consciously moving on.
- **Make targets** (Part I only):
  - `playtest-check`: static. Unit tests plus the symbol/offset check.
  - `playtest-smoke`: launches VICE, ≤ 30 s.
  - `playtest-session GOAL=<name> [SEEDS=…] [WORKERS=n]`: launches VICE,
    unbounded.
  - `playtest-dashboard`: serves the static page.
  - `playtest-repro FINDING=<id>`: launches VICE (arrives with the M1 recorder;
    M0 proves the replay path it uses).
  - `playtest-m0-report`: launches VICE; the M0 measurement job (§9). Like a
    session, it is an operational job, not a verification gate.
  - `playtest-qualify GOAL=…` and `playtest-regress`: session modes
    (`--qualify [--freeze]`, `--regress`) with their own targets.
  - `playtest-selftest`: launches VICE. It builds the deliberately broken
    variant and requires the auditor to catch and replay it (§8.2).
- **Existing repo tooling.** `platforms/commodore/c128/tests/vice_connector.py`
  speaks the *text* remote monitor. The playtester needs binary-monitor events
  and batched requests, so it gets its own client. Its `parse_vs_symbols` was
  not reused after all: it keeps one address per name, while overlay symbols
  need a multimap (`abi.parse_vs`).

## 6. Components

### 6.1 VICE client and process launch

**Launch.** Every resource is pinned:

```
x64sc -default -config /dev/null +saveres -console +sound -sounddev dummy
      -warp -pal -seed 1 -reu -reusize 512 -drive8type 1541 -drive8truedrive
      -binarymonitor -binarymonitoraddress 127.0.0.1:<port>
      -autostart <worker-private copy of moria8-c64.d64>
```

- Flag spellings were checked against the installed VICE 3.10 in M0.
  `+saveres` is required: without it the GTK build tries to save resources on
  exit and aborts with no display connection.
- `playtest-smoke` asserts the VICE version.
- `stdin` is `/dev/null`, and `stdout`/`stderr` go to a per-worker log file.
  A full pipe stalls VICE.
- **REU is mandatory.** Without it, every overlay switch and tier crossing
  reloads from the 1541. Playtesting the REU-less path is a separate future
  configuration.
- **Each worker gets a private copy of the `.d64`.** The game writes saves,
  and a shared image would corrupt.

**Boot once, then reuse.** Cold boot loads all tiers and overlays into the REU
through a true-drive 1541. After the first boot of a build, the client dumps a
**title-screen snapshot**. Every session and smoke test undumps it, which
keeps `playtest-smoke` inside 30 s.

**Protocol.** Binary monitor, VICE 3.x:

| Op | Code | Use |
|---|---|---|
| memory get / set | `0x01` / `0x02` | State reads. Always use the **RAM bank ID**: `$C000` map, `$E000` overlays, and RAM under ROM. Use the **IO bank** for color RAM `$D800` and the CIAs. Bank IDs are discovered with `0x82`. |
| checkpoint set / delete | `0x12` / `0x13` | `input_get_key` entry, crash traps. Re-armed after every undump or restart. Checkpoint set answers with a `0x11` checkpoint-info packet, not `0x12`. |
| registers get | `0x31` | PC, SP, `$01`. M0 checks whether any register exposes a total cycle count (§6.7). |
| dump / undump | `0x41` / `0x42` | Snapshots, only at input-site stops with an empty keyboard buffer. |
| keyboard feed | `0x72` | Exactly one key per `input_get_key` stop (§6.4). |
| ping, banks/registers available | `0x81`, `0x82`, `0x83` | Health, discovery. |
| exit (resume), quit | `0xaa`, `0xbb` | Lifecycle. |

**Every command stops the CPU** and emits register and stopped events, so a
resume discards every event up to VICE's resumed event; only stops after it
count.

**Requests are pipelined.** A step writes all of its requests in one socket
write and matches responses by request ID:

1. the batched state reads, made as one contiguous read where the layout
   allows;
2. the key feed;
3. the resume.

The target is one effective round trip per step. The map is re-read only when
dlvl, the turn counter, or the visibility state changes.

### 6.2 Symbols and offsets

`playtest/moria_playtest/abi.py` hand-lists the roughly 30–40 names the M0–M2
bot needs. Examples:

- `zp_player_*`, `zp_game_flags`, `zp_rng_0`–`3`;
- `player_data` + `PL_*` offsets;
- `MAP_BASE` and `TILE_*`/`FLAG_*`;
- the monster table and record offsets;
- `current_overlay`;
- `input_get_key`, the `game_new_start` seed site, the crash vectors.

Each entry names its source:

- **Addresses** resolve from the build's `.vs`.
- **`.const` values** (struct offsets, tile codes) are checked by a
  single-line regex against their defining file, for example
  `.const PL_MAX_DLVL = 56` in `core/player.s`.

`make playtest-check` fails when a name disappears or a value no longer
matches. The rule is that a PR changing a listed struct updates this table.
This is the one playtest check proposed for `make test` (§10).

A generator that reads every `.const` from the sources is deferred to Part II
(§12.2). The hand list is smaller and the check catches the same drift.

### 6.3 Seeding

`rng_seed` has three C64 call sites:

- `platforms/commodore/c64/main.s:701` (startup init);
- `platforms/commodore/c64/main.s:979` (`title_load_game`);
- `core/game_loop.s:467` (`game_new_start`, "Re-seed RNG after user input").

It XORs CIA timers, `zp_entropy` (incremented on every input poll,
`platforms/commodore/c64/input.s:314`), and the prior RNG state
(`core/rng.s:23-40`).

Seeding has two writes, both derived from the session seed:

1. **At the title stop**, the RNG is overwritten directly. Chargen (stat
   rolls) runs on this state, before `game_new_start` reseeds, so without
   this write every seed would roll the same character.
2. **After the `jsr rng_seed` in `game_new_start`**, an exec checkpoint
   overwrites `zp_rng_0`–`3` again, then deletes itself. Town and dungeon
   generation run on this state.

Together they erase all timer and input jitter for new games. The load-game
path is not used in Part I.

### 6.4 Synchronization and prompt detection

**One key per `input_get_key` stop.** These routines discard buffered keys:

- `input_get_command` clears `KBDBUF_COUNT` on entry
  (`platforms/commodore/c64/input.s:905-908`);
- `input_modal_prepare` does the same (`input.s:164-166`);
- `input_wait_release` drains it.

So:

- The only checkpoint is `input_get_key` entry. Keys fed at an
  `input_get_command` stop are lost.
- Multi-key commands are sent one key per stop, with the mode re-checked
  between keys.
- VICE delivers fed keys from an alarm after resume, not instantly; M0 tests
  exactly when.

**Blind spots.** Run and auto-rest do not pass through `input_get_key`. They
poll the CIA held-key state (`input_run_key_held`, `input.s:70+`, via
`hal_input_run_cancel_check`, `core/game_loop.s:988`). Fed keys never look
"held", so the harness cannot cancel a run or rest; only the game's own stop
conditions end them. `input_wait_release` is a spin loop with no input site.
Both appear as long resumes, which is why per-resume budgets exist (§6.7).

**Prompt detection.** The return-address approach fails as the only signal:

- **Overlays collide.** The ten overlays share `$E000-$EFFF`. In the current
  `build/c64/main.vs`, 124 of the 1,119 symbols in that window share an
  address with another symbol.
- **Helpers tail-call.** For example `core/input_ui_helpers.s:22,31`,
  `core/ui_store.s:705,719,783`, `core/ui_home.s:151,313`,
  `core/game_loop_helpers.s:188`. The stacked return address then belongs to
  the helper's caller.
- **Text entry looks like a key read.** `hal_input_get_text_char` is the same
  routine as `input_get_key`.

So for M0–M2, the UI mode is decided by:

1. **Screen text and game state first.** The status line and command prompt
   identify `COMMAND`. Known prompt strings (`-more-`, `[y/n]`, chargen
   screens, death screen) identify the rest. Strings are read from screen RAM.
2. **The call stack second.** It is a hint, validated by checking that the
   byte at `ret-2` is `$20` (JSR) and that `current_overlay` matches the
   symbol's overlay segment.

M0–M2 recognize only four modes:

| Mode | Handling |
|---|---|
| `COMMAND` | The brain chooses. |
| `DISMISS` | Covers `-more-` and similar. Send space. |
| `CHARGEN` | Scripted Half-Troll Warrior path. |
| `DEATH` | End the character. |

Anything else is **`UNKNOWN`**: send the game's cancel key (`$03` RUN/STOP;
`$1b` is the secondary, per `hal_input_modal_escape_*` in `input.s`), log an
`unknown_prompt` event with the screen text, and continue. Richer modes
(`ITEM_SELECT`, `DIRECTION`, `STORE`, …) are added when a goal needs them.

Implementation notes from M0:

- **Stages.** Each mode carries a stage: chargen steps; `more`, `anykey`, and
  `info` (the end-of-chargen sheet, also SHIFT+C) for `DISMISS`; and
  `tombstone`, `disk_setup`, and `other` for `DEATH`.
- **The death flow is recognized by screen text.** `GAME_FLAG_OVER` stays set
  through the whole flow, so it is only a fallback.
- **Two prompts are labeled but stay `UNKNOWN`.** Their callers are resident
  code, so the return address identifies them unambiguously:
  - `run_direction`: the second key `input_get_command` reads after `.`;
  - `direction`: `get_direction_target`.

### 6.5 Game model and fair-play view

- **Map.** Read from memory, gated by `FLAG_VISITED`. `TILE_SECRET` renders as
  wall. Remembered-but-not-in-view is distinguished with `FLAG_LIT` and the
  light radius.
- **Monsters and items.** What the player can see comes from the **screen**,
  which is the actual fair-play source. Memory (`MF_VISIBLE`/`MF_DETECTED`,
  the monster table) is used only to identify a glyph's creature type once it
  is visible.
- **Screen and view must agree.** A disagreement between screen and
  memory-derived view is an auditor event. It catches both bot bugs and render
  bugs, cheaply.
- **Status.** HP, level, dlvl, XP, food, and light come from `player_data` and
  zero page, and are cross-checked against the status line.

### 6.6 Brain v0

The brain is deterministic. Each decision records (goal, layer, reason, key).
Only what the three goals need is built:

| Layer | Needed by | Content |
|---|---|---|
| Prompt | all | §6.4 mode handling, chargen script |
| Emergency | 2, 3 | If HP < threshold with a visible monster: retreat along the explored path, go back up stairs if standing on them, quaff a known CLW if carried |
| Fight | 3 | Bump-attack a visible monster when a simple danger estimate is acceptable. The estimate is creature level against clvl and HP fraction, from the monster record. |
| Rest | 3 | Rest when HP is not full and no monster is visible |
| Navigate | 1, 2, 3 | A* over known tiles. Town: walk to the down staircase. Dungeon: frontier exploration; open and bash doors; search when the frontier is exhausted; take down stairs when the goal wants depth; seek monsters when the goal wants XP. |
| Anti-stall | 2, 3 | A per-goal budget of steps without progress, then escalate: new frontier, search, take any stairs. Exhausting the budget logs a `stall`. |

The full danger model, readiness checklists, town shopping, and Balrog plan
are Part II (§12.3).

**As built in M2 (brain v1).** The layers run in this order:

1. **Prompt.** Answers `CHARGEN`, `DISMISS`, `DEATH`, `DIRECTION`, and
   `STORE` prompts. In a store it buys rations (`B`, letter, `Y`; never
   haggles) and leaves with `Q`.
2. **Retreat.** Escape by the nearest staircase, avoiding squares next to
   creatures. It fires when HP is below 60% with a creature within two
   squares, or below 80% with any creature in view, or when attacked by
   something not on screen. Stairs that lead deeper than the goal needs are
   not used.
3. **Fight.** Attack an adjacent creature. Never in town, never a Floating
   Eye.
4. **Eat.** When Hungry, Weak, or Faint. After "You have no food." it stops
   trying (that costs no game time, so it would loop) and heads up toward
   town until food is bought or picked up.
5. **Rest.** One turn at a time (`5`), to full HP, only with nothing in view.
6. **Shop.** Once per town visit, walk into the General Store (entrance 1)
   and buy up to five rations, as a player would before going down.
7. **Descend.**
8. **Hunt.** XP goals only, at 80% HP or more. When the target is two squares
   away, wait up to two turns for it to step into contact (first strike).
9. **Explore.** Frontier tiles from the fair-play map. Doors are opened
   (3 tries) or bashed (8 tries), and then blocked. Paths treat a known trap
   as 25 extra steps: they detour around it, and cross it only when it is
   the only way. A known trap is a destination only when nothing else is
   left.
10. **Search.** Walls with unknown space behind them, 6 searches per spot and
   120 per level. Only for depth goals.
11. **Stair-scum.** After 300 steps with no new map or XP, leave by any
    staircase, never deeper than the goal.

Several rules exist only because of game findings F-M2-1 to F-M2-3 (§8.3):
single-turn rests, the 60% retreat threshold, first-strike waiting, and the
unseen-attacker check.

Shopping, the no-food rule, and trap costs were added on 2026-10-21. After
the F-M2 game fixes, `playtest-regress` fell to 19/20 on `reach_dl2`: seed
1011 ran out of food on DL1 and pressed `E` forever. With these rules all
three suites pass 20/20 again (session `20261021-141656`).

### 6.7 Supervisor, timeouts, and restart

- **Per-command timeout: 60 s.** This is the maintainer decision. Any single
  monitor request with no response in 60 s means the emulator is killed.
- **Per-resume budget.** This is the wait from resume to the next
  `input_get_key` stop. The wall-clock ceiling is also 60 s. M0 measures the
  longest legitimate spans (level generation, tier load, run, rest) and
  confirms they are well under it. If any is not, the timeout policy is
  revisited before M1.
- **Deterministic hang detection.** M0 settled the emulated-time source. The
  binary monitor has no total cycle register (only `LIN`/`CYC`). CIA TOD is
  never started by the KERNAL and reads a frozen 1:00:00.0. The jiffy clock at
  `$A0`–`$A2` pauses whenever IRQs are masked. The source is therefore the
  64-bit `MAINCPU` CLK inside a `0x41` dump.
  - The client takes such a dump only when a resume has run longer than the
    1 s poll interval.
  - The first poll records the clock. A later poll raises a `hang` once more
    than 300 emulated seconds pass with no input stop.
  - The longest measured legitimate span is a stair descent: about 3 emulated
    seconds and 0.16 s wall. 300 emulated s is about 10 s wall at the
    measured ~29× warp, so the limit trips well inside the 60 s wall budget.
  - It stays deliberately loose until M2 measures rest-until-recovered from
    low HP, the one span expected to be long.
- **Kill and restart.**
  - Terminate the worker's **own PID** (never `killall`), then kill it.
  - Log `emulator_unresponsive` with the last PC/SP.
  - Restart from the last snapshot, **together with the brain state saved
    beside it**. Brain memory (explored levels, store knowledge) is not in the
    VICE snapshot, so each snapshot ID has a matching `brain.json`.
  - A timeout recurring at the same step becomes a `hang` finding.
- **Ports.** Each worker has a fixed port, retried on bind failure.

### 6.8 Auditor v0 and recorder

**Auditor v0** runs on every stop, against privileged state:

| Class | Check |
|---|---|
| `hang` | §6.7 |
| `crash` | Exec checkpoint on the BRK vector; KERNAL warm-start entry; a CPU JAM reported by VICE |
| `stack` | SP at a `COMMAND` stop differs from the value learned at the first one |
| `state_invariant` | HP ≤ MHP; player on a walkable tile; `FLAG_OCCUPIED` agrees with the monster table at the player's neighbors; dlvl matches the loaded tier |
| `view_mismatch` | §6.5 |
| `unknown_prompt`, `stall` | §6.4, §6.6. These are bot-quality data, shown apart from game bugs. |

Gold/XP accounting, damage-dice bounds, and store-price checks are deferred:
they need specifications first, or they will produce false positives.

**Recorder.** Each session writes to `build/playtest/<session-id>/`:

- `session.json`: goal, seeds, build SHA, VICE resource set, bot version, and
  the outcome per character.
- `events.jsonl`: level changes, deaths, stalls, findings, restarts.
- `<char>/trace.jsonl.gz`: every decision.
- `<char>/snapshots/<id>.vsf.gz` plus `<id>.brain.json`: at every level entry
  and every finding. Rolling retention of 20 per character, plus all finding
  snapshots.
- A disk-usage check warns at a configurable quota.

**Repro.** `make playtest-repro FINDING=<id>`:

1. undumps the finding's snapshot and loads its brain state;
2. replays the key log one key per stop;
3. stops at the failing step with the monitor open.

### 6.9 Dashboard v0

`make playtest-dashboard` serves one static HTML page plus JS from
`http.server` on `127.0.0.1:8064`. The page polls a `status.json` that each
worker rewrites every N steps. It reads files only, so it can never affect a
session.

The page shows:

- the session goal and per-worker status (seed, character number, dlvl, clvl,
  HP, steps, steps/s, restarts);
- the **live C64 screen**, rendered from screen RAM plus color RAM with the
  C64 palette;
- the last 30 decisions with their reasons;
- the event log (deaths, stalls, findings, plateau alerts);
- per-goal qualification progress (§7.2).

The six-view dashboard is Part II (§12.5).

## 7. Goals

### 7.1 Definition

A goal is a `Goal` entry in `playtest/moria_playtest/goals.py`. Each entry
carries:

- a predicate over the observation at a command stop;
- the character spec;
- the step budget;
- the brain targets the goal implies.

```python
"enter_dungeon": Goal("enter_dungeon", "Leave town by the down staircase ...",
                      lambda o: o.dlvl >= 1, step_budget=2_000, target_dlvl=1),
# M2: reach_dl2 (o.dlvl >= 2, 20_000 steps), reach_clvl2 (o.clvl >= 2, 20_000 steps)
```

- The budgets are starting values. `enter_dungeon` takes 12 steps on every
  qualification seed; the M2 budgets are recalibrated during M2.
- A session runs until a character reaches the goal. Characters that die or
  exhaust the step budget are recorded, and the session continues with a new
  character on the next seed. Sessions have no time limit.

### 7.2 When a goal works

- **Qualification.** A goal **works** when **20/20 fixed qualification seeds**
  each reach it with their **first character, within the goal's step
  budget**, on the fair-play view and the unmodified build.
- **Determinism.** The step budget is counted in agent steps, not wall time,
  so the gate is deterministic and can fail.
- **Regression.** Once a goal works, its 20 seeds become its **frozen
  regression suite**. Every later brain change must still pass every frozen
  suite.
- **Plateau alert.** If N consecutive characters (default 10) fail to beat the
  session's best progress, the dashboard raises an alert. It never ends the
  session.

### 7.3 Development loop

1. Run the goal's seeds.
2. Cluster the failures (deaths, stalls, `unknown_prompt`).
3. Make one rule or data change for the largest cluster.
4. Re-run the seeds, then all frozen suites.

There are no holdout rotations, promotion registries, or statistical
tie-breaks.

## 8. Milestones

Each milestone has a measurable exit criterion and an explicit stop rule.

| M | Scope | Exit criterion |
|---|---|---|
| **M0 Foundations** | VICE client and launch (§6.1); symbol/offset table and check (§6.2); seeding (§6.3); one-key sync and four-mode detection (§6.4); supervisor with timeouts and restart (§6.7); snapshot + brain-state + key-log replay; `playtest-smoke` | All items of the measurement checklist (§9) are done and recorded in `build/playtest/m0-report.json`. `playtest-smoke` ≤ 30 s (title undump, chargen, town, all decoders checked). The replay test passes. A 20k-step keystroke fuzz from town either yields zero `UNKNOWN` modes or files each one as an event, and has no unexplained hang. |
| **M1 `enter_dungeon`** | Brain prompt and town-navigation layers; fair-play view; auditor v0; recorder; dashboard v0 | `enter_dungeon` works (§7.2). A deliberately broken test build (one invariant violated) is caught and its finding replays. |
| **M2 `reach_dl2`, `reach_clvl2`** | Dungeon navigation, doors, search, stairs; fight, emergency, rest; anti-stall; plateau alert; frozen suites | Both goals work, and `enter_dungeon` still passes its frozen suite. No `unknown_prompt` in the final qualification runs. **No further goals are added until M2 is met.** |
| **M3 `reach_dl5`, `clvl5`** | The brain rounds in §14.3: any-glyph creatures, food and light logistics, threat memory, avoiding stationary monsters, sealed-area fallback | Both goals work (§7.2); all frozen suites still pass; no `unknown_prompt`. |

**Stop rules** (defaults, tunable by the maintainer):

- **M0 is time-boxed to two working weeks.** If the replay test cannot pass,
  stop and decide: either drop exact replay (keep snapshots + approximate
  logs), or stop the project.
- **M2 gets 15 brain-change cycles (§7.3).** If both goals are not working by
  then, stop and write up what blocked them before continuing.
- **M3 gets 10 brain-change cycles.** Same rule. The size signpost rises to
  about 5,000 lines of runtime code (maintainer decision, §14.6).

### 8.1 M0 result (2026-10-20)

M0 is implemented in `playtest/moria_playtest/` and its exit criterion passes.

- **Report.** `make playtest-m0-report` writes `build/playtest/m0-report.json`.
  It holds all 11 items plus an `m0_exit` evaluation, measured on VICE 3.10
  `x64sc` with REU and true-drive 1541.
- **Gates.** `make playtest-check` takes 0.3 s (ABI table check plus 20 unit
  tests). `make playtest-smoke` takes 12.1 s on a cold build cache and 0.4 s
  from the cached title snapshot.

| Item | Measured |
|---|---|
| 1 Round trips (stopped) | ping 0.009 ms; 3.8 KB read 0.014 ms; 7 reads pipelined 0.034 ms vs 0.072 ms serial; full observation 0.096 ms. While running: ping 0.56 ms. |
| 2 Emulation speed | `x64sc` 28.8 Mcycles/s with the input checkpoint armed (29.3× real time), 31.3 without. `x64` is the same within 1%. A virtual drive gains nothing while idle. |
| 3 Action costs | Move, rest, or run in town: about 134k cycles (136 ms emulated, 6 ms wall). Town→DL1 including the tier-1 load: 3.02M cycles (3.06 s emulated, 112 ms wall). Inventory overlay: 36k cycles. DL1→DL2 was not measured: the privileged BFS found no path on that seed. |
| 4 Boot | Cold boot to title 11.8 s. Spawn plus title undump 0.34 s. |
| 5 Snapshots | Dump 1.1 ms, undump 2.8 ms, 1.31 MB per snapshot (RAM, 512 KB REU, drive, and disk image). The worker's `.d64` and the template are unchanged by undump and play. |
| 6 Cycle counter | None in the register set. `MAINCPU` CLK from a dump is used; it is monotonic. |
| 7 Replay | 238 fuzz keys on fresh processes: **RAM hash 10/10, vsf hash 10/10**. A reseeded copy diverges. The crash the keys ran into **replays 3/3** at the same PC. |
| 8 Spans and contention | 20k fuzz steps: 1 worker 404 steps/s; 4 workers 1,249 steps/s aggregate; 8 workers 1,700 steps/s aggregate (about 285 per worker). The longest stop-to-stop span is 0.16 s wall (a stair descent). Zero spans over 1 s. |
| 9 Prompt coverage | 20k steps cover all four modes and every chargen stage. 40 distinct `UNKNOWN` screens were filed with full samples; most are item selectors, `direction`, and `run_direction`. No unexplained hang. |
| 10 Key feed | One poked key per stop moves once. Two poked keys net one move (the `input_get_command` flush). VICE's `0x72` feed takes effect within one stop. KERNAL buffer limit 10. |
| 11 Isolation | Private disks; PID-only kill leaves the sibling responsive; VICE output goes to `vice.log`. SIGKILL is detected as `ViceError` and the worker restarts from its snapshot. A SIGSTOPped emulator hit the **60.0 s** timeout and was restarted. |

**Finding F-M0-1 (crash, game bug, fixed 2026-10-20).** The fuzz found a
crash on C64 when the player dies with no separate save disk:

- Death leads into Disk Setup, which loops on "Insert a separate Save Disk".
- `Q) Back` then crashed: the CPU executed data at `$BBDB` (inside
  `title_str`) and BRKed into the KERNAL warm start at `$FE66`.
- The fuzz hit it 6 times in 20k steps, and it replays deterministically.

**Root cause.** It is broader than the Back path:

- Commit `0bdd3db` (2026-08-15) moved `core/score_io.s` into the C64 death
  overlay at `$E000`.
- `tramp_game_over_run` still called `hiscore_load` and `hiscore_save` with
  `$01=$36`, so KERNAL ROM executed in place of the overlay code. Every C64
  game over (death or retirement) ran ROM bytes there.
- Whether that crashed or silently skipped the high-score I/O depended on
  machine state.
- Plus/4 calls the same code with RAM banked in; C128 keeps it resident.

**Fix.** It is C64-only:

- Steps 3–6 (score, high-score load, insert, save) now run as one routine,
  `c64_death_score_io`, in the death overlay with `$01=$35`.
- The C64 storage HAL binds `CHKOUT`/`CHROUT` to raw KERNAL ROM, so the
  overlay supplies bank-safe `score_io_chkout`/`score_io_chrout` wrappers over
  `c64_disk_call`. `core/score_io.s` selects them under
  `SCORE_IO_PLATFORM_CHANNEL_OUT`; all other platforms build byte-identical.
- Moving the steps into the overlay also recovers resident space:
  `program_end` goes from `$BFF7` to `$BFD4`.

**Regression test.** `game_over_product_smoke` (`make test64`) drives the
production game-over sequence on a real disk image. It covers no save media
first, then a save disk in drive 9 that must receive `HALL.OF.FAME`. It was
red before the fix and is green after. The seed-1000 fuzz that originally hit
the crash now runs 20k steps with zero findings.

**Size.** At the end of M0 the package was 2,519 lines. Of those, 236 are
tests and 739 are measurement tooling (`m0.py`, `fuzz.py`).

### 8.2 M1 result (2026-10-20)

M1 is implemented and its exit criterion passes.

**New modules:**

| Module | Role |
|---|---|
| `goals.py` | Goal definitions |
| `view.py` | Fair-play view |
| `brain.py` | Brain v0: prompt layer, town navigation, anti-stall |
| `auditor.py` | Auditor v0 |
| `recorder.py` | Recorder |
| `session.py` | Sessions, qualification, freeze, regress, emulator restart |
| `repro.py` | Finding replay |
| `dashboard.py` + `playtest/dashboard/index.html` | Dashboard v0 |
| `selftest.py` | Broken-build self-test |

**Exit criteria:**

- **`enter_dungeon` works.**
  - `make playtest-qualify GOAL=enter_dungeon PLAYTEST_ARGS=--freeze` passes
    **20/20** on seeds 1001–1020: first character, fair-play view, shipping
    build, 12 steps each, zero findings.
  - The frozen suite is `playtest/suites/enter_dungeon.json`, and
    `make playtest-regress` passes it 20/20.
  - The default session (`make playtest-session`) reaches the goal on seed 1.
- **A deliberately broken build is caught and replays.**
  `make playtest-selftest` builds the C64 disk with
  `-define PLAYTEST_FAULT_STACK_LEAK`. That test-only hook at the top of
  `main_loop` leaks one stack byte per pass once the first turn has passed,
  and nothing defines it otherwise. On that build:
  - the auditor files `stack: SP at command prompt $F1, expected $F2`;
  - `make playtest-repro FINDING=…` reproduces it from the level-entry snapshot
    plus the recorded key.
- **The hook changes nothing in shipping builds.** All 126 build outputs
  across C64, C128, Plus/4, Apple IIe, and CX16 are byte-identical with and
  without the hook.
- **Dashboard v0 serves the live state.** `make playtest-dashboard` serves:
  - the goal and qualification status;
  - per-worker state;
  - the live C64 screen in C64 colors (screen RAM plus color RAM);
  - the last 30 decisions with their layer and reason;
  - character results and events.
  It was checked with a headless-browser screenshot.

**Observed behavior and decisions:**

- **`enter_dungeon` barely exercises navigation.** Town generation puts the
  player one step from the down staircase. The goal mostly exercises sync,
  chargen, the auditor, and the recorder. Real navigation arrives with
  `reach_dl2`.
- **Undump resolves sites before classifying.** `Game.undump` now resolves
  the resident return sites before its first observation. Without that, a
  restored stop classified as `UNKNOWN` and the auditor learned its SP
  baseline one step late, which broke the first replay attempt.
- **Snapshots carry the auditor baseline.** The SP baseline is saved beside
  each snapshot.
- **Findings carry a replay recipe.** Each finding records its snapshot, the
  keys since that snapshot, the screen, and the observation.
  - A `game`-class finding ends the character, with outcome `finding`.
  - `bot`-class findings (`unknown_prompt`, `stall`) are logged and play
    continues.
- **Tier-matches-dlvl check deferred.** The tier ranges overlap (tier 3 is
  DL11–25, tier 4 is DL20–100), so this check needs a specification first.

**Size.** The package is now 3,618 lines:

- about 2,520 lines of runtime code, which is what counts against the
  3,500-line signpost (§5);
- 359 lines of tests;
- 739 lines of M0 measurement tooling.

### 8.3 M2 result (2026-10-21)

M2 is implemented and its exit criterion passes.

- **Goals.** `reach_dl2` (20k steps, `target_dlvl=2`) and `reach_clvl2`
  (20k steps, `target_dlvl=1`, `want_xp`) are in `goals.py`.
- **Code.** The fair-play `View` gained creature identity (glyph and level,
  for creatures already on screen), frontier and search-spot computation,
  stairs sets, and path keep-clear. The brain is v1 (§6.6). `DIRECTION` is a
  mode, added because door handling needed it.
- **Qualification.**
  - `reach_dl2`: **20/20** on seeds 1001–1020. Steps range from 30 to 3,349.
  - `reach_clvl2`: **20/20**. Steps range from 203 to 1,264.
  - Both runs were first character, fair-play view, shipping build.
  - Re-running `reach_clvl2` gives identical per-seed results, 20/20.
  - Suites frozen as `playtest/suites/reach_dl2.json` and `reach_clvl2.json`.
- **Re-qualification after the game fixes (2026-10-21).** The F-M2 fixes below
  changed the game, and three more brain rounds followed (no-food loop, known
  traps, town shopping; §6.6). All three goals were re-qualified 20/20 on the
  fixed build and re-frozen (`program_sha256` `069d41a960ea…`):
  - `enter_dungeon`: steps 53 to 65 (shopping first adds about 45).
  - `reach_dl2`: steps 79 to 685.
  - `reach_clvl2`: steps 134 to 1,475.
  - Sessions `20261021-145848`, `-145852`, `-145902`. No `unknown_prompt`.
- **Regression.** `make playtest-regress` passes all three suites (20/20
  each, session `20261021-141656`). The only findings are bot-class
  stair-scum stall notices.
- **Timeouts.** The longest single resume across all M2 play was 0.2 s wall.
  The 60 s budget and the 300-emulated-second hang limit stand.
  - The bot never uses CTRL+R auto-rest. One auto-rest from 8/21 HP ran 785
    game turns, about 104 emulated seconds.
  - A high-level character auto-resting from near zero HP could exceed 300
    emulated seconds. The hang limit must be revisited before any goal uses
    auto-rest.
- **Effort.** 12 brain-change rounds of the 15 the stop rule allows (9 to
  first qualification, 3 after the game fixes). Unit tests: 47. Runtime code:
  2,884 lines, under the 3,500-line signpost.

**Game findings (all three fixed 2026-10-21; see Status below):**

- **F-M2-1: auto-rest ignores hunger and starvation.**
  - `auto_rest_should_stop` (`core/game_loop.s:2223`) stops only on full
    HP/mana, a printed message, or a scene change.
  - Worsening hunger only plays a sound (`turn_maybe_play_hunger_alert`,
    `core/turn.s:50`). Starvation damage prints nothing
    (`turn_tick_hunger`, `core/turn.s:310`).
  - With the compressed food scale (2,000 starting turns; Hungry→Faint in 140
    turns), one CTRL+R from low HP went Full→Faint→dead (seed 1011, old
    brain).
  - Expected (VMS Moria): resting is disturbed when hunger worsens and when
    the player takes damage.
- **F-M2-2: monsters attack twice per turn.**
  - `monster_try_step` (`core/monster_ai.s:799`) attacks when its target is
    the player's square, then exits through `!mts_blocked`, which returns
    carry clear (`:1037`).
  - `monster_move_toward` (`:555`) reads carry clear as "blocked" and tries
    the next direction.
  - An orthogonally adjacent monster therefore attacks twice every turn (the
    diagonal try and the matching horizontal or vertical try both target the
    player). A diagonally adjacent monster attacks and then also moves.
  - Measured: a speed-1, single-attack Kobold applied damage twice inside one
    `monster_ai_tick` from the same monster slot. The calls came from two
    different `monster_move_toward` call sites.
  - This roughly doubles all monster melee damage. The code dates from
    `e65b714` (2026-02-11).
- **F-M2-3: a diagonally adjacent attacker across a wall corner is invisible.**
  - `monster_update_visibility_one` (`core/monster.s`, LOS gate at `:1224`)
    runs `mm_los_clear_to_target` even at distance 1.
  - A monster attacking diagonally through a doorway, with walls on both
    sides, is never marked `MF_VISIBLE` or drawn. Measured: Kobold at (44,22),
    player at (45,23), flags `$01`, repeated "the Kobold hits you" with bare
    floor on screen.
  - Umoria's `los()` returns true for any adjacent square. The rule touches
    `MONSTER_STATE_CONTRACT.md` visibility, so a fix needs that contract's
    rows.

**Status (2026-10-21):**

- F-M2-1 fixed: `turn_rest_disturbed` latch, ledger TRN-007; C64
  `test_main_loop.s` t45-t46 and `test_turn.s` t30-t33.
- F-M2-2 fixed: `monster_try_step` returns carry set after attacking; C64
  `test_monster_ai.s` t57-t58.
- F-M2-3 fixed: any monster within one step is in line of sight, as in VMS
  Moria and Umoria (ledger MON-010). This supersedes the PR #46 expectation in
  `test_effects.s` Test 35; C64 `test_monster.s` t20-t22 and Test 35 cover it.
  The brain keeps its unseen-attacker check as a guard.

**Follow-ups the findings suggest:**

- Automate F-M2-2-style checks as auditor `rules` checks. For example: at
  most (1 or 2 by speed) × attack-slot attacks per monster per tick, measured
  by checkpoints on `monster_attack_player` and `monster_ai_tick`.
- Add an "attacked by something not visible" check for F-M2-3.
- Neither is built yet: both stop the emulator on every monster action, so
  their cost needs measuring first.

## 9. M0 measurement checklist

Every item is measured, not assumed, and recorded in the M0 report.

1. **Round-trip latency.** Ping, 1 B, 100 B, 3.8 KB `memory_get`, and
   pipelined batches; while stopped and while running.
2. **Emulation speed.** Mcycles/s at warp for `x64sc` and `x64`. Compare with
   and without an armed checkpoint, true drive vs virtual device, and REU on.
   Use the same town snapshot each time.
3. **Cost of game actions.** Cycles and wall time for: a plain move, a rest,
   a run, a stair transition at DL1, a tier-crossing load, and each overlay
   switch.
4. **Boot cost.** Cold boot with REU fill; title-snapshot undump time.
5. **Snapshot cost.** Dump/undump time and size with REU. Confirm the
   worker's `.d64` file on disk is not modified by undump or replay.
6. **Cycle counter.** Whether `0x31`/`0x83` expose a total cycle count. If
   not, pick a fallback (§6.7) and verify it.
7. **Replay.** Snapshot + brain state + key log reproduces the identical vsf
   (normalized) and RAM hash 10/10 under `x64sc`. A reseeded copy diverges.
8. **Longest legitimate span.** The longest stop-to-stop span over the 20k
   fuzz, at 1, 4, and 8 concurrent workers. This sets the cycle limit and
   validates the 60 s budget.
9. **Prompt coverage.** Fuzz coverage of the four modes plus `UNKNOWN`,
   including run, rest, and `input_wait_release` spans.
10. **Key feed.** The 10-key KERNAL buffer limit, the `input_modal_prepare` and
    `input_get_command` flushes, and exactly when a fed key becomes visible
    after resume.
11. **Worker isolation.** Private `.d64` copies; PID-only kill; drained output
    logs; a forced kill and restart exercised end to end.

Throughput for planning (steps/s, cycles per game turn) is taken from items
2–3 and 8. No figure from earlier attempts is reused.

## 10. Verification and repo rules

- **`make test` integration.** Only `playtest-check`'s static symbol/offset
  check is proposed for `make test`. That keeps the cost on game PRs to "update
  the table when you change a listed struct". Everything else stays in
  separate `playtest-*` targets and is advisory.
- **30 s gates.** `playtest-check` and `playtest-smoke` are ≤ 30 s gates for
  playtest code changes. Sessions and qualification runs are operational jobs,
  not verification. They run under the 60 s per-response rule (§6.7).
- **AGENTS.md amendment (applied 2026-10-20, maintainer-approved).** Without
  this, future agents would apply rule 8 to sessions and repeat F2. Text:
  - **Add to Non-Negotiable Rule 8:** "Exception: AI playtest *sessions*
    (`make playtest-session`) are long-running operational jobs, not runtime
    verification. They have no overall time limit and run until their goal is
    reached. Every emulator command and resume inside a session has a 60-second
    response timeout, after which the emulator process is killed and
    restarted. `make playtest-check` and `make playtest-smoke` remain ≤ 30 s
    verification gates."
  - **Add to the VICE escalation list:** `make playtest-smoke`,
    `make playtest-session`, and `make playtest-repro`.
- **Findings stay out of the backlog.** Findings stay under `build/playtest/`
  and are reported to the maintainer. They are never written to
  `docs/BACKLOG.md` (AGENTS operational rules), and they are never fixed
  automatically inside playtest work.
- **Nothing generated is committed.** Snapshots, traces, logs, and disk copies
  are never committed.

## 11. Answers to the review's open items

- **`.vs` and overlays.** Overlay symbols are disambiguated by
  `current_overlay` plus the segment each symbol belongs to. M0 confirms the
  `.vs` (or the KickAss memory map) carries enough segment information. If it
  does not, the build emits per-overlay symbol files as a separate, approved
  build change.
- **`x64` vs `x64sc`.** Part I uses `x64sc` throughout. Snapshots are not
  portable between the two.
- **Creature data** lives in `platforms/commodore/c64/creature_data/tier1-4.s`.
  Only the active tier is resident (`core/tier_manager.s`). Part I reads only
  the resident records it needs.

# Part II — Vision (non-binding)

Part II is re-planned each time a goal starts working. Nothing in it is
authorized until it moves into Part I.

## 12. Directions

### 12.1 Tracks

| Track | Death | Purpose |
|---|---|---|
| **ironman** (Part I) | Permanent; the session continues with a new character | Honest results and balance data |
| **assisted** | Rewind to the last level-entry snapshot, with a per-depth-band budget R | Coverage of deep content before the bot can survive it. Results are labeled *assisted (k rewinds)*. |
| **gym** | The scenario ends | Short wizard-mode or poke-based setups, ≤ 30 s, as unit tests for brain subsystems and endgame balance |

**Rewinds must perturb.** The game and the brain are deterministic, so a plain
rewind replays the same death. Each rewind:

- writes a fresh RNG state, derived from (seed, rewind count) and logged;
- on a repeat in the same band, adds a recorded diversion directive (take the
  nearest stairs, spend escapes earlier).

Repeats in the same autopsy cluster count against R.

### 12.2 State ABI generator

This would replace the hand list (§6.2) with a generator that reads `.const`
and `.label` definitions and creature tables into `state_abi.json` keyed by
build SHA. It is adopted only when the hand list grows past about 100 entries.
KickAss `.eval`, `.for`, and macros make full source parsing fragile, so the
generator would cover only simple single-line forms and fail loudly otherwise.

### 12.3 Full brain (Borg-style)

- **Danger model.** Per tile and horizon: expected damage from known monsters'
  speed, attack dice, and spell/breath chance. Read from the resident tier
  records and unit-tested on hand-computed cases.
- **Readiness checklists.** These are data files that a designer can edit.
  A checklist that the game can never satisfy is a balance finding.
- **Other layers.** Town shopping driven by readiness gaps; Word of Recall
  cycles; gear scoring and identification; caster classes.
- **Balrog hunt.** `pick_creature_type` (`core/monster.s:645`) is uniform over
  creatures with `cr_level ≤ dlvl`. Tier 4 has 57 rows, and the Balrog is the
  last at level 100, so each eligible spawn at DL≥100 is the Balrog about 1
  time in 57. Other spawn paths (summons in `core/monster_magic.s`,
  `core/chest_summons.s`, special rooms) need checking. The plan is to
  stair-scum DL100+ with detection until a `B` is known, then run a
  pre-computed fight plan validated in gyms.
- **Goal note.** The `kill_balrog` goal requires clvl 40 *and* the kill. The
  clvl 40 condition is the maintainer's goal. The game itself sets
  `GAME_FLAG_WINNER` on the kill alone (`core/combat.s:1304`).

### 12.4 Later goal ladder

After M2, goals are added one or two at a time, each with qualification seeds,
a step budget, and a frozen suite. A likely order:

1. `reach_dl5`
2. `clvl10`
3. `reach_dl10`
4. `first_recall_cycle`
5. `reach_dl20`
6. `clvl25`
7. `reach_dl40`
8. `reach_dl50`
9. `clvl35`
10. `reach_dl100`
11. `balrog_seen`
12. `kill_balrog`

### 12.5 Full dashboard

Possible later views:

- a milestone ladder;
- a known-map view with a danger heatmap;
- progress curves across bot versions;
- death and stall clusters with autopsies;
- findings with repro commands;
- per-depth balance tables;
- the class/race matrix.

The server technology is chosen when these views are actually built.

### 12.6 Class/race matrix

`race_class_flags` (`core/tables.s:99`) allows 31 race/class combinations:

| Race | Classes |
|---|---|
| Human | Warrior, Mage, Priest, Rogue, Ranger, Paladin |
| Half-Elf | Warrior, Mage, Priest, Rogue, Ranger, Paladin |
| Elf | Warrior, Mage, Priest, Rogue, Ranger |
| Halfling | Warrior, Mage, Rogue |
| Gnome | Warrior, Mage, Priest, Rogue |
| Dwarf | Warrior, Priest |
| Half-Orc | Warrior, Priest, Rogue |
| Half-Troll | Warrior, Priest |

Half-Troll Warrior is first. Each class capability (prayers, spells, missiles,
stealth) is a separate work item, followed by ladder runs for every
combination.

### 12.7 Other platforms

The brain, model, goals, and recorder are intended to be platform-neutral,
because `core/` structures are shared. The map size is a platform layout
constant (`hal_layout_map_cols/rows`): 80×48 on C64 and Plus/4, 198×66 on
C128. The
backend interface is **extracted when platform #2 starts**, not designed in
advance.

| Platform | Likely backend | Known differences |
|---|---|---|
| C128 | VICE binary monitor (`x128`) | VDC 80-col screen; banked reads (load `C128_MEMORY_CONTRACT.md`) |
| Plus/4 | VICE binary monitor (`xplus4`) | TED screen base; its own layout assertions |
| Apple IIe | MAME Lua plugin with a socket | Map in aux RAM (`$0800-$3B0B`); interleaved text pages; ROMs via `A2ROMS` |
| Commander X16 | `x16emu -testbench` | No breakpoints or snapshots; the existing `input_get_key_testbench_resume` sync pattern; map in banks 1–2 |

### 12.8 Capacity (inference)

A win might take hundreds of thousands to a million agent steps. Planning
numbers come only from M0 measurements. Workers start at 4. Scaling to 8, 16,
or more is decided from the M0 item 8 contention measurements.

### 12.9 Non-goals

- Reinforcement learning and behavior cloning. If tuning is ever needed, the
  first step is black-box tuning of numeric thresholds.
- An LLM in the turn loop. Offline summarization of findings is fine.
- Bot hooks in the product binary.

## 13. Maintainer decisions (2026-10-20)

1. **Time limits.** Sessions are unlimited and run until the goal is reached,
   with a 60 s timeout on every emulator response.
   - **1a.** Goals are defined by the test system. The initial batch is
     `enter_dungeon`, `reach_dl2`, and `reach_clvl2`. No more goals until
     these work. The DL-before-clvl order is the author's choice.
   - **1b.** Goals 1–3 are kept even though the old bot reached them by
     cheating; they are bring-up for the honest stack (§1).
2. **Fair play.** The fair-play view is the default. Privileged state goes to
   the auditor only.
3. **Wand of Lightning hack.** Repaired and merged separately (3d8 per VMS
   Moria `wands.inc`; `test_wands_staves.s` Test 8).
4. **First character.** Half-Troll Warrior first. Other classes and races are
   separate items building toward the matrix (§12.6).
5. **Code location.** Top-level `playtest/`; outputs in `build/playtest/`.
6. **Prior worktrees.** Left in place and ignored.
7. **AGENTS.md.** The rule-8 carve-out and escalation-list additions in §10
   are approved and applied to `AGENTS.md`.
8. **Dashboard.** A minimal dashboard ships in M1 (§6.9). The full dashboard
   is Part II.
9. **Qualification.** Qualification has a per-goal step budget so it can fail,
   plus project stop rules (§8).
10. **Size signpost.** About 3,500 lines of runtime code through M2, with
    tests and M0 measurement tooling excluded. It is a warning to pause and
    check for sprawl, not a hard stop (§5).

## 14. M3 proposal (2026-10-21, pending maintainer decisions)

The maintainer decided the scope on 2026-10-21 (§14.6). M3 is now in the
milestone table (§8); this section keeps the evidence and the plan.

### 14.1 Baselines

Both runs use the committed brain v1 with shopping (`ee1795f`) on the fixed
game (`dea5d1a`), seeds 1001–1020, first character, fair-play view. The goals
were registered only for the probe; nothing in the repo changed.

| Probe | Budget | Result | Notes |
|---|---|---|---|
| `reach_dl5` (`target_dlvl=5`) | 50k steps | **16/20**, 4 died | Successes take 234–2,914 steps |
| `clvl10` (`want_xp`, `target_dlvl=5`) | 60k steps | **0/20**, all died | Highest clvl 7; clvl 5+ on 8 seeds |

Sessions: `build/playtest/sessions/m3-baseline-reach_dl5` and
`m3-baseline-clvl10`.

### 14.2 Death clusters (24 deaths across both probes)

| Cluster | Deaths | Evidence | Root cause in the bot |
|---|---|---|---|
| **Non-letter creatures** | 10 | Creeping Copper Coins (`$`) 7; White Mushroom patch (`,`) 3 | `build_view` only treats letters as creatures, so the bot rests "with nothing in view" next to a monster that is hitting, poisoning, or paralyzing it |
| **Food logistics** | 7 | All 7 starved deep (DL3–5) after "You have no food." | Buys at most five rations per town visit; turns for town only once food is gone; no known up stairs means it rests while starving |
| **Fire from out of view** | 4 | Novice Priest / Novice Mage bolts (10–18 damage), confusion | `unseen_attack` lasts one turn: the bot rests between spells and never leaves |
| **Stationary killers** | 2 | Yellow Jelly, Green Naga acid | Melee or approach of monsters a player would walk around |
| **Sealed area** | 1 | `reach_dl5` seed 1014: 148 squares, search budget spent, 4,478 "nothing to do" turns, starved | Search budget is final; no fallback (more search, tunnel) |

**Also measured:** the starting Wooden Torch dims at about 4,000 game turns
on every run that lasts that long (7 runs), and the bot continues in the dark.
The General Store sells a Brass Lantern (24 gp) and Flasks of Oil (12 gp).

### 14.3 Proposed brain rounds

Each round is one change with red/green unit tests (§7.3), ordered by deaths
removed:

1. **Unfamiliar glyphs: look first, or learn the hard way** (maintainer
   direction 2026-10-21: players use the look command, or get caught
   off-guard). A non-terrain glyph the bot has not identified (`$`, `,`, and
   so on) is treated as unknown, not as floor. When it lies on one of the
   eight lines from the player, the bot looks at it (`X` + direction; no game
   turn) and records what the game reports ("You see …"). Otherwise it keeps
   its distance and lines up or waits. An attack message while an
   unidentified glyph is adjacent marks that glyph as a creature. The monster
   table is no longer used to identify glyphs.
2. **Food and light logistics.** Keep a reserve (e.g. three rations), read it
   from the inventory screen (`I`), and head for town when below it rather
   than when out. Buy a lantern and oil; refuel with `SHIFT+R`.
3. **Threat memory.** Any attack or spell message (including confusion and
   blindness) puts the bot in a threatened state for N turns: no resting, and
   leave by the nearest stairs.
4. **Avoid stationary monsters.** Never melee or path next to creatures that
   do not move (jellies, molds, mushroom patches), learned by watching
   position over turns.
5. **Sealed-area fallback.** When nothing else applies, search again at the
   best spots (no budget), then tunnel.

Deferred unless the clusters demand them: potion identification by use and
buying Cure Light Wounds (stores sell potions unidentified; appearances wrap
modulo 12, so the bot must key an item on appearance *and* price), weapon and
armor upgrades, escapes.

### 14.4 Proposed goals and exit criterion

- **M3 goals:** `reach_dl5` (budget 20k steps) and **`clvl5`** (`want_xp`,
  `target_dlvl=4`, budget 30k). The ladder's `clvl10` moves to M4 with
  `reach_dl10`: at 0/20 with highest clvl 7, it needs more than the five
  rounds above (consumables, gear, light over long runs).
- **Exit:** both goals qualify 20/20 (§7.2), all frozen suites still pass, no
  `unknown_prompt`.
- **Stop rule:** 10 brain-change rounds. If either goal is not working by
  then, stop and write up the blockers.
- **Size:** runtime code is 2,884 lines. The rounds above are estimated at
  400–600 lines, so the signpost would rise to about 4,000 for M3.

### 14.5 Game questions surfaced (not changed)

- **Monster bolts.** Every bolt caster uses one generic bolt, 2d8 + creature
  level (`core/monster_magic.s` `monster_cast_bolt`). VMS Moria's Novice Mage
  Magic Missile is 2d4, and its Novice Priest has no bolt (Cause Light Wounds
  instead). At DL2–5 the bolts did 10–18 damage.
- **Healing rate.** A level-1 Half-Troll took about 1,000 turns to recover
  13 HP (§8.3 run). Not yet compared with the VMS regeneration formula.

### 14.6 Maintainer decisions (2026-10-21)

1. **Goals.** M3 is `reach_dl5` + `clvl5`. `clvl10` moves to M4.
2. **Limits.** 10 brain-change rounds; size signpost about 5,000 lines.
3. **Monster wound spells follow VMS Moria**, after checking Umoria. Umoria
   at the pinned revision is identical: no monster bolts; Cause Light Wounds
   3d8 and Cause Serious Wounds 8d8, each resisted by a player saving throw;
   Novice Mage casts blink, Cause Light Wounds and confuse; Novice Priest casts
   Cause Light Wounds and fear. This is a separate game change (open design
   points in §14.7).
4. **Test isolation.** Under discussion: running emulator tests in private
   network namespaces instead of fixing each fixed-port harness.

### 14.7 Monster-spell alignment

Maintainer decisions (2026-10-21): align the whole spell set except breath,
as its own game task (wound spells with saves, blind/confuse with VMS saves,
durations and stacking, fear, removal of the unused heal spell); use the VMS
save formula with Moria8's existing race/class save values; use Umoria's
corrected "You resist the effects of the spell." Element-correct breath is in
`docs/BACKLOG.md` ("Element-correct monster breath").

Findings that shaped it:

- `tools/parse_creatures.py` maps both upstream wound spells to one
  `MSF_BOLT` bit, and all eight `cr_spell_flags` bits are taken. Creature
  level cannot tell them apart (Death Quasit, level 40, casts Cause Light
  Wounds; Cause Serious Wounds casters are level 28+), so light vs serious
  needs data: a per-creature bit elsewhere, or a small list.
- Moria8 has no player saving throw. VMS uses `player_saves(wis_adj + lev)`
  against the race/class save skill, so a save stat (race and class tables)
  is needed.
- The message becomes upstream's "casts a spell." instead of "casts a bolt!".
- `MSF_FEAR` (`$80`) is set by the generator for 38 upstream fear casters,
  but the game dispatches only spells 0–6, so fear is never cast. Upstream
  casts it.
