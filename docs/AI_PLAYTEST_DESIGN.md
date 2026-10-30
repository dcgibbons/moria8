# AI Playtest Design

Status: revision 8, 2026-10-22. M0, M1, and M2 are implemented and their exit
criteria are met (§8.1–§8.3), re-verified after the F-M2 game fixes. M3 meets
its exit criterion at the 16/20 bar (§14.9); the game defects it found are in
§14.10.
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
- **Optional ROMs (maintainer, 2026-10-27).** `PLAYTEST_KERNAL` and
  `PLAYTEST_DOS1541`, from the caller's environment only, name a C64 KERNAL
  and a 1541 drive ROM that are added as `-kernal` and `-dos1541`
  (`launch.rom_args`). Unset, VICE's own ROMs are used. JiffyDOS is the
  maintainer's preference: its KERNAL with its 16 KB 1541 image (the pair
  works only together, over the true drive). A cold boot took 3.7 s against
  14.1 s with the stock ROMs. The title snapshot's cache key includes each
  ROM's hash, so a snapshot is never restored under the other KERNAL. Any
  other ROM option can be played the same way, to verify the game under it.

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
- **Player knowledge.** `knowledge.py` reads the shipped creature tier data
  (names, native levels, glyphs, speed, "moves only to attack") as what a
  player knows from experience or a monster memory. It is never read from
  game memory. See §14.6 item 7.
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

### 6.9 Dashboard

**Since 2026-10-26 (M5b) the dashboard shows a round, not a session.** A round
is the sessions named `<round>-<goal>-<character>` (for example
`m5b-r36b-clvl10-human-priest`); `/api/overview[?round=R]` returns the
newest round (or `R`) with its suites, and the page, styled with the
moria8.org tokens from `docs/styles.css`, shows: an overall status strip
(elapsed, runs finished, live workers, steps/s, hangs, and per suite its score
against the bar and whether it can still pass); a card per suite with each of
its 20 seeds coloured by outcome and the bar marked; every live worker's C64
screen at once (click for a large screen and its recent decisions,
`/api/worker`); the deepest level reached over steps per character; the
project's round-by-round scores per suite with the bar; and deaths by creature
(parsed from the end of each dead character's trace) and by depth and level.
Charts are inline SVG and the server is the standard library only. The
original v0 description follows.

**Since 2026-10-27 (M5f) it is one page**, laid out to fit one screen:

- **M5 grid:** every race (rows) and class (columns), each cell's clvl10 and
  reach_dl8 side by side: frozen (with the bar it was frozen at), the latest
  full run at the bar but not frozen, below the bar, or not run.
  `/api/milestone` reads `playtest/suites/` and the newest finished session
  of each.
- **This round:** tiles (elapsed, runs, suites passed, deaths, hangs), then a
  row per session: its seed strip with the bar marked, score, verdict, ETA,
  and a sparkline of its score in earlier rounds.
- **Deaths by cause,** stacked by character level: falling rock, pit, arrow,
  poison, a caster's spell, or the creature that hit, read from each dead
  character's trace (`dashboard.death`).
- **What they died holding:** Cure Light Wounds potions, flasks of oil and
  mana left, from the trace's `clw`, `oil` and `status` fields (M5f).
- **Live screens,** with an HP bar under each. A click opens the **focus
  view**: the full-size screen, HP, mana, potions and oil, HP and maximum
  mana over the last 400 steps with potions, Phase Doors and retreats marked,
  and the decisions newest first, refreshed every second. `#watch=<session>/<worker>`
  in the URL opens it directly.
- **Now:** a line under the header saying what the current runs are for,
  from `build/playtest/now.json` (`{"text": ...}`), written by whoever
  starts a phase; absent, the line is hidden.
- **Regression sessions** (`--regress`, no goal of their own) show one row
  per frozen suite, tagged `regress`, with the bar it was frozen at; each
  finished character is matched to the suite it played through the
  session's events (`dashboard.regress_suites`).
- The header shows when the data was made, in the viewer's zone, with its
  age; red and "stale" after two minutes. MORIA8 links to moria8.org.
- **How to read this** (at the bottom): the bar and what frozen means, the
  default and class bars, each combination's own bar, the goals with their
  step budgets, and the colours and tags. Its numbers come from
  `goals.py` through `/api/milestone` (`dashboard.legend`), so it cannot
  drift from the bars it explains.

#### Publishing (`make playtest-publish`, https://playtest.moria8.org)

The dashboard is public (maintainer, 2026-10-27). `playtest/moria_playtest/publish.py`
writes it as static files every 30 s under `build/playtest/publish/`: the page
(with a `playtest-static` meta tag, which makes it read `data/*.json` instead
of `/api/...`, hide the round picker and poll every 30 s), `data/overview.json`
(the newest round only), `data/milestone.json` and `data/workers/<session>--w<N>.json`
for each live worker's focus view. Every absolute host path is cut to its
last part before anything is written (`publish.scrub`). The snapshot is then
copied with `rsync -az --delete-after` over SSH.

The caller's environment names the destination (AGENTS.md rule 9):

| Variable | Meaning |
|---|---|
| `PLAYTEST_PUBLISH_TARGET` | `user@host:/path/`, the web root on the server |
| `PLAYTEST_PUBLISH_KEY` | the SSH private key for that user (optional) |

`PLAYTEST_PUBLISH_ARGS`: `--once` (one snapshot and push), `--no-push` (write
`build/playtest/publish/` only, e.g. to check it with `python3 -m http.server`
from that directory), `--every N`.

**The server** (2026-10-27): a DigitalOcean droplet, Ubuntu 24.04 LTS, on the
maintainer's tailnet. Public DNS (Squarespace) has an A record `playtest` for
its public IP; GitHub Pages keeps serving `moria8.org`. On the server:

- nginx serves `/var/www/playtest` for `playtest.moria8.org`, with `gzip` on
  for JSON, CSS and JS and `Cache-Control: no-cache` on `/data/`; certbot
  gives it HTTPS.
- A `deploy` user owns `/var/www/playtest` and nothing else; its
  `authorized_keys` holds only the publish key (`ssh-keygen -t ed25519` with
  no passphrase, so the loop runs unattended: the key can only rewrite the
  dashboard).
- `ufw` allows 80 and 443 from anywhere and 22 only on `tailscale0`: the
  publisher reaches the server by its tailnet name.

Traffic is small: an update is about 100 KB of JSON (most of it live screens),
about 20 KB gzipped, so a tab left open costs about 60 MB a day; only the
server's outbound transfer is metered.

**The publisher runs as a systemd user service** on the machine that plays,
from this working tree (`moria8-playtesting`, kept for the purpose). The unit
lives in `~/.config/systemd/user/moria8-playtest-publish.service`, outside the
repository:

```ini
[Unit]
Description=Moria8 playtest dashboard publisher (playtest.moria8.org)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=<this working tree>
Environment=PLAYTEST_PUBLISH_TARGET=deploy@<tailnet host>:/var/www/playtest/
Environment=PLAYTEST_PUBLISH_KEY=<home>/.ssh/moria8_publish
Environment=PYTHONUNBUFFERED=1
ExecStart=/usr/bin/make -s playtest-publish
Restart=always
RestartSec=30

[Install]
WantedBy=default.target
```

Install it with `systemctl --user daemon-reload`, `systemctl --user enable --now moria8-playtest-publish`
and `loginctl enable-linger <user>` (so it starts at boot and outlives the
login). Day to day:

- `systemctl --user status moria8-playtest-publish`: is it running.
- `journalctl --user -u moria8-playtest-publish -f`: one line per publish
  (suites and live workers), or the error.
- `systemctl --user restart moria8-playtest-publish`: after changing
  `publish.py` or `dashboard.py`. A change to `playtest/dashboard/index.html`
  goes out with the next snapshot without one.

#### Dashboard v0

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

- **Qualification.** A goal **works** when **at least 16 of the 20 fixed
  qualification seeds** each reach it with their **first character, within
  the goal's step budget**, on the fair-play view and the unmodified build.
  (20/20 until 2026-10-22; §14.6 item 5: the bot need not play every
  creature perfectly.)
- **Determinism.** The step budget is counted in agent steps, not wall time,
  so the gate is deterministic and can fail.
- **Regression.** Once a goal works, its 20 seeds become its **frozen
  regression suite**. Every later brain change must still pass every frozen
  suite at the same bar.
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
| **M3 `reach_dl5`, `clvl5`** | The brain rounds in §14.3: any-glyph creatures, food and light logistics, threat memory, avoiding stationary monsters, sealed-area fallback | Both goals work (§7.2, ≥16/20); all frozen suites still pass; no `unknown_prompt`. **Met 2026-10-22 (§14.9).** |
| **M4 `clvl10`, `reach_dl8`** (`reach_dl10` until 2026-10-24) | The brain rounds in §15.3: stationary hazards, fear and fast attackers, then what the re-measured clusters show | Both goals work (§7.2, ≥16/20); all frozen suites still pass; no `unknown_prompt`. Started 2026-10-22 (`/goal`, §15). **Met 2026-10-24 (§15.6).** |
| **M5 Every race and class at M4** | §16: the M4 goals for every Warrior race, then Paladin and Priest, then Rogue and Ranger, then Mage, then every other race of each class | `clvl10` and `reach_dl8` work (§7.2, ≥16/20; ≥10/20 for Mages and Priests, §16.1 amended 2026-10-27) for each of the 31 race/class combinations, each frozen as its own suite; all frozen suites still pass; no `unknown_prompt`. Planned 2026-10-24 (§16). **M5a (every Warrior race) met 2026-10-25 (§16.8); M5b-M5e met 2026-10-26; M5f met 2026-10-27 (§20.5): 62 of 62 goals frozen.** |
| **M6 Every port plays** | §21: a backend per platform (Plus/4, C128, the MAME ports Apple IIe, Atari 8-bit and BBC Master 128, then the Commander X16); the C64's frozen goals on each; a platform coverage map on the dashboard | On each of the seven ports, `clvl5` and `reach_dl5` frozen for the Half-Troll Warrior and a Human Warrior, Priest, Mage and Rogue (Paladin and Ranger are not in the primary set); no `unknown_prompt`; the C64 suites still pass. The C128 backend (below) is part of it. Planned 2026-10-27 (§21). **M6 met 2026-10-28 (§21.10): 70 of 70 goals frozen.** |
| **M7 More of the game, and balance** | §21.5: feature coverage (spells, items, creatures, traps, stores, recall), the first Word of Recall cycle and `reach_dl15`/`clvl15`, and a difficulty rating per race and class from 40-seed runs | Planned 2026-10-27, after M6; its exit criterion is set when it starts. |
| **C128 backend** (M5c until 2026-10-26; not scheduled) | Half-Troll Warrior on `x128`, no brain work: the backend (§12.7) for VDC screen text, banked reads, the C128 keyboard buffer and the 198×66 map | Every frozen C64 suite passes on the C128 at its bar. Moved out of M5 by the maintainer on 2026-10-26 (§16.2) |

**Stop rules** (defaults, tunable by the maintainer):

- **M0 is time-boxed to two working weeks.** If the replay test cannot pass,
  stop and decide: either drop exact replay (keep snapshots + approximate
  logs), or stop the project.
- **M2 gets 15 brain-change cycles (§7.3).** If both goals are not working by
  then, stop and write up what blocked them before continuing.
- **M3 gets 10 brain-change cycles.** Same rule. The size signpost rises to
  about 5,000 lines of runtime code (maintainer decision, §14.6). Extended by
  the maintainer on 2026-10-22 (`/goal M3`): M3 met its exit in round 28;
  rounds 29-30 re-measured after the §14.11 review fixes (§14.8).

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

## 14. M3 (2026-10-21 to 2026-10-22)

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
- **Exit:** both goals qualify ≥16/20 (§7.2 with the §14.6 item 5 bar), all
  frozen suites still pass, no `unknown_prompt`.
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
  13 HP (§8.3 run). Resolved 2026-10-22 (`TURN_RENDER_CONTRACT.md` TRN-009):
  Moria8 healed 1 HP every 8-50 turns by CON, and read past that 16-entry
  table for CON 18/01 and above (from 1 HP a turn to 1 HP per 128 turns, or
  code bytes). Regeneration now follows VMS `regenhp` (max HP x 0.003 +
  0.022 per turn, x2 while resting, slower when weak or faint).

### 14.6 Maintainer decisions (2026-10-21)

1. **Goals.** M3 is `reach_dl5` + `clvl5`. `clvl10` moves to M4.
2. **Limits.** 10 brain-change rounds; size signpost about 5,000 lines. The
   round limit was lifted on 2026-10-22 (`/goal M3`, run until M3 holds).
3. **Monster wound spells follow VMS Moria**, after checking Umoria. Umoria
   at the pinned revision is identical: no monster bolts; Cause Light Wounds
   3d8 and Cause Serious Wounds 8d8, each resisted by a player saving throw;
   Novice Mage casts blink, Cause Light Wounds and confuse; Novice Priest casts
   Cause Light Wounds and fear. This is a separate game change (open design
   points in §14.7).
4. **Test isolation.** Under discussion: running emulator tests in private
   network namespaces instead of fixing each fixed-port harness.
5. **Qualification bar (2026-10-22).** The bot does not have to play every
   creature perfectly. Every goal, M1-M2 frozen suites included, works at
   **≥16/20** qualification seeds reaching it with their first character
   within the budget (§7.2 otherwise unchanged: fair-play view, unmodified
   build, no `unknown_prompt`). Later rounds prefer general levers over
   tactics for one creature.
6. **Store maintenance follows VMS (2026-10-22).** The bot found a
   starvation trap: stores only refilled empty slots, so a General Store full
   of shovels, lanterns and spikes never offered food again (seed 1014, 18
   empty visits). Store restocking now follows VMS `store_maint`
   (`store1.inc`) on every return to town: above `STORE_MAX_KEEP` items sell
   off (count − max + 2); below `STORE_MIN_KEEP` stock (min − count + 2);
   otherwise sell off 1+randint(3) random items, then stock 1+randint(3). The
   General Store picks from VMS `store_choice` (`values.inc`), 15 of 26 food.
   Moria8 deviations: keep bounds scaled from VMS's 24-item stores to 12
   slots (14/20 → 7/10, turn-around 3); Slime Mold stands in for Hard
   Biscuit, Beef Jerky, Ale and Wine; no Cloak (25 choices); new stock goes
   into the first empty slot and is never merged into an existing slot (VMS
   `store_carry` merges); selling off empties the whole slot, where VMS
   `store_destroy(..., one_of=true)` removes one unit of a stack the player
   sold. Both are deliberate (accepted by the maintainer, 2026-10-22):
   restocked stock is always quantity 1, and the C128 ItemActions overlay has
   11 bytes free. A Flask of Oil keeps its
   existing `p1 = LANTERN_MAX_CHARGES` (its 250-turn fuel). Tests:
   `test_store.s` 28 and 44–46.
7. **Player knowledge from shipped data (2026-10-22).** The brain may use the
   shipped creature tier data as player knowledge (§6.5): names and levels
   (round 1), and the speed and "moves only to attack" flags (rounds 9, 14),
   which replaced §14.3 item 4's "learn stationary monsters by watching".
   Maintainer decision (2026-10-22): keep it for M3 and rework it later to
   learn speed and stationarity by observation (backlog: "Playtester: learn
   creature speed and stationarity by observation").

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

### 14.8 Round log

Seeds 1001–1020, first character, fair-play view; goals registered with the
§14.4 budgets. Frozen suites (`make playtest-regress`) after each round.

| Round | Change | `reach_dl5` | `clvl5` | Frozen suites |
|---|---|---|---|---|
| Re-baseline | Game: monster spells follow VMS (MON-011) | 15/20 | 8/20 | 20/20 ×3 |
| 1 | Look first: unknown glyphs are looked at (`X` + direction, free) or learned from an attack; creature names are player knowledge from the shipped tier data | 14/20 | 15/20 | 20/20 ×3 |
| 2 | Readiness: DL n only at character level ≥ n; hunt for XP when under-levelled | 7/20 | 12/20 | 20/20 ×3 |
| 3 | Food: count foods as a player does, keep a reserve of 2, resupply in town before running out, buy slime molds too | 8/20 | 11/20 | 20/20 ×3 |
| 4 | Unstuck: with no way up take the down stairs and climb back; climb when too deep; re-search instead of resting | 9/20 | 12/20 | 20/20 ×3 |
| 5 | Loop fixes: re-search only at goal depth; after an empty store keep playing 1,500 steps before another town trip | 10/20 | 12/20 | 20/20 ×3 |
| 6 | Unknown glyphs are costly, not impassable (an item can lie in a room's only exit) | 10/20 | 12/20 | 20/20 ×3 |
| 7 | Sealed in: search 25 times per spot, re-search at any depth | 10/20 | 12/20 | 20/20 ×3 |
| 8 | A level marked for leaving is still explored when no staircase is reachable; sealed search also targets walls with unreachable known floor beyond | **12/20** | **14/20** | 20/20 ×3 |
| 9 | Stationary creatures (`,` `J` `e` `m`, from the tier data's attack-only flag) are never fought and are pathed around | 6/20 | 12/20 | 20/20 ×3 |
| 10 | Fear: "You are too afraid!" means no melee for 8 turns and retreat from adjacent creatures | 6/20 | 10/20 | 20/20 ×3 |
| 11 | Explore/search ping-pong: a frontier tile the player stood on without revealing anything (a dark wall or corner) is dead for the level | 6/20 | 11/20 | 20/20 ×3 |
| 12 | The last descent into a depth goal is always allowed (readiness and food no longer matter once arriving completes the goal) and preempts a town trip | 11/20 | 11/20 | 20/20 ×3 |
| 13 | Light: buy a Brass Lantern and 2 Flasks of Oil (torches when no lantern is for sale), offering the asking price when the store haggles; wear it from the `?` list; refuel before it burns out; keep rough time (torch ~4,000 turns, lantern/flask ~7,500) and resupply below 2,000 with no refill. Item prompts get their own mode (`ITEM`) | 10/20 | 9/20 | 20/20 ×3 |
| 14 | Fear is read on every screen (round 10 missed it on `-more-` screens; the last fear message wins); never run on foot from an attacker faster than the player (speed from the tier data) | 12/20 | 10/20 | 20/20 ×3 |
| 15 | Stationary creatures are remembered for the level (out of sight they still block paths); retreat and rest ignore them unless adjacent; an empty store means a restock hop to DL1 and back (stores restock on every return to town), up to 5 before the 1,500-step wait. Bar 16/20 (§14.6 item 5) | **18/20** | 14/20 | 20/20 ×3 |
| 16 | A retreat commits to one staircase, and ends (stand and fight) once it doubles back over its own path | 17/20 | 14/20 | pass |
| 17 | A move that leaves the player in place means something unseen holds the tile: keep off it 10 steps; a blocked tile is never a path goal | 17/20 | 14/20 | pass |
| 18 | Readiness margin: DL n (n ≥ 2) needs character level n + 1 | 13/20 | 13/20 | pass |
| 19 | *Game:* VMS store maintenance (§14.6 item 6) | 11/20 | 14/20 | 19/20 ×2 (new dungeons) |
| 20 | No walking onto known traps below half HP; an unseen attacker is only pinned on a glyph some creature uses; a fight that lands on the target drops the identification; store visit bookkeeping however the visit ends | 13/20 | **16/20** | pass (bar 16/20) |
| 21 | Fight a faster attacker only when it is visible; no secret-door search while attacked unseen | 12/20 | 16/20 | pass |
| 22 | Afraid: throw a Flask of Oil at a creature in line (fear blocks melee only); carry 3 flasks. *Game:* the throw prompt's `?` list crashed (§14.10) | 15/20 | 16/20 | pass |
| 23 | Disarm a known trap on the path (3 tries) before walking over it | 15/20 | 16/20 | pass |
| 24 | Readiness margin: DL n (n ≥ 3) needs level n + 2. Session workers run as processes (§14.10) | 12/20 | 19/20 | pass |
| 25 | Hungry with no way up and nothing to explore: down stairs lead to a fresh level | 13/20 | 19/20 | pass |
| 26 | *Game:* level-up from overlay code crashed (§14.10), first fix reverted | — | — | — |
| 27 | *Game:* level-up magic deferred to `main_loop` | 14/20 | 19/20 | pass |
| 28 | Retreat only to stairs within 12 path steps; farther, stand and fight (hunt even when hurt) | **16/20** | **18/20** | 20/20, 19/20, 19/20 |
| 29 | §14.11 review fixes (runner, item prompts, attacker pinning, path steps, oil and message bookkeeping, deferred level-up flag and status redraw) | **17/20** | **18/20** | 20/20, 19/20, 19/20; `reach_dl5` 17/20, `clvl5` 18/20 |
| 30 | §14.11 round-2 review fixes (audit exit, pending pick across `-more-`, message repeats, regress budget) | 17/20 | 18/20 | all five pass (same seeds as round 29) |
| 31 | Game: VMS HP regeneration (TRN-009). With one-turn rests the bot fell to `reach_dl5` 14/20, `clvl5` 17/20 (only CTRL+R rests at the doubled rate); the brain now rests with CTRL+R, which TRN-007 made safe (stops on damage or hunger) | **18/20** | **20/20** | all five pass: `enter_dungeon`, `reach_dl2`, `reach_clvl2` 20/20 (regress against the round-30 suites) |

After round 1, Creeping Copper Coins deaths went from 6 to 0 (48 identifications
by look). Round 2 removed most early caster deaths but made runs much
longer, which exposed food and stuck-level failures (rounds 3-6). Round 6
changed nothing on these seeds: the stuck seeds were really sealed in by a
secret door that 6 searches per spot rarely find (one took 36 searches in a
direct probe), which round 7 addresses.

### 14.9 M3 result (2026-10-22): exit criterion met

Round 28 first met the §14.4 exit at the §14.6 item 5 bar (`reach_dl5`
16/20, `clvl5` 18/20). After the §14.11 review fixes, round 29 holds it:
`reach_dl5` 17/20 and `clvl5` 18/20 first-character seeds, every frozen suite
passes (`enter_dungeon` 20/20, `reach_dl2` 19/20, `reach_clvl2` 19/20,
`reach_dl5` 17/20, `clvl5` 18/20), and no `unknown_prompt` occurred. Both goals are frozen (`playtest/suites/reach_dl5.json`,
`clvl5.json`, 16/20 bar recorded). The rounds went past the original stop
rule of 10 at the maintainer's direction (`/goal M3`).

What the bot learned, each round with unit tests that failed first (80 new;
128 in the playtest suite after the §14.11 review fixes): look
identification; readiness margins; food and light logistics
(lantern, oil, restock hops); stuck, sealed and trapped levels (search,
disarm, the down-stairs way out); fear, invisible and faster attackers
(throwing oil); retreat discipline (one staircase, no doubling back, only
when the stairs are near). Runtime code: 3,696 lines by the §2 rule (tests,
`m0.py` and `fuzz.py` not counted; signpost 5,000).

`reach_dl5` passes one seed above the bar (17/20): brain changes that cost
two seeds fail its frozen suite.

Remaining failures (round 29): `reach_dl5` Poltergeist (1001), the
gas-trap-then-Kobold DL1 death (1002, unchanged since the store change gave
it a new dungeon), and Novice Priest (1017); `clvl5` 1002 and 1017.

### 14.10 Game defects found by the M3 bot (2026-10-22)

1. **General Store starvation trap** (found in round 18, fixed for round 19): stores only refilled empty
   slots, so a store full of gear never offered food again. Fixed by VMS
   store maintenance (§14.6 item 6); `test_store.s` 28, 44-46.
2. **Throw `?` list crash** (found and fixed in round 22): `throw_item` (ITEMS overlay) called
   the resident selector directly, so the inventory list's HELP overlay was
   never replaced by ITEMS before returning; every C64 throw that used `?`
   ended in BRK. Fixed by using the overlay's `item_action_select_filtered_inv`
   (which records the return overlay), as read/aim/use already did.
3. **Level-up from overlay code crash** (found in round 24; a first fix in
   round 26 was reverted; fixed for round 27): `combat_apply_levelup`
   ran the magic trampolines, which load an overlay over the window, from a
   kill made by ITEMS/SPELL overlay code (thrown or fired missile, bash,
   spell); the overlay code then resumed over the wrong overlay. The same
   path hung wizard-mode level-up on C64. Fixed by deferring the mana/spell
   recalculation to the top of `main_loop` (resident code only on the
   stack); level, HP, bonuses and the message stay immediate. Static
   contracts `levelup_magic_deferred_contract` and
   `levelup_magic_main_loop_contract`. A first fix that reloaded the overlay
   recorded in `current_overlay` was reverted: tier loads never update that
   byte, so it reloaded ITEMS over live creature tier data.
Follow-on test fix (not found by the bot): C64 `test_chest_open.s` ran ~2 KB
into the map region, and the chest explosion's map write landed on test data
once resident code grew. Unexecuted modules now load above the result
buffer, with a below-`MAP_BASE` assert.

Session runner (round 24): workers are OS processes, not threads (the
brain and emulator protocol are CPU-bound Python under the GIL); a
measurement round of both goals plus the frozen suites takes about 3
minutes with 32 workers instead of most of an hour.

Known tool gap: `make playtest-repro` did not reproduce either overlay
crash from its level-entry snapshot, though fresh-game probes did
deterministically.

### 14.11 Adversarial review (2026-10-22)

Three reviewers (staff engineer, engineering manager, 6502 performance
specialist) reviewed the M3 change set. Resolutions:

- **Runner could drop seeds** (`session.py`): a worker that raised anything
  but `GameFault`, or died, lost its seed silently, and regress measured the
  bar against the results that came back. Now every seed gets a result
  (`error` for a raised character or a dead worker), workers take seeds
  through a blocking queue with sentinels (forked before the queue's feeder
  thread starts), regress measures against the suite's seed list, and only
  the full qualification seed list can be frozen. Test `RunSeedsTest`.
- **`Mode.ITEM` could hide stray prompts:** an item prompt the brain did not
  ask for (`Brain.expects_item_prompt`) is now filed as `unknown_prompt`.
- **Attacker pinned on any glyph:** an unseen attacker's name is only given
  to an adjacent unidentified glyph it is drawn with (`knowledge.glyphs_of`),
  and not when a visible creature with that glyph is adjacent.
- **Retreat range compared weighted cost:** `View.path_steps` counts steps.
- **Oil counted before it was used:** counted when a flask is picked to
  throw, or when the game confirms a refuel.
- **Food and light news on `-more-` screens was lost:** messages are read on
  every screen, once per distinct screen; the light countdown stays per
  command step.
- **Level-up deferral:** a flag, not a counter (one recalc however many
  levels); `status_draw` after the recalc so the new maximum mana shows at
  once; cleared on new game and load; ledger row TRN-008 in
  `docs/TURN_RENDER_CONTRACT.md`.
- **Store:** an assert that store slots stay below `$80` (the code marks
  "none" with `$FF`); the stack and merge deviations are documented in §14.6
  item 6.
- **`test_chest_open.s`:** `player_magic.s` is back in the executable region
  (the non-trampoline level-up path calls it); `monster_ai.s` stays above the
  result buffer (only `turn_post_action` reaches it, and the tests never call
  that).
- **Docs:** round numbers in §14.10, test and line counts in §14.9, the round
  limit in §8 and §14.6, the fair-play decision (§6.5, §14.6 item 7).
- **Not changed:** `clvl5` keeps `target_dlvl=4` (its description now says
  readiness keeps it on DL1-2); the two unused imports in `m0.py` predate M3.

Round 2 (Sonnet reviewers):

- **The round-1 item-prompt check broke the game-finding exit:** inserted
  between `file_finding` and `if finding.cls == "game"`, it nested that line,
  so game findings stopped ending characters and a stray item prompt could
  raise. The per-observation audit is now `Character.audit`, with tests for
  both cases (`CharacterAuditTest`). Round 29 filed only `stall` findings, so
  its results stand.
- **A `-more-` screen cancelled a pending item pick:** the pick path now runs
  only on `Mode.ITEM` screens.
- **Identical consecutive messages:** only a repeat of a prompt screen's text
  is skipped; two pickups in a row both count.
- **Error path left VICE running:** the worker is stopped before a fresh one
  is made.
- **Regress:** no frozen suite fails the gate; each suite runs with its
  frozen step budget.
- **Docs:** round 29 recorded; §14.9 restated against it; TRN-008 has a
  verification-matrix row naming the smoke gate.
- **Not changed:** the pickup message names one item even for a stack (the
  game prints no quantity), so a stack counts once, as a player would read
  it. Apple IIe and CX16 keep the wizard path's overlay reload after level-up
  (now a guard; comment updated).

Round 3 (Sonnet reviewers): no blocker or major findings. Minor fixes: a test
that text already counted on a prompt screen counts once on the next command
screen; `RunSeedsTest` now proves the error path stops its worker; the
runner sets `stop` and terminates its workers if the parent itself fails.
Counts in §14.9 refreshed; §8 says where the exit was met. Confirmed, not
changed: the 16/20 bar now also governs the M1-M2 suites (§14.6 item 5).

Round 4 (confirmation): the engineering-manager review found nothing. The
staff-engineer review found that the round-3 parent-failure path sent SIGTERM
to workers with no handler, orphaning their VICE processes (VICE runs in its
own session). Workers now turn SIGTERM into an orderly exit and stop their
emulator in a `finally`; a failed parent waits `WIND_DOWN_SECONDS` per worker
before terminating. Test `RunSeedsParentFailureTest` (every started worker
stops). Not changed: a second interrupt during that wind-down can skip the
remaining joins (cosmetic; the workers still stop their emulators).

Round 5 (confirmation): no blocker or major findings. Accepted residual
risks, not changed: SIGTERM arriving inside a worker's own emulator stop
could interrupt it in a narrow window (bounded by the process-group signal
`launch.kill` already sent); an exiting worker joins its result-queue feeder
thread, which could block only with more than about 64 KB of unread results
(each result is a small dict).

Maintainer decisions after round 5 (2026-10-22): the test-infrastructure edits
made to validate the product changes are accepted (C128 `run_tests128.sh`
throw chain, `test_main_loop128.s` stubs, `test_chest_open.s` layout); the
store deviations are accepted (§14.6 item 6); the shipped-data player
knowledge stays for now, with a backlog item to learn it by observation
(§14.6 item 7).

Round 6 (final, all three reviewers on the final tree): no findings. Final
gates on that tree: `make -j5 -O test` and `make test128` (137/137) pass;
playtest check, smoke and the five frozen suites pass.

## 15. M4 (from 2026-10-22)

The maintainer started M4 on 2026-10-22 (`/goal proceed with M4`). The goals
were decided with M3 (§14.4, §14.6 item 1): `clvl10` and `reach_dl10`. The
exit criterion is M3's (§8). On 2026-10-24 the maintainer replaced
`reach_dl10` with `reach_dl8` ("change to reach_dl8") after rounds 71-79
held `reach_dl10` at 20-24 of 40; rows below that name `reach_dl10` are the
history of the old goal. The same direction raised the food the bot carries
("carry more food": up to 20 rations' worth, 16 purchases a visit).

### 15.1 Baselines

The brain after round 31 (`5c625e2`: VMS HP regeneration, CTRL+R rests),
seeds 1001-1020, first character, fair-play view. The goals were registered
only for the probe (100,000-step budgets, so the runs end in death rather
than the budget).

| Probe | Result | Notes |
|---|---|---|
| `clvl10` (`want_xp`, `target_dlvl=8`) | **0/20**: 16 died, 4 findings | Highest clvl 9, deepest DL6 |
| `reach_dl10` (`target_dlvl=10`) | **0/20**: 16 died, 4 findings | Highest clvl 9, deepest DL6 |

Sessions: `build/playtest/sessions/m4-baseline-clvl10` and
`m4-baseline-reach_dl10`.

All 8 findings were the auditor, not the game: three-digit HP fills its status
field (`HP:105/105MP:0/0`), which the status parser could not split. They
ended the 8 strongest characters (clvl 8-9, 100+ HP). Fixed with a regex and a
test (`STATUS_HP`).

### 15.2 Death clusters (32 deaths across both probes)

Seeds 1006, 1008 and 1016 died the same way in both probes.

| Cluster | Deaths | Evidence | Root cause |
|---|---|---|---|
| **Stationary hazards** | 14 | Yellow Jelly 6 (searching or resting beside it; its poison finished the rest); White Mushroom patch 8 (paralysis spores: one character went from 81 HP to dead without a move) | The bot searches, explores and rests next to creatures that never move. Moria8's paralysis matches Umoria (save, no stacking, `randint(level)+3` turns). |
| **Fear and a fast attacker** | 11 | Poltergeist: "frightens you", then 50-80 hits while the bot retreats, searches or explores | Afraid, the bot cannot melee; it runs from a creature faster than itself, and threw oil once |
| **Poison** | 2-3 | HP falls 1 a turn while resting, no attacker in view | Game: Moria8 did 1 HP every poisoned turn; VMS scales by `con_adj` (CON 18: 1 HP every other turn). Fixed by maintainer decision (TRN-010). |
| **Others** | 4 | Green Naga 2, Novice Mage 1, Creeping Copper Coins 1 | — |

Stalls: 30 `stall` findings (no new map or XP for 300 steps while
stair-scumming), mostly on DL1-5.

### 15.3 Proposed brain rounds

1. **Stationary hazards.** Never search, rest or stand next to a known
   stationary creature unless attacking it on purpose; step away first.
2. **Fear and fast attackers.** Afraid with an attacker adjacent or close:
   throw (oil or any missile) instead of running from a faster creature.
   Not afraid: fight weak fast creatures rather than retreat.
3. Re-measure; then the remaining clusters and the stair-scum stalls.

Rounds 1 and 2 became rounds 32-33 (§15.5).

### 15.4 Game changes during M4

1. **Poison damage by `con_adj`** (2026-10-22, maintainer: "yes align the
   poison"): `TURN_RENDER_CONTRACT.md` TRN-010.
2. **The last paralyzed turn gives the player a command first** (2026-10-22,
   maintainer: "yes"): `TURN_RENDER_CONTRACT.md` TRN-011. Moria8 let
   monsters act between paralysis expiry and the player's next command, so a
   White Mushroom patch could paralyze the player again before every move.
3. **Fear attack** (2026-10-23, maintainer goal: "make recommended fixes as
   discovered"): `MONSTER_STATE_CONTRACT.md` MON-012. Moria8 had no saving
   throw and replaced the timer; VMS saves on `wis_adj`, then 3 +
   randint(level) turns, +3 while already afraid.
4. **Stores identify their stock** (2026-10-23, maintainer goal): VMS
   `store_create` puts each new item through `store_carry`, which calls
   `identify` (`desc.inc`: `object_ident[...] := true`), so every kind a store
   stocks is known by name. Moria8 stocked unidentified flavours ("Cloudy
   Potion"); `sro_stock` now calls `id_known_set`. Noted, not changed: Moria8's
   Cure Light Wounds potion heals 4-11 and cures nothing else; VMS heals 2d7
   and cures blindness (`potions.inc` effects 13 and 29).
5. **Monster random movement** (2026-10-23, maintainer goal):
   `MONSTER_STATE_CONTRACT.md` MON-013. `tools/parse_creatures.py` dropped
   Umoria's `CM_20/40/75_RANDOM` bits, so erratic creatures (Poltergeist 88%
   random, worm masses 75%, 41 creatures at 20%) chased the player on every
   move. Paid for by two shared helpers (`core/df_target_row.s`
   `df_target_row_ptr`, 21 inline copies; `core/df_target_dir.s`
   `df_target_from_dir`, 3 copies), each `#importonce` and imported by every
   user, first by a resident file on every platform.
6. **Monster treasure drops** (2026-10-23, maintainer direction "yes
   proceed"): `MONSTER_STATE_CONTRACT.md` MON-014. The generator also dropped
   the CMOVE treasure bits, and no kill path called a drop routine, so the
   only gold came from veins, floor piles and chests; the bot could rarely
   afford potions or Word of Recall. A per-creature `cr_treasure` byte (tier
   SoA field) and a kill-time queue feed the chest-contents generator. Memory:
   C64 moved `combat_msg_buf` and `creature_name_buf` to free page-2 RAM
   (`$02A7-$02FF`); C128 moved the Bank 1 tier cache base from `$8000` to
   `$7F00` (the DB region ends at `$79D5`); C128 places the module and
   `look_flash_target` in the main image.
7. **Gold pickup lost 256 gold per carry** (2026-10-23, found by round 50):
   `item_pickup` added the low byte of a gold pile, then called
   `floor_item_get_qty_hi_x`, whose `cmp #2` cleared the carry before the
   middle byte was added, so every pickup that crossed a multiple of 256
   dropped 256 gold (seed 1010: 9,000 collected, 203 in hand). The high byte
   is now fetched first. C64 `test_item.s` t58 (249 + 14 = 263; $00FF +
   $0102 = $0201; fails on the old order).
8. **Temple and Alchemy shop stock follows VMS** (2026-10-23, maintainer
   direction "let's make these store stocks behave like VMS moria does"):
   both stocked random potions and scrolls by category, so Word of Recall was
   1 kind in 34 at the Temple and never at the Alchemist, while Genocide,
   *Destruction*, Aggravate and Potions of Poison sold freely. They now pick
   from VMS `store_choice` (`values.inc`, indexing `inventory_init`) like the
   General Store (§14, item 6), mapped to Moria8 items: Temple 23 of 26
   entries (Cure Light Wounds x3, Word of Recall x2, prayer books, Remove
   Curse, blunt weapons; Restoration for Restore Wisdom; no Boldliness,
   Restore Life Levels or Blessing), Alchemy shop 21 of 26 (Word of Recall
   x3, Identify, Light, Magic Mapping, enchanting, Restoration x5 for the
   Restore potions, Neutralize Poison for Slow Poison; no Phase Door,
   Treasure Detection or Detect Invisible). What a store buys from the player
   is unchanged (the Temple sells maces it will not buy; VMS's Alchemist also
   buys scrolls). `docs/MANUAL.md` updated. C64 `test_store.s` t48
   (mutation-checked), t43 part E narrowed to category-stocked stores. The
   C128 ITEMS overlay, which holds the restock code, has 0 bytes left.
9. **Items stack** (2026-10-23, maintainer direction "yeah stack!"): Moria8
   gave every item its own pack slot, so 20 single rations filled the
   22-slot pack and Word of Recall could not be bought. Identical food,
   potions, scrolls, flasks of oil, spikes and ammunition now share one
   slot up to 255, as VMS `inven_carry` merges them (`core/inv_add.s`);
   eating, quaffing, reading, refuelling, throwing, firing and spiking use
   one (`inv_consume_one`); selling sells one at the one-item price; a stack
   shows its count. Not done: a full pack still refuses an item that would
   only merge (VMS `inven_check_num` allows it); names are not pluralised.
   Memory: C64 moves five pure scratch groups to free page-2 RAM and BASIC's
   line buffer ($0200-$0258; 1 byte left below $C000), Plus/4 three buffers
   to its BASIC buffer, Atari the item-name buffer after `msg_history` in
   high RAM, C128 `inv_add.s` to the main image, and BBC `item_spawn_level`
   into OVL.GEN behind a resident trampoline (its Bank 7 GEN cache slot
   grows to 21 pages; `docs/BBCMASTER_MEMORY_CONTRACT.md`). C64
   `test_item.s` t59-t61 (mutation-checked).
10. **Acid damages armour** (2026-10-24, maintainer direction "Full VMS"):
   Green and Black Nagas, which spit acid every turn, caused about 40% of
   M4 deaths. Moria8 applied the full acid dice; VMS `acid_dam`/`minus_ac`
   damages a random worn armour piece ("Your <item> is damaged!", to-AC - 1)
   and halves the damage while that piece has AC left (MON-015,
   `docs/MONSTER_STATE_CONTRACT.md`). Shared code in `core/monster_acid.s`;
   the C128 main image and the Apple IIe and BBC Master resident images
   carry it, and the C64 found the bytes by sharing two inventory-slot copy
   helpers (`inv_slot_to_fi_add`, `fi_add_to_inv_slot`). C64
   `test_monster_attack.s` t18-t22 (mutation-checked).

### 15.5 Round log

`clvl10` and `reach_dl10` qualification runs (20 seeds, first character,
100,000-step provisional budgets), after the game changes in §15.4.

| Round | Change | `clvl10` | `reach_dl10` | Notes |
|---|---|---|---|---|
| baseline | — | 0/20 | 0/20 | §15.1 |
| 32 | `step_away` layer (move off any square next to a stationary creature); no search spots next to one; `throw` before `retreat` | 1/20 | 0/20 | Worse: the bot stepped away from a Floating Eye or Yellow Jelly beside its path, then the path stepped back, until paralysed or poisoned to death (about 12 deaths on DL1-2) |
| 33 | `step_away` removed (paths already pay 25 per square next to one); glyph memory: unidentified glyphs are remembered off screen (seed 1003 flipped between two squares for 200 steps as a `$` scrolled in and out, then starved); no rest for 20 steps after an unseen attack (seed 1010 rested beside a blinding Bloodshot Eye until it starved) or while out of food (seed 1008); always carry 3 Flasks of Oil to throw (seed 1004 had no lantern, so no oil, against a Poltergeist) | 6/20 | 0/20 | `clvl10` successes at 15-20k steps; `reach_dl10` reaches DL8 at clvl 11. Deaths: Poltergeist ~13, Green/Black Naga 6 (stood and fought), oscillations 3, dark 2 |
| 34 | Full pack read (item `u` on row 21 was never found: seed 1006 retried a throw 121 times); an item the list does not show resets its count; far stairs still flee a creature with no spells (seed 1014: Black Naga); an A-B-A-B oscillation blocks the square it returns to (seeds 1001, 1003, 1012); spare torches always (seed 1007: 3,400 steps in the dark) | 8/20 | 1/20 | Poltergeist 13 of 31 deaths: fear stacks +3 a hit (MON-012, as upstream) and never wore off |
| 35 | Afraid of a faster attacker: any staircase, down too, and no give-up on doubling back; every flask may be thrown when spare torches back up the lantern | 6/20 | 4/20 | Poltergeist down to ~4; Creeping Copper Coins ~10 (they follow; each step a new unidentified `$`); White Mushroom patch 4 (stairs ringed with them) |
| 36 | No rest with an unidentified creature glyph within 2; walk away from slow creatures (`$`) when no stairs; swat a fragile stationary creature (`,`: 1 HP) beside the path | 7/20 | 1/20 | Coins still ~8 (they follow one square behind, out of the light); ~8 starved searching sealed DL1-2 pockets |
| 37 | Threat memory: a creature (or unidentified creature glyph) within 2 squares keeps the bot from resting for 5 steps (replaces round 36's "unidentified glyph within 2" rule); short of food with a staircase in reach, never search walls | 9/20 | 1/20 | ~10 starved in `fallback`: round 37's "no search when short of food" left no layer acting where `stair-scum` would not take down stairs |
| 38 | Round 37's search rule replaced: short of food, `stair_scum` runs before `search` | 9/20 | 1/20 | Same deaths: `stair-scum`'s forced search came before its down-and-back hop |
| 39 | Game: stores identify their stock (§15.4 item 4). Bot: short of food with no way up, the down-and-back hop comes before a forced search; buy Cure Light Wounds at the Alchemist (reserve 3) and drink one below 30% HP | 4/20 | 1/20 | Broken: the quaff prompt reads "Quaff which potion (a-a)?", which the item-prompt check ("which item") missed; cancel-and-retry loops ran characters out of budget (~650k quaff steps) |
| 40 | Item prompts recognised by "which item/potion/scroll/food/wand/staff (a-" | 5/20 | 1/20 | Potions bought (~3k shop steps) but rarely decisive; Poltergeist ~10 deaths, 50-70 hits each: led to MON-013 |
| 41 | Game: monster random movement (MON-013) | 8/20 | 4/20 | Poltergeist deaths gone. Gates pass, regress passes (17-20/20). Starvation ~10 ("You have no food" 200-300 steps before death, DL3-8); Creeping Copper Coins ~6 |
| 42 | Food in ration units (a Slime Mold is a third); reserve 2 + depth/3 rations; 8 food purchases a visit | 12/20 | 7/20 | Starvation still 10: sealed-looking pockets whose frontier squares revealed nothing (seed 1003 rested 1,500 steps beside an open door) |
| 43 | `grope`: before resting with nothing to do, step into the unknown neighbours of frontier squares that revealed nothing, once each | 13/20 | 7/20 | `reach_dl10`: 6 of 10 deaths still starvation (level 10-11 characters climbing home from DL2-8 through levels with no reachable up staircase); 3 out of budget |
| 44 | Word of Recall: buy one at the Temple (Moria8's Temple sells potions and scrolls; VMS stocks Word of Recall at the Alchemist and Temple), read it from DL3+ with supplies low, and in town after shopping to return to the deepest level; wait in place for the yank | 9/20 | 1/17 (stopped) | Worse: Temple trips every visit (~6,700 steps) for 2 scrolls read; the gold was rarely there |
| 45 | Temple trip only with the gold (status `AU:`; Cure Light Wounds 60+, Word of Recall 250+); never melee slow creatures (Creeping Coins) unless cornered, and never hunt them | 4/18 | 0/13 | Stopped early; clearly worse than round 43. Gold was the limit: monsters dropped nothing, which led to MON-014 (§15.4 item 6) |
| 46 | Game: monster treasure drops (MON-014). Bot: `collect` walks to identified gold and food in view (12 steps) and picks it up (`G`); Creeping Coins ('$') are fought at 80% HP or more, since they now drop gold | 2/9 | 0/7 (stopped) | Gold beside a Floating Eye: the bot walked to it, stood down when the eye counted as a threat, and was walked back, 2,900 times (seed 1001); Yellow Jelly beside gold |
| 46b | `collect` picks up on arrival whatever is in view, skips items beside a creature that never moves, gives up after 36 walks; slow creatures not worth a fight become hazards | 5/13 | 0/7 (stopped) | Coins ~8 of 15 deaths: a looked-at coin read as an unknown '$' after every step, and explore walked back beside it between hits |
| 47 | An identified creature keeps its name when its glyph moves one square; a retreat from an unseen attacker keeps going while it may still be there | 8/13 | 0/9 (stopped) | Coins still: two squares off in the dark a torch-lit player does not see them; explore and retreat alternated |
| 48 | A retreat also keeps going while a creature was seen close (5 steps); slow creatures stay hazards 30 steps out of sight | 14/20 | 3/17 (stopped) | `clvl10` best yet. `reach_dl10`: starvation on the climb home from DL6-8 (Word of Recall bought 6 times in 17 characters: Moria8's Temple stocks random potions and scrolls), coins, Green Naga, Yellow Jelly beside the only corridor |
| 49 | Paths pay 150 extra per square next to a hazard (Yellow Jelly corridors) | 13/20 | | Seeds 1003, 1006, 1013, 1015, 1017 die as in round 48: a Brown Mold beside a resting, confused player; exploring back into a Green Naga at a third of HP; long DL1-2 searches |
| 50 | Never rest, search or wait beside a creature that never moves: step off; badly hurt with resting blocked by a creature seen close, back away from where it was last seen; a Black Market trip for Word of Recall with 600 gold or more | 9/14 | 2/11 (stopped) | No Black Market trip ever: gold never reached 600 though characters picked up 3,600-9,000. The game lost 256 gold on each pickup that carried (§15.4 item 7) |
| 51 | Game: gold pickup carry fixed | 16/20 | 4/17 (stopped) | `clvl10` meets the bar. With gold kept, 6 of 12 `reach_dl10` characters bought Word of Recall at the Black Market. Deaths: White Mushroom patches attacking a paralysed bot whose next command screen said only "You can move again." (it rested beside them), Novice Mage groups confusing it, coins, Yellow Jelly |
| 52 | Game: Temple and Alchemy shop stock follows VMS (§15.4 item 8). Bot: an attacker named behind `-more-` counts on the next command screen | 9/17 | 0/7 (stopped) | The stock change shifts every dungeon (store RNG draws), so per-seed outcomes moved. Sealed pockets: a felt-out dead-end edge still counted as a way out, so the bot rested 2,700 turns and starved (seeds 1005, 1003, 1011); explore walked into a Yellow Jelly sitting on an unexplored edge (a goal square is entered whatever stands on it) |
| 53 | A dead-end edge already stood on is no way out (sealed searching starts), groping comes before forced searching; no frontier square under a creature or next to a hazard | 13/20 | 5/20 | `reach_dl10` deaths: 4 starved sealed in (never read the Word of Recall they carried), 7 lost fights (Green Naga 3, coins 2, Novice Mage/Priest groups, Skeleton Orc) |
| 54 | Sealed in and short of food: read Word of Recall at any depth. Harness: playtester hot paths optimised (same decisions over a 3,000-step trace, 22.2 s to 16.3 s per character: `decide` 6.0 s to 2.8 s); iteration rounds cap characters at 50,000 steps (`--step-budget`; final qualification keeps the goal's 100,000) | 13/19 | 4/17 | A full pack: items never stack in Moria8, and 20 single foods (8 bought per visit) filled 22 slots, so Word of Recall purchases failed (seed 1020) |
| 55 | Carry at most 8 rations' worth; Slime Molds only to make up the reserve | (invalid) | (invalid) | The disk filled (2.4 TB of level-entry snapshots) and 13 workers' dumps timed out. Cause: the reserve followed the current depth, so a character with 2.33 rations went up from DL3 and back down from DL2 every step (~4,000 level entries each). Harness: keep only the latest snapshot per character and those findings cite |
| 56 | Food reserve from the deepest level since town; creature toughness memory (a kind that cost half the HP without dying is not hunted and is fled at 80% for 3 levels) | 15/20 | 5/16+ | Round in ~8 minutes, 144 MB on disk. Characters now buy and use potions and Word of Recall; most deaths came after drinking all three Cure Light Wounds |
| 57 | Carry 5 Cure Light Wounds | 15/20 | 3/17 | Starvation 8: once the reserve was made only Rations were bought, and none when the store had none |
| 58 | Slime Molds up to 2 rations over the reserve; carry at most 10 rations' worth | 10/20 | 6/17 | Starvation 5; Creeping Coins 6 (fought at full HP since round 46), Green Naga 5 |
| 59 | Never fight Creeping Coins unless cornered | 11/20 | 2/17 | Starvation 9 again. Rounds now swing about 5 characters on any change (every change reshuffles all 20 dungeons) |
| 60-64 | Game: items stack (VMS `inven_carry`; §15.4 item 9). Bot: depth goals descend at character level = depth (40-seed A/B: 12/40 vs 6/39); no resting while a slow creature was seen in the last 30 steps; carry 2 Word of Recall; clvl10 avoids and flees creatures with monster-lore HP > 20 + 4 x level or AC > 20 + 3 x level (A/B: 24/35 vs 20/37; it halved reach_dl10, so depth goals do not use it). Harness: per-worker VICE config with the version tag (no desktop dialogs) | 15/20 | 12/20 | Round 64, full 100,000-step budget. Rounds 62-63: 11/20 and 12/20 |
| 65-70 | 40-seed A/B tests, all rejected: creature-near memory 15 steps (reach 15/40 vs 22/40), dive at level = depth - 1 (12 vs 20), toughness at 30% HP lost (14 vs 22), retreat at 45% HP (14 vs 21), spare oil thrown at strong creatures (no effect: rarely more than 3 flasks), tunnelling out when sealed (19 vs 22; the sealed test fires too often) | | | Two `hang` findings in the input wait loop (`input_sound_update`, `hal_sound_update`) under 32-64 parallel emulators; neither reproduces from its snapshot |
| 71-78 | 40-seed rounds (`reach_dl10` at 100,000 steps from round 76, `clvl10` at 50,000). Bot: kill a weak creature that never moves when it blocks the only way on (seed 1021 starved behind a Floating Eye; seed 1006 searched a room 12,000 turns with an eye beside its door); one level from a depth goal, the depth-scaled food reserve no longer sends it home; dark floor the game forgets stays remembered (seed 1023 oscillated 6,000 steps); with nothing else to do it searches instead of resting; casters by kind, not glyph (one Orc Shaman made every Orc a caster); `reach_dl10` builds up first (readiness margin 2, maintainer direction); buy the best affordable weapon (blows x dice from the game tables) and armour, keeping 200 gold. Rejected: walking away from strong nagas (naga deaths rose to 8 a goal). Game: MON-015 acid. Harness: an input stop that lands as a long resume is interrupted is caught (three false `hang` findings) | 30/40 best (round 74), 21-28/40 since | 24/40 best (rounds 71, 78) | Any change reshuffles about a third of the seeds: differences under about 7 of 40 are noise. Nagas remain the largest killer, then Creeping Coins and starvation |
| 79-92 | `reach_dl8` replaces `reach_dl10` and the bot carries more food (maintainer direction 2026-10-24); clvl10 descends at three levels over each depth (40-seed A/B: 31/40 against 28/40); every round at the full 100,000-step budget from 83. Bot: Word of Recall from the Alchemist, before Temple potions (79 bought in 40 characters, from ~5), and read whatever the food after 2,000 steps without progress; fight back in town when attacked; a crowd of two or more within 3 squares of a staircase takes it, up or down (a Creeping Coins nest by the arrival stairs); explore never steps back beside slow creatures, seen or remembered; a weak Floating Eye beside the player is killed; killing a weak blocker waits until nothing else is close; a door given up on is bashed again when sealed in; sealed in, a weak stationary creature, seen or remembered, is killed so the squares beside it can be searched; an attack is unseen when nothing in view is drawn like its named attacker, and searching stops for 20 steps after one; no look through an identified item, and an attack relabels an item glyph as its attacker. Rejected: monster-lore armour threshold 14 + 3 x level (30/40 and 24/40 against 29/40 and 23/40) | 12-18/20; **18/20** (round 92) | 13-17/20; **17/20** (round 92) | Round 92 meets the exit criterion with both goals at once. Findings: only bot `stall` notes, no `unknown_prompt` |

### 15.6 M4 result (2026-10-24): exit criterion met

Round 92 met the exit criterion with both goals in one run on the first
character of the 20 qualification seeds at the 100,000-step budget:
`clvl10` 18/20 and `reach_dl8` 17/20 (bar 16/20), with no `unknown_prompt`
and no game finding (only bot `stall` notes). Both goals are frozen
(`playtest/suites/clvl10.json`, `reach_dl8.json`; the freeze rerun matched
round 92 exactly, the emulator being deterministic), and every frozen suite
passes: `clvl10` 18/20, `reach_dl8` 17/20, `clvl5`, `reach_dl5`, `reach_dl2`,
`reach_clvl2` and `enter_dungeon` 20/20.

Goal changes on the way, at the maintainer's direction: `reach_dl10` became
`reach_dl8`, depth goals build up two levels over each depth before going
down (`clvl10` three), and the bot carries more food. Game changes found by
the M4 bot are listed in §15.4 (items 1-10: poison, paralysis, fear, store
identification, random movement, monster drops, gold pickup, VMS store
stock, item stacking, acid).

Measurement lesson: any change reshuffles about a third of the seeds, so a
40-seed A/B differs by up to about 7 characters from noise alone, and only
larger differences were acted on. Runs on fixed seeds are deterministic, so
a qualification result reproduces exactly on the same code.

Fixed after M4: a stale disk after a rebuild made every worker fail at boot
in one round, so the harness now refuses a disk whose program files differ
from the build outputs beside its symbols (`launch.check_disk`). Results now
travel from the workers on one pipe each instead of a shared queue: a worker
that died right after reporting could lose that result to the queue's feeder
thread, or hang the other workers on the queue's lock (the flaky
`RunSeedsTest`).

### 15.7 M4 lessons

What moved the goals, roughly in order of effect:

1. **Word of Recall as the way home.** Most late deaths were characters
   stuck on a level (sealed pockets, missed stairs) until they starved, and
   most of them had never owned a scroll. Buying it at the Alchemist before
   Temple potions, and reading it after 2,000 steps without progress,
   was the largest single gain (rounds 82, 91).
2. **Gear and readiness.** Characters reached Green Nagas on DL5 with the
   starting Dagger and AC 4. Building up first (two levels over each depth,
   three for `clvl10`) and buying the best affordable weapon and armour
   turned fights the bot could not win into ones it could.
3. **Getting unstuck.** Trace-driven fixes for specific stuck states, each
   general once found: a weak stationary creature blocking the only exit or
   hiding the search spot beside a secret door; a stuck door given up on
   after 11 tries; dark floor the game forgets; an explore target that
   flickered as the torch moved.
4. **Not walking back into danger.** Creeping Coins killed by attrition: the
   bot walked away, then explore led it straight back. Remembering where
   slow creatures were (they vanish beyond the torch's one square), leaving
   by the stairs when a crowd is beside them, and killing an adjacent
   Floating Eye ended most of those deaths.
5. **Perception bugs.** One Orc Shaman made every Orc a caster (judge by
   kind, not glyph); a visible Floating Eye made an unseen caster's attacks
   look accounted for; a look past an identified item named the item
   instead of the mushroom patch behind it.
6. **Game fidelity.** The bot exposed ten game deviations from VMS Moria
   (§15.4). Each was a real bug; acid in particular made nagas twice as
   dangerous as upstream.

What did not work:

- **Avoiding a strong creature by walking away** (nagas): explore led the
  bot back to it, and naga deaths rose. Leaving the level worked better.
- **Tuning thresholds** (retreat HP, toughness share, monster-lore armour,
  memory lengths, dive margin by one): every change landed within the noise.
- **Digging out of sealed pockets:** granite rarely yields to a weapon, and
  the bot cannot tell which wall to dig.
- **Fleeing every creature the lore calls strong, for a diver:** almost
  everything at depth is, and running halved `reach_dl10`.

Method:

- **Replay the failing seed, read the trace, fix what it shows.** Runs on
  fixed seeds are deterministic, so a replay reaches the exact moment of
  failure. Nearly every gain came from this; almost no parameter change did.
- **Treat 40-seed A/B differences under about 7 as noise.** Any change
  reshuffles about a third of the seeds' dungeons and fights.
- **Check whether a rule can fire at all.** One round changed nothing,
  death for death, because the new recall rule needed a scroll that the
  stuck characters never had.
- **Rebuild the disk image after `make test`.** The gates rebuild the C64
  program but not the disk, and a mismatched disk fails every worker at boot.
- **Mutation-check every new bot test** (remove the rule; the test must
  fail): several first drafts passed without exercising the rule at all.

## 16. M5: every race and class at M4 (planned 2026-10-24)

### 16.1 Decision

The maintainer chose this fork on 2026-10-24 over two others: pushing the
Half-Troll Warrior on toward the Balrog, or putting M4 on other platforms
first. The M4 bar is kept for every combination ("let's keep the milestone
the same"): a Gnome Mage must reach `clvl10` and `reach_dl8` on 16 of 20 seeds
like the Half-Troll Warrior. "For playability, those should all be equal but
it might require different techniques": a combination that cannot reach the
bar gets new brain technique (spells, missiles, stealth) or is reported as a
balance finding; its bar is never lowered.

**Amended 2026-10-26 (maintainer, M5b):** pure spell casters, Mages and
Priests of every race, qualify at **15/20** on both goals ("I want to make
pure spell casters (mages and priests) have a bar of 15 instead of 16").
`CLASS_BARS` in `playtest/moria_playtest/goals.py`; a `CHARACTER_BARS` entry
still decides its own combination. Every other class keeps 16/20.

**Amended 2026-10-27 (maintainer, M5f):** Mages and Priests qualify at
**10/20**, half the seeds. After 13 rounds the 6-9 HP casters (Elf, Gnome and
Halfling Mages, Gnome Priest) sat at 4-13/20 against 15, dying at level 1-2
to what VMS deals a character that small: "I think it is OK to accept them as
weaker and have a lower bar ... let's aim for a bar of *10* for mages and
priests ... as we advance to higher levels of the dungeon I would expect our
bar to continue to be lowered." Deeper goals are expected to set lower
ones. The 14 caster suites frozen at 15 were moved to 10 on 2026-10-27
("let's make all casters a bar of 10"), each with a `bar_note`.

**Amended 2026-10-27 (maintainer, M5 regression):** Gnome Priest `clvl10` is
frozen at **9/20** ("we can capture their low bars and freeze then"). The VMS
trap change re-rolled every seed's maps; with the regression's bot fixes
(Bless and Chant held when hurt, the Priest tether, the Temple when poisoned,
worm masses remembered as slow by kind) it scored 9/20 on both runs, 64 of the
other 66 suites passing at once and the Half-Elf Ranger and Rogue after the
fixes. These scores rank characters by how well the bot plays them, not how
hard a person finds them: the small casters (Halfling and Gnome Mages, the
Gnome Priest) are the hardest group, which 20 seeds cannot order within.

Why this order:

- **Race costs no bot work.** `Goal.character` already picks the race and
  class letters for the scripted chargen, and every race can be a Warrior.
  Race changes stats, hit dice, infravision, the experience penalty,
  searching and stealth: tables no run has exercised past the Half-Troll.
- **Class is where play differs.** Spells, prayers, mana, book learning,
  spell failure and missiles are large areas of game code the bot has never
  touched (the brain has no cast command today).
- **Casters help the Balrog later.** Detection, teleport and identify are
  layers a deep run needs anyway; building them for the classes first makes
  a later Balrog push easier for every class, the Warrior included.
- **The C128 finds a different class of bug.** Banking, overlay and layout
  faults are silent corruption on this codebase. The same frozen suites on
  `x128` are a regression test of all the shared code, with no brain work.

### 16.2 Stages

| Stage | Combinations | New bot work | Exit |
|---|---|---|---|
| **M5a Warrior races** | Human, Half-Elf, Elf, Halfling, Gnome, Dwarf, Half-Orc Warriors (Half-Troll is M4) | None at first: baselines with the M4 brain, then trace-driven fixes | Both goals ≥16/20 for each; frozen |
| **M5b Paladin, Priest** | Human Paladin, then Human Priest (Half-Troll until round 10, §17) | A cast layer: choose a prayer, target it, track mana, learn from books, buy books; prayers for healing, fear and light first | Both goals ≥16/20 for the Paladin, ≥15/20 for the Priest (§16.1, amended 2026-10-26); frozen. **Human and Dwarf Priest met 2026-10-26 (§17, round 55)** |
| **M5d Rogue, Ranger** | Human Rogue, Human Ranger | Missiles: buy ammunition, fire, target; stealth-aware choices; the cast layer for their spells | Both goals ≥16/20 for each; frozen. **Met 2026-10-26 (§18, round 5)** |
| **M5e Mage** | Human Mage | Spells for survival, not only utility: Magic Missile, Phase Door, detection; a fragile character's readiness | Both goals ≥15/20 (§16.1, amended 2026-10-26); frozen. **Met 2026-10-26 (§19, baseline 19 / 18)** |
| **M5f The rest** | The other 20 combinations (§12.6) | Trace-driven fixes for what fails | Both goals ≥16/20 for each (≥10/20 for Mages and Priests, §16.1 amended 2026-10-27); frozen |

**M5c deferred (maintainer, 2026-10-26):** "I don't think we should do M5c
for the c128 - that part is less interesting to me right now. Let's do M5d
and then M5e and get those main classes tested." The order is now M5d, M5e,
M5f. Within a class, Human comes first (no race adjustment), then the other
races in M5f.

**M5c moved out of M5 (maintainer, 2026-10-26):** "let's move M5c out of M5 -
it doesn't make sense just yet." The C128 backend is now its own milestone,
not scheduled (§8); M5 is met without it. The stage letters stay as they
were, so M5 has no M5c.

### 16.3 Method

M4's lessons apply (§15.7): replay the failing seed and fix what the trace
shows; treat 40-seed differences under about 7 as noise; check that a rule
can fire at all; mutation-check every new bot test. Each stage starts with a
baseline of the current brain on the qualification seeds (1001-1020, first
character, 100,000 steps), and its death clusters, like §15.1-15.2.

A difference between races or classes on the same seeds is evidence for a
game deviation, not just a weaker character: check the race or class table,
the spell, or the formula against VMS Moria before tuning the bot.

### 16.4 Maintainer decisions (2026-10-24)

The maintainer accepted all four proposals and started M5a (`/goal Proceed
with M5a`).

1. **Suite names.** The Half-Troll Warrior suites keep their names; other
   combinations add the race and class (`clvl10-human-warrior.json`, with a
   `character` field), and `--regress` runs all of them.
2. **Regression time.** The lower goals (`clvl5` and below) stay Half-Troll
   Warrior only. `--character` (`make playtest-regress CHARACTER=...`) runs
   one combination's suites. "Let's not hyperfocus on perfection here,
   let's get it working before we do that": a faster regression is later
   work.
3. **The cast layer's scope.** Only the spells and prayers the M4 goals
   need (healing, light, fear, detection, Phase Door, Magic Missile), added
   as the traces call for them, not the whole book.
4. **M5c scope** (now the C128 backend milestone, §8). The C128 backend
   changes only the harness (§12.7); a game bug it finds is fixed as a game
   change with its contract loaded, like M4's (§15.4).

Harness support: `--character` on every session mode
(`make playtest-qualify CHARACTER=human-warrior`); the names are in
`playtest/moria_playtest/goals.py` (`CHARACTERS`).


Weak-by-design combinations (maintainer decision 2026-10-24, during M5a
round 9: "it might be fair to consider that halfling and gnome are just not
appropriate for warriors"; chose "freeze at their level"): Halfling and
Gnome Warriors are a balance finding, not a bot failure. Against a Human
Warrior, the race table gives a Halfling hit die 6 (Human 10), STR -2 and
melee BTH -10, and a Gnome hit die 7 and BTH -8; their strengths (stealth,
searching, saves, bows) do nothing for a melee character. Each is frozen at
what it reliably reaches, as a regression suite with its own bar
(`goals.CHARACTER_BARS`), and M5a is met once every other Warrior race
qualifies at 16/20. They return at the full bar with a class that suits them
(Halfling Rogue, Gnome Mage).

### 16.5 M5a baseline (2026-10-24)

The M4 brain (`19bdcbf`), seeds 1001-1020, first character, 100,000 steps,
every other Warrior race (sessions `m5a-base-<goal>-<race>`):

| Race | `clvl10` | `reach_dl8` |
|---|---|---|
| Human | 13 | 10 |
| Half-Elf | 10 | 7 |
| Elf | 8 | 5 |
| Halfling | 6 | 5 |
| Gnome | 11 | 8 |
| Dwarf | 16 | 13 |
| Half-Orc | 11 | 15 |
| Half-Troll (M4) | 18 | 17 |

Moria8's race table matches Umoria's (`data_player.cpp`) exactly, so the gap
is play, not a race deviation. Deaths (141): nagas 50 (DL5, the first level a
two-level margin allows at level 7), Kobolds on DL1-2 27 (Halflings and Elves
lost even melee), traps and poison 15, Novice Priests 13, Creeping Coins 11.

### 16.6 Game changes during M5a

1. **A melee turn no longer springs the trap under the player** (2026-10-24).
   The move command ran `trap_check_at_player` after every successful
   `player_try_move`, so a Human fighting a Green Naga from a dart trap was
   hit, and drained of strength, on every swing. Pinned VMS `move_char`
   (`moria.inc`) springs a trap only through `carry` in the branch that moves
   the player; the run path already checked `player_move_relocated`. Now the
   move path does too (`core/game_loop.s`); C64 `test_main_loop.s` t49 (fails
   on the old code). A repair to the upstream rule: no ledger row.
2. **Store prices over about 500 gp were wrong for low CHR** (2026-10-24).
   `calc_chr_price` divided only the low 16 bits of the 24-bit `cost x CHR%`
   product: Mithril Chain Mail (600 gp) at CHR 8 showed 40 gp, and the haggle
   refused that offer (its floor is the base cost), so low-CHR characters
   (Gnome, Dwarf, Half-Orc, Half-Troll) could never buy it and kept Leather
   Armour. Now all 24 bits are divided (`hg_div_mul_result_24x8`,
   `core/store.s`); C64 `test_store.s` 49 (fails on the old code). Moria8's
   own formula (`base x chr_price_adj / 100`), computed correctly.
3. **Melee to-hit was halved in every corridor** (2026-10-24). The
   audited Umoria rule halves base and level to-hit against a target the
   player cannot see (`playerCalculateBaseToHit(monster.lit)`), but
   `player_attack_monster` read the target square's `FLAG_LIT` (room light),
   so a monster in torchlight in a corridor or dark room was hit at half
   skill: an Elf hit a Black Naga with about 20% of blows. It now reads the
   monster's `MF_VISIBLE` (MON-001); C64 `test_combat.s` 42 (fails on the
   old code); `docs/COMBAT_AUDIT.md` updated. Pinned VMS `py_attack` never
   halves; the Umoria rule the audit chose is kept, and following VMS is
   left to the maintainer.

### 16.7 M5a round log

Rounds run all eight races (Half-Troll to watch its frozen suites);
sums are the seven new races' 14 qualifications (baseline 138 of 280).

| Round | Change | Sum | Notes |
|---|---|---|---|
| 1 | Trap fix (§16.6 item 1); throw oil (2d6) at approaching creatures worth one, carry 7 more flasks | 134 | Kobold deaths 27 → 17, but flasks bought first at the General Store left no gold for Word of Recall: starvation 18; Half-Troll 14/15 |
| 2 | Throwing flasks only from gold the potions and scrolls leave; none at slow creatures; fight odds (turns to kill against turns to die, from the lore's HP, AC and attacks and the character's own blows) join the M4 "too strong" test | 155 | Dwarf 18/16 meets the bar; nagas 43, starvation 19, Novice Priests 16; Half-Troll 14/16 |
| 3 | Store price fix (§16.6 item 2); out of food, fight through slow creatures instead of walking away; no Word of Recall and gold for it: a town trip; the last scroll is kept for the way home | 174 | Starvation 19 → 1; Half-Orc 17 and Dwarf 16 on `clvl10`; Half-Troll 18/17 (its frozen numbers). One Human seed lost to a harness race (title-snapshot temp file shared by concurrent sessions; fixed) |
| 4 | Melee to-hit fix (§16.6 item 3) | 228 | 12 of 16 qualify: Human 18/17, Dwarf 17/19, Half-Orc 18/19, Half-Troll 20/17, and `clvl10` for Half-Elf 16, Elf 17, Halfling 17, Gnome 16. Nagas 43 → 3; `reach_dl8` short for Half-Elf 12, Elf 15, Halfling 13, Gnome 14, whose deaths are now Novice Priests and Mages on DL2-3 (12 of 30) |
| 5 | Readiness also needs maximum HP for two of the strongest spells cast at the next depth (`knowledge.spell_max`: Cause Light Wounds 3d8 from DL2) | 230 | Every `clvl10` passes; `reach_dl8` 14 for Half-Elf, Elf, Halfling, Gnome. Novice caster deaths 12 → 6; Creeping Coins 9 (walked away into a dead end and cornered) and nagas 7 lead |
| 6 | Creeping Coins fought when the fight odds are under 0.5 (walked away from otherwise) | 227 | Within noise of round 5; Gnome 16/16 now qualifies, Human, Half-Elf and Halfling `clvl10` dip to 15-14. Nagas 14, coins 9; two seeds (Halfling 1012, Human 1015) die every round to a DL1 poison gas trap at level 1 (VMS's is harsher: 2d6 at once plus 12 + 1d(damage) turns) |
| 7 | Fight odds must be under 0.6, not 1.0: at 1.0 a fight is a coin flip | 233 | 11 of 16: Human 20/17 joins Dwarf, Gnome, Half-Orc, Half-Troll; Half-Elf `clvl10` 16. Short: Elf 15/14, Half-Elf `reach_dl8` 15, Halfling 14/13. Yellow Jellies 5: a potion drunk between steps hid an A-B-A-B oscillation beside one |
| 8 | The oscillation breaker counts moves only (a potion drunk between steps hid the A-B-A-B) | 235 | 12 of 16: Elf `reach_dl8` 16, Gnome `reach_dl8` 16 and Halfling `clvl10` 17 join. Short: Elf and Gnome `clvl10` 15, Half-Elf `reach_dl8` 15, Halfling `reach_dl8` 13. Coins 12: each pile of a nest looked an easy fight alone |
| 9 | Fight odds count every adjacent attacker (a coin nest was fought one pile at a time) | 238 | 12 of 16; short at 16/20 only Elf `clvl10` 15 and Half-Elf `reach_dl8` 15 (Gnome and Halfling `reach_dl8` 15 and 14 get their own bars, §16.1). Coins 11 lead. Checking whether worm masses breed found a generator bug: no creature has `CF_BREEDER` or `CF_GROUP`, and the dragon/animal defense bits are mapped from the wrong Umoria bits (backlogged by the maintainer, `docs/BACKLOG.md`) |
| 10 | Oil at slow creatures that are costly to melee (Creeping Coins) | 238 | Identical to round 9 on every goal: the rule never fired (coins look like gold until adjacent, and deeper characters carry only the lantern's flasks); kept, as it costs nothing |

Focused rounds (maintainer direction 2026-10-24: run only the goals under
the bar, 14 workers each, then confirm everything once on the final code):

| Round | Change | Goals run | Result |
|---|---|---|---|
| F11 | Hurt beside creatures that are all slow: step away before drinking | Elf `clvl10`, Half-Elf `reach_dl8` | 16, 14 |
| F12 | Creeping Coins never fought by choice again (M4 policy; rounds 6-10 showed no gain) | same | 18, 14 |
| F13 | A treasure vein's `$` in rock is never taken for an attacker (seed 1018 attacked a wall, which takes no game time, for 85,000 steps); while only Hungry, no meal with a creature within 5 squares (seed 1012 ate with a Rattlesnake closing in) | same | 19, 15 |
| F14 | Gold for armour (1,000 or more, 5,000 steps since town) is a town trip; a piece bought but not yet worn counts as worn, so one visit fills several slots (a Half-Elf on DL5 carried 1,547 gold in AC 7) | + Gnome, Halfling `reach_dl8` | Elf 20, Half-Elf 17, Gnome 16, Halfling 16: every goal at 16/20 |

The maintainer chose to try an escape item as well; Moria8 has no Phase
Door scroll (the Alchemist omits it, `docs/FEATURE_MAP.md` lists it Missing),
so it was backlogged (`docs/BACKLOG.md`) instead.

### 16.8 M5a freeze (2026-10-25)

One run of all 14 goals on the final code (after focused round F14), first
character on seeds 1001-1020 at 100,000 steps, each frozen on reaching its bar:

| Race | `clvl10` | `reach_dl8` |
|---|---|---|
| Human | 19 | 18 |
| Half-Elf | 20 | 17 |
| Elf | 20 | 19 |
| Halfling | 15 (own bar 15, §16.1) | 16 |
| Gnome | 17 | 16 |
| Dwarf | 19 | 20 |
| Half-Orc | 20 | 19 |

From a baseline of 138 of 280 to 255. Only Halfling `clvl10` needed its
own bar (`goals.CHARACTER_BARS`); every other Halfling and Gnome goal met
16/20 once armour was bought (F14). Suites: `playtest/suites/<goal>-<race>-warrior.json`.

## 17. M5b: Paladin and Priest (from 2026-10-25)

Started by the maintainer on 2026-10-25 (`/goal proceed with M5b`), on the
game after the creature flag fix (worm masses now breed) and the Phase Door
scroll. Characters: Human Paladin, Half-Troll Priest (§16.2), both goals, the
16/20 bar.

The Priest changed after round 13 (maintainer, 2026-10-25): Human or Dwarf,
the races players most likely pick for a Priest, Human first. The
Half-Troll was the hardest Priest to start with, against §16.2's own rule
(Human first within a class): WIS -2 (more prayer failure, less mana) and
bow/throw -10. Its rounds 1-10 stay in §17.4 for comparison; the Human
Priest starts from its own baseline (round 15).

### 17.1 Harness and cast layer

- `goals.CHARACTERS` holds all 31 race/class combinations; a class's menu
  letter follows `race_class_flags` (the class menu lists only the classes a
  race allows), checked against `core/tables.s` by a test.
- The classifier knows the prayer prompts: `Mode.SPELL` stages `book`
  ("Prayer book (a-v)?", "Study which book (a-v)?"), `which` ("Pray which?
  (a-c, ESC)") and `list` (its `?` list: letter, name, mana, level).
- `playtest/moria_playtest/magic.py`: the bot reads the list once (and again
  after learning), studies with `F` after each level-up, and prays through
  `P`, the first book and the prayer's letter. A refusal that takes no turn
  ("You're not experienced enough.", "You faint from fatigue.") is not
  retried until the next level. The `pray` layer runs after `quaff`: Remove
  Fear when afraid, Cure Light or Medium Wounds below half HP (potions below
  a third), Detect Doors/Stairs once a level when the way out is lost, and
  Create Food when food is low.

### 17.2 Baseline (the M5a brain, no prayers)

| Character | `clvl10` | `reach_dl8` |
|---|---|---|
| Human Paladin | 10 | 10 |
| Half-Troll Priest | 3 | 3 |

Deaths (68): Kobolds on DL1-2 16, traps and poison 14, White Worm masses 9
(breeding since the flag fix), Creeping Coins 6.

### 17.3 Game questions surfaced

1. **Starting prayers ignore the class level.** `core/player_create.s` gives
   every Priest and Paladin prayers 0-2 (and every Mage spells 0-3) at
   creation, so a level-1 Paladin "knows" Cure Light Wounds (Paladin level
   2) and Bless (level 3), though the game refuses them until those levels.
   Upstream characters learn their first spells through the normal learning
   rules. Kept as is and recorded as a delta in `docs/FEATURE_MAP.md` §2
   ("Starting HP & Mana"), maintainer decision 2026-10-25.

### 17.4 Round log

| Round | Change | Paladin | Priest | Notes |
|---|---|---|---|---|
| base | M5a brain, no prayers | 10 / 10 | 3 / 3 | — |
| 1 | Cast layer (§17.1) | 13 / 11 | 6 / 6 | Kobolds on DL1 14 (10 of the Priest's 14 failures), nagas 10; three Paladin seeds (1005, 1015, 1017) die at level 1 to a poison gas trap (16 HP, 15 turns of poison, no cure at that level: upstream balance, §16.6) |
| 2 | Fight odds use the class's and race's melee skill (`CLASS_BTH`, `RACE_BTH`; the Warrior's made a Priest fight Kobolds it lost to) | 12 / 10 | 6 / 6 | No change |
| 3 | Three breeders in view: leave the level; breeders never hunted (a Paladin fought multiplying White Worm masses on DL1 for 3,400 steps) | 12 / 12 | 5 / 4 | Four Priests (1003, 1010, 1013, 1014) drained to death in town: `quaff` and `pray` skipped DL0, where the bot never rests |
| 4 | Heal (prayer, potion) in town too | 12 / 11 | 6 / 5 | Town deaths 4 → 0; level-1 deaths now lead (Kobolds 16: the Priest starts with gold for 3 rations, 2 torches and one potion, a Dagger, 14 HP) |
| 5 | On a staircase, one close creature the character would lose to (`lore_strong`): take the stairs up, or down when deeper is fine | 12 / 10 | 6 / 5 | Fired 147 times at Kobolds, 48 at nagas, but most Kobold fights start off the stairs. A level-1 Priest left town with 175 gold unspent (Dagger, Leather Armour): the 200 gear reserve |
| 6 | Gear reserve 40 below level 5 (`gear_reserve`) | 15 / 14 | 12 / 11 | The largest M5b gain: level-1 characters now buy a weapon and armour. A level-1 Paladin still spent 480 of its 570 gold on two Word of Recall scrolls (M4's recall-first order) |
| 7 | Early (below level 5): Weaponsmith and Armoury before the Alchemist and Temple; one Word of Recall (`recall_reserve`) | 15 / **16** | 13 / 10 | Paladin `reach_dl8` qualifies. Nagas 9 lead. A Priest sealed on DL1 starved for 54,000 steps: Detect Doors/Stairs was spent on arrival ("no up stairs seen"), before the level was explored |
| 8 | Detect Doors/Stairs only when sealed or stuck, again every 2,000 steps (`DETECT_EVERY`) | 15 / **16** | 12 / 10 | Nagas 8, level-1 Kobolds 6, traps and poison 5. A Paladin (1002) sealed on DL2 kept HP under half while starving, so the heal always came before Detect Doors/Stairs and the way out was never looked for |
| 9 | Detect Doors/Stairs before a heal when nothing is close; no heal the adjacent creatures outrun (3d3 / 4d4 against their lore damage, `HEAL_AVERAGE`) | 14 / 15 | 11 / 10 | Blue Worm masses 8 (new lead), level-1 Kobolds 6, traps and poison 5, nagas 4. Worm deaths: the stairs lay past a nest, and descend walked into it (its fallback ignores creatures) while `fight` struck each adjacent worm; the swarm regrew faster than it was cut down |
| 10 | Slow breeders are walked past like Creeping Coins (`walk_past`): hazards to route around, walked away from in contact | 11 / 9 | 8 / 7 | Reverted. Worm deaths unchanged (8), White Worm masses 5 more, two Priests out of steps (not traced; likely: walking away keeps the worms in view, which blocks resting (`SLOW_MEMORY`), and the stairs past a nest stay out of reach) |
| 11 | Paladin only (maintainer: the Paladin first, the Priest later). `descend` never falls back to a path through creatures while a breeder is in view | 14 / 15 | — | The same deaths as round 9 (fixed seeds): worms 3, traps 3, nagas 2, coins 2. Paladin 1010 stood 250 steps on one square killing Blue Worm masses as fast as they bred, every step out into contact, and drank five potions before dying there. Paladin 1002 was teleported into a pocket that Detect Doors/Stairs showed no way out of, with no Word of Recall, and starved |
| 12 | Phase Door: up to 3 bought at the Alchemist (`PHASE_RESERVE`); read when badly hurt in contact with no retreat, beside a breeder or two creatures or near death (`phase_door`) | 11 / 13 | — | 72 bought, 6 read. Six characters stopped on a game finding, `FLAG_OCCUPIED=1 ... disagrees with the monster table`, each just after a Phase Door: `eff_teleport_apply_target` set the creature flag on the player's landing tile, left stale once the player stepped off (normal steps and `trap_teleport` never flag the player). Fixed in the game (maintainer: fix now); the six C64/C128 teleport, Phase Door and Portal tests now assert the landing tile unflagged. Level-1 Kobolds 4, Novice Priests 3 |
| 13 | Round 12 again on the fixed game | 15 / 14 | — | No game findings. Worms 3 → 1. Level-1 Kobolds 5: seeds 1010 and 1011, which lived in round 11, died on DL1 after the same purchases; the Alchemist walk for Phase Door shifts the game's RNG, so their levels differ (noise, not the rule). Novice Priests 3 (DL2: 1d5 a hit nearly every turn on AC 9, then a 3d8 Cause Light Wounds), nagas 2, the level-1 gas trap 2 |
| 14 | Early (below level 5) the bot buys up to 5 flasks to throw (`OIL_EARLY`) whatever potions and Word of Recall still need: the reserve for those left level-1 characters only the lantern's flasks | **16** / 13 | — | Paladin `clvl10` qualifies. Flasks thrown 147 → 234 (hits 44 → 71). Two `reach_dl8` seeds (1005, 1013) climbed to DL1 at step ~52,500, stepped on a teleport trap within ten turns into a pocket that Detect Doors/Stairs showed no way out of, with no Word of Recall left (2 and 4 bought, all read), and starved there 10,000-20,000 steps later |
| 15 | No change: the Human Priest's baseline (§17 header), and the Paladin again | **16** / 13 | 2 / 3 (Human) | The Paladin repeats round 14 (`clvl10` qualifies again). The Human Priest dies on DL1 to Kobolds in 12 of 18 `clvl10` failures, most within 3,000 steps: 18 HP, a Flail at melee skill ~50 against AC 16, and the bot hunts Kobolds it should only meet on its terms (seed 1011: three misses in a row from 18 HP). Two flasks thrown a game: the General Store stocks Flask of Oil 2 times in 25 choices, quantity 1 (`sro_general_choice`, VMS weights), so early oil is limited by the stock, not the shopping list. Bless (Priest level 1: +5 to-hit, +2 AC for 12-23 turns) is never prayed |

Round 14's two starved `reach_dl8` Paladins (replay of seed 1005, the bot's map at step 55,000): the teleport trap put it in three rooms joined by corridors it walked to their dead ends; Detect Doors/Stairs showed a down staircase and two doors four unseen rows south, with no known way there. Tunnelling cannot help (granite needs a digging score over `randint(1200) + 80`; STR plus weapon weight is ~26). It had 1,929 gold and no Word of Recall: it had read its last one home and was walking up for food. Two of 40 characters; left for now.

| Round | Change | Paladin | Priest (Human) | Notes |
|---|---|---|---|---|
| 16 | Bless when a creature worth it (fight odds ≥ 0.25, `BLESS_ODDS`) is within 3 squares, counted 12 steps, prayed again after a failure | 15 / 12 | 2 / 2 | Bless prayed ~790 times, 268 took. No gain: Kobolds 16 of the Priest's 20 deaths. The Priest hit Kobolds 42% of the time (216 of 515) against ~66% by its skill; the Paladin 70% against ~75%. The bot buys weapons by damage alone and ignores Umoria's too-heavy penalty (weight over STR x 15 costs 3 to-hit a point, `combat_calc_melee_total_tohit_bonus`): Human Priests (ST ~10) bought a Two-Handed Sword, 20 lb |
| 17 | Melee skill counts the too-heavy penalty (`melee_skill`); weapons are bought by damage times the chance to hit AC 20 (`melee_value`, `REFERENCE_AC`) | 12 / 11 | 3 / 4 | The Priest's hit rate on Kobolds 42% → 65% (its skill predicts ~66%); it buys light weapons now. Kobolds still 14 of its 17 `clvl10` deaths. The Paladin fell two rounds running (16/13, 16/13 → 15/12 with Bless → 12/11) |
| 18 | Bless reverted (no Priest gain in round 16; it costs a Paladin a turn and mana at 35% failure); the melee-skill fix kept | **16** / 13 | 7 / 7 | The Paladin back to rounds 14-15 (two seeds differ a goal, both ways): Bless cost it. The Priest's best yet. Kobolds still 8 of its 12 `clvl10` deaths, all on DL1 inside 5,000 steps, at 12-18 HP: three after a hunt, the rest found by the Kobold while exploring, or caught retreating. The lore odds (0.57 for a Flail) say win; with 12 HP the swings decide |
| 19 | Wary below 30 max HP (`WARY_HP`): a creature in view with fight odds over 0.4 (`WARY_ODDS`) sends the bot to the stairs before contact, and is not hunted (`wary_of`) | — | — | Stopped part way and reverted: early Kobold deaths rose for both characters (16 by mid-round; the Priest's first 10 `clvl10` characters all died). A Kobold moves as fast as the player, so running from it on sight gives it free bites from behind, and the stairs are often farther than the Kobold |

Paladin `clvl10` frozen after round 19 (maintainer: the Paladin first, freeze): 16/20 on the round-18 brain, `playtest/suites/clvl10-human-paladin.json`.

| Round | Change | Paladin `reach_dl8` | Notes |
|---|---|---|---|
| 20 | `reach_dl8` readiness margin 2 → 3, as `clvl10` (DL2 at level 4, not 3): round 18's seeds 1009 and 1019 died to DL2 Novice Priests that survived under `clvl10` | 15 | 1009 and 1006 now live; 1007 dies to DL5 Blue Worms. 1019 still dies at step 4,435: at level 3 a crowd (`crowded`) took it down the stairs it stood on, and with one level of slack (`resupply`'s `too_deep`) it stayed on DL2. Kobolds on DL1 3 (1005, 1010, 1011) |
| 21 | Not ready for the depth and standing on an up staircase (where a crowd escape down arrives): go up at once, without the slack | **17** | Qualifies: 1019 now lives. Left: Kobolds on DL1 at level 1 (1005, 1010, 1011), the same three that fail `clvl10` |

Paladin `reach_dl8` frozen at 17/20 (`playtest/suites/reach_dl8-human-paladin.json`).

Prayer books (maintainer, 2026-10-25: "spell casters are bound by their books"). Round 18's Priests studied 363 times, learned 124 prayers and met "No new spells to learn" 239 times, and never bought a book: the bot only knew book a, so past level 5 it learned nothing and never prayed Cure Medium Wounds, Portal or Create Food. Now (Priest and Paladin only, `BOOK_LEVELS`): the next book is bought at the Temple first, once the class's level for its first prayer is reached (Priest 1/5/9/15, Paladin 1/9/15/29), with a town trip when one is wanted and affordable (`book_wanted`, `wants_book_trip`); the bot learns the books' prompt order from the book prompt's `?` list (pack order: a new book takes the first empty slot), studies each book until none has a new prayer, reads each book's list, and prays through the book that holds the prayer (`magic.py`).

| Round | Change | Priest (Human) `clvl10` / `reach_dl8` | Notes |
|---|---|---|---|
| 22 | Prayer books bought, studied and prayed from (above); and the book prayers used: Orb of Draining (3d6 + level, doubled on evil) at a creature worth it in line within 6 squares, Blind Creature on a creature it would lose to within 2, Chant before a fight at odds over 0.4 (`invoke`), each only with mana left for the best heal (`Magic.spare`: Bless at level 1 had spent the only heal's mana); when boxed in and badly hurt, Sanctuary with two or more beside, else a Phase Door scroll, else Portal (`phase_door`) | 9 / 6 | No book bought in 40 characters, so none of the new prayers was ever prayed. Replay (seed 1003, step 18,341): the C64 Temple shows "Holy Book of Prayers Words" (the name cut to the line), not the bare title the bot matched; and the level-5 Priest had 172 gold against 309 |
| 23 | Books matched by their shown name (`store_name`, `book_of`); a wanted book's price joins the gear reserve, and potions drop to 2 while saving for it (`CLW_SAVING`) | stopped | Books bought now, but 10 of 20 Priests a goal ran out of steps in town: a new Words of Wisdom with nothing learned from it cannot be listed ("You don't know that spell.") and the bot asked for its list again every other step. The game recounts the prayers to learn only at a level-up, from level and WIS, whatever the books (`magic_check_new_spells`): a Priest that spent its slots in book 1 learns from Words of Wisdom at its next level |
| 23b | That answer counts the book as read until a prayer is learned from it | 7 / 5 | Books bought (Words of Wisdom 19, Chants and Blessings 12); prayed Chant 186, Cure Medium Wounds 148, Sanctuary 27; no Orb of Draining, Portal or Blind Creature yet. Kobolds on DL1 at level 1-2 still 14 deaths, before any book matters. 4 `reach_dl8` out of steps on DL1-4, not yet traced |

The Dwarf Priest joins the Human (maintainer, 2026-10-25: "I want to see how it performs next to the human priest"), on the round 23b brain: WIS +1, melee skill +15, STR +2, hit die 9.

Round 23b's out-of-steps: three searched DL1 dead ends; one (1010) asked for Portal 2,500 times on DL3 (it had picked up books, and Portal was known in none the prompt offered). Now a prayer in no offered book is refused until the next level and the books are listed again; a book that appears in the list counts as owned and is studied (`book_list`, `book_wanted`).

Game fixes found by the M5b Priests (maintainer, 2026-10-25: a difference from VMS and Umoria is usually an early accident: fix it): the rockfall trap deals 2d6, not 2d8 (VMS `values.inc` "some loose rock", Umoria `{2, 6}`; a level-1 Dwarf Priest has 11 HP); every class starts with 5 Rations and 5 Wooden Torches, not 1 and 1 (VMS `player_init`, Umoria `class_base_provisions`), and torches stack with equal turns as upstream. The Cloak is in the backlog (no cloak slot yet). Bot: the kit counts (`STARTING_FOOD`, `STARTING_TORCHES`), and a Priest's first town stop while early is the Armoury.

| Round | Change | Human Priest `clvl10` / `reach_dl8` | Dwarf Priest | Notes |
|---|---|---|---|---|
| 24 | The game fixes and Armoury-first above, with round 23b's book-loop guards | 5 / 3 | 10 / 3 | Kobolds on DL1 still lead; 8 `reach_dl8` out of steps: two refueling a lantern the game had removed, one Portal loop, the rest searching DL1 dead ends |
| 25 | Search mode (`#`) while moving about with nothing in view (maintainer: "keep it on when moving about"), every character (`search_mode`); the game now ends it when a monster comes into sight, as VMS and Umoria (`monster_update_visibility_one`); a burnt-out light stays worn and a lantern is refueled, as VMS and Umoria (the game removed it: two `reach_dl8` Priests in round 24 tried to refuel a lantern that was gone for 5,000 steps each); Portal only when it can be prayed | 7 / 7 | 9 / **14** | The best Priest round: the Dwarf's `reach_dl8` is two short. Search mode on 304 times, 27 traps found before they sprang. Kobolds on DL1 still 24 deaths across the four runs: Moria8 ships 3 of upstream's 12 level-1 creatures (Kobold, White Worm mass, Floating Eye; `tools/parse_creatures.py` picked 3 "iconic" creatures a level), so DL1 has no easy prey |
| 26 | Round 25 again (stopped part way; same code) | — | — | |
| 27 | Five DL 1 creatures added to tier 1 (maintainer: "add creatures"): Giant White and Yellow Centipedes, White Icky-Thing, Large White Snake, Giant White Mouse (Umoria stats, `tools/parse_creatures.py` `ADDED_NAMES`, after tier 1's original 24 so saved indices hold; the C128 tier cache grows to `$9567`). DL 1 Kobolds: 1 in 3 creature picks before, 1 in 8 now | 9 / 10 | 6+ / 8 | Stopped once the result was clear. The Human's best; the Dwarf's `reach_dl8` fell 14 → 8, mostly to breeding Giant White Mice on DL1 (9 deaths by mid-round) |
| 28 | 25 more DL 1-5 creatures (maintainer: "add 25 more creatures to tier-1"): tier 1 holds 54, tier 2 gains the three DL 5 ones (35); no more breeders, nothing invisible. C128 tier cache now `$7A00-$9567`; the BBC Master no longer preloads tier 1 | 10 / 10 | 9 / 5 | The Human's best again. Breeding mice 8 deaths, Kobolds 8, Large Brown Snakes 5 (AC 35, slow). Ten Dwarf characters out of steps on DL1 at level 8-10: 46-47 max HP against DL2's readiness bar of 48 (two Cause Light Wounds at 3d8) |
| 29 | The HP readiness bar stops binding 3 levels past a depth's ready level (`READY_HP_LEVELS`) | 10 / 10 | 10 / 4 | The Dwarves now leave DL1 but hit other stalls (8 `reach_dl8` out of steps): full packs (worn-out gear the bot never drops; every purchase failed; a torch could not be worn from a stack), a sealed-in Dwarf healing while it starved, dead-end searching |
| 30 | Game: wearing from a stack with a full pack drops the replaced item at the player's feet (VMS/Umoria pack overflow). Bot: drop junk when the pack is full (`drop_junk`; burnt-out lights and replaced gear); Create Food before a heal when food is low | 10 / 10 | 10 / 7 | No clear change: deaths are still most failures. Found while reviewing: stores never stacked (each stocked item took its own slot with a count of 1), so the General Store rarely had more than one or two flasks of oil for the bot to throw |
| 31 | Game: stores stack as Umoria (`storeCarryItem`/`storeDestroyItem`/`inventoryTakeOneItem`): stock joins identical stacks up to 24, buying takes one, sales join at the next restock; restock moves to the chest overlay on C128, Plus/4 and Atari (maintainer: "I don't want the load, but let's do it for now"). Bot: store rows with a count | 11 / 9 | 13 / 14 | The Dwarf's best so far. A death census of rounds 28-31 (131 Priest deaths): 107 on DL1, 58 at character level 1; last attackers Kobold 31, Giant White Mouse 30, Large Brown Snake 16, Giant White Centipede 11. First-visit purchases barely changed (about 3 food and 1 oil a run): the Armoury takes the gold, not the store's stock |
| 32 | Game: breeding follows VMS/Umoria (MON-016): with n creatures in its 3x3 square, itself included, a breeder multiplies when n < 4 and randint(7n) = 1, and a further 1 in 7 while the player rests; it was a flat 1 in 12 with no crowding or rest rule | — | — | Stopped after 10 runs (all deaths) for round 33 |
| 33 | Round 32's breeding rule, and creatures act only within their alert radius or in view, awake or asleep (MON-017; maintainer: "definitely should not breed when the player isn't around"); before, an awake creature acted anywhere on the level | 11 / 9 | 8 / 7 | Not a valid measure: 10 runs hung (C64 code corruption, below). Found: on the C64, Plus/4 and Atari, `item_spawn_level` placed nest gold with `random_floor_in_room`, a dungeon-generation overlay routine, after `pick_item_type` had loaded the chest overlay into the `$E000` window, so it ran whatever bytes the chest overlay's REU slot held at `$EBC7`; tonight's modal-misc changes put text there, a gold pile went to (0, 51), off the map, and its `FLAG_HAS_ITEM` write turned a `bne` in `render_single_tile` into a JAM opcode. `tramp_spawn_nest_gold` now loads the dungeon-generation overlay first, as the Apple IIe and CX16 trampolines did |
| 34 | Game: the creature bash follows VMS `bash` (DEX blows / 1.5, `STR/6 + 25` to-hit, the shield's dice, stun 2-3 turns after a surviving hit, off-balance `randint(140) > DEX` for 1-3 turns); shields carry VMS's dice. Bot: reroll the stats, as a player does, until the class's main stat is at least 17 (or 2 below the race/class best) and CON at least its middle value, at most 50 rolls (`roll_good`; maintainer: "I like the general policy - but make sure that would work"); every race/class passes at least 1 roll in 30 | 15 / 9 | 14 / 8 | Round 34 ran a few minutes with the reroll not reading the roll screen (`STR:15 (15)` has no space after the colon) and was restarted as 34b. No hangs. Human `reach_dl8`: 4 deaths on DL1 at level 1-2, 7 on DL4-6 at level 7-10 (Novice Warriors 3). Dwarf `reach_dl8`: 8 out of steps at level 8-10 on DL1-6: food (191 town trips for 1-3 rations each in seed 1004) and the stair-scum's nearest staircase (93 climbs from DL2) |
| 35 | Bot: an exhausted level is left by a known down staircase when the character is ready for more depth (`stair_scum`); a caster who can pray Create Food does not climb for food (`Magic.feeds`, `needs_resupply`) | 15 / 10 | 14 / 8 | No change: on DL1-2 the food reserve kept `deeper_ok` false, so the stair change never applied (stair-scum still climbed ~250 times a run). Human deep deaths (DL4-6, level 7-10, Novice Warriors and nagas): the Priests carried Words of Wisdom but every study went to the Beginners Handbook's leftovers, so they fought praying Cure Light Wounds only |
| 36 | Game: the store turnover sells one item of a stack at a time, as VMS `store_destroy(..., true)` (food stacks build up; Umoria's `randint(count)` emptied them); bot: DL1-2 trips keep one ration of food reserve, not two; study the latest prayer book first (Cure Medium Wounds, Portal). Search mode stays on while exploring though each move then costs two turns of food: it is there to find traps before they are walked into (maintainer, 2026-10-26: "the point of having search on all the time is to avoid trap deaths") | — | — | Stopped after a few minutes: nearly every Priest sat on DL1 at level 3-4 |
| 36b | Round 36, and the bot's maximum-HP readiness bar (two of a depth's strongest spells at their maximum: 48 HP for DL2, so level-4 Priests with 26-30 HP waited for level 6-7) is gone; readiness is character level against depth (`ready_level`). Maintainer: "that's your made up rule, doesn't make sense" | 9 / 12 | 9 / 14 | `reach_dl8` up from 10 and 8; `clvl10` down, 10 deaths each: about half at level 1-3 on DL1 (Kobolds, snakes, centipedes; a level-1 Priest kept 3 flasks for its lantern and threw none, and never threw at an adjacent foe), the rest at level 7-9 on DL4-6 |
| 37 | Bot: a flask is thrown at an adjacent creature worth one when the character's melee (blows x dice) is under a flask's 2d6 average (`melee_weak`); a lantern keeps 1 flask, not 3 (`LANTERN_OIL`); early, with the kit's torches, no lantern is bought (the gold goes on flasks) | 9 / 9 | 7 / 10 | Worse on all four: about 20 flasks thrown a run, town trips 47 -> 88 a run (food money went on oil: "0 food left" climbs), early deaths not fewer. All three reverted |
| 38 | Round 36b's bot, and `clvl10` readiness four levels over each depth (was three): it hunts and fights at every depth, and in round 36b it died at twice `reach_dl8`'s rate (10 against 5-6) | 11 / 12 | 13 / 14 | `clvl10` up from 9 and 9; kept |
| 39 | Bot: at the Armoury, while the starting Dagger is wielded and the Weaponsmith not yet visited, a weapon's price (`WEAPON_GOLD_EARLY` 60, a Mace) stays out of the armour budget: 13 of 15 deaths at level 1-3 in round 36b still held the Dagger | 10 / 8 | 11 / 11 | No weapon bought all the same (14 of 17 early deaths held the Dagger): the General Store came before the Weaponsmith and spent the money |
| 40 | Round 39, and with the starting Dagger the Weaponsmith comes straight after the Armoury, before the General Store | 9 / 11 | 18 / 11 | Dwarf `clvl10` passes. Still only 17 of 80 bought a weapon (16 deaths at level 1-3). Monster to-hit checked against Umoria `playerTestAttackHits` (60 + level x 3 for every class): matches |
| 41 | Round 40, and round 37's oil rules for the early levels only (below level 5): a flask at an adjacent foe when the weapon does less than a flask's 2d6, and the lantern keeps one flask, not three. Round 37 had the fewest deaths at level 1-3 (12 against 15-17) but drained gold and food later | 13 / 9 | 15 / 14 | 17 deaths at level 1-3: round 37's 12 was noise. About four runs a suite die at level 1-2 on DL1, the whole failure budget of a 16/20 bar |
| 42 | Round 41, a weapon allowance of 110 gold at the Armoury while the Dagger is wielded (60 bought nothing: 63 of 80 kept the Dagger), and `shun`: below level 5, a creature the lore calls too strong (`lore_strong`, a level-1 Priest against a Kobold) is not met: from a staircase take it, else walk to a staircase nearer than the creature | 12 / 13 | 15 / 11 | 19 deaths at level 1-3; a weapon in 31 of 80. `shun` seldom fires: most early killers step out of the dark next to the player (a torch lights only the 3x3 around it, as in Umoria and VMS) |
| 43 | Round 42's bot. Game: spell failure, maximum mana and spells allowed use upstream's `stat_adj` (Umoria `playerStatAdjustmentWisdomIntelligence`, VMS `wis_adj`): failure falls by 3 x (adj - 1) (was 0-3, with 18/xx as 18) and no +20% while fainting from hunger; mana is Umoria's `newMana` + 1 (a level-1 Priest with WIS 18 has 2, not 9; level 10 with 18/50, 21 not 88). Round 42's level-1 Priests failed 1 Cure Light Wounds in 5 beside a Kobold | 13 / 11 | 13 / 13 | 14 deaths at level 1-3 (19 in round 42). Five runs spent their budget at level 9-10 on DL1-2, all in the dark: an empty light was worn (a burnt-out torch, or an old empty lantern beside a new one), the game never says "gone out" for an empty one, and Moria8 showed an unidentified light's fuel nowhere. Blind, the bot searched walls for 44,000 steps or starved on the way up |
| 44 | Game: a light's fuel shows identified or not, as upstream (VMS "with %P5 turns of light", Umoria `itemDescription`). Bot: wear the torch or lantern with the most turns (never an empty torch), and read the fuel of a light put on from "You are wearing ... (N turns)": an empty one is dark (refuel, or another torch) | 11 / 11 | 13 / 11 | 14 deaths at level 1-3 again. Five budget runs still went dark: "You are wearing a Wooden Torch (27 turns)." runs past 40 columns and the game drops the fuel, so a 27-charge torch was taken for a new one and the spares counted were burnt out; dark, the bot went 60 times between DL1 and DL2 for an up staircase it could not see |
| 45 | Bot: the fuel of the light picked (its pack row) when the wear message drops it, and the spare torches recounted from the pack (34+ charges); dark with nothing to light, read Word of Recall at any depth (`lightless`); a flask beats melee by expected damage at each one's chance to hit, so a weapon too heavy for STR throws (`melee_weak`) | 11 / 7 | 13 / 13 | 12 deaths at level 1-3. 'p' casters (Novice Priest, Mage, Warrior) killed 12 at level 4-10. Five budget runs still went dark: search mode spends two turns a step and auto-rest many, so the bot's step count of a torch ran far behind, and the last one went out with no Word of Recall left |
| 46 | Bot: with a caster in view whose biggest spell (lore: Cause Light Wounds 3d8, Cause Serious Wounds 8d8, breath) is over 4/3 of HP, heal (prayer, else potion) and do not hunt (`under_spell`); the last torch is the light home (`light_low` once no spare is left, three spares bought, not two); search mode counts two turns a step | 14 / 13 | 15 / 13 | The best round of M5b: 11 deaths at level 1-3, 3 to 'p' casters (12 in round 45). Five budget runs, four of them Dwarf `reach_dl8`: explore stepped back and forth between two squares for thousands of steps (seed 1015: 5,000 at a corridor bend, the way up behind a secret door), until the light and the food ran out |
| 47 | Round 46's bot. Game: VMS base costs for every item mapped one-to-one onto an upstream template (FEATURE_MAP 8.3.1): a Potion of Cure Light Wounds 15 gp (was 50), a Flask of Oil 3 (10), the Beginners Handbook 25 (100), Words of Wisdom 100 (300), Word of Recall 150 (200), and weapons and armour dearer (Chain Mail 530, was 80; Long Sword 300, was 60). Bot: its price constants to match (`CLW_GOLD` 20, `RECALL_GOLD` 190, `OIL_GOLD` 3, `BOOK_GOLD`) | 12 / 9 | 13 / 14 | 13 deaths at level 1 (8 in round 46): at VMS prices armour and a weapon left a level-1 Priest a lantern and one flask. A level-9 Dwarf starved in town: the ration was refused for a full pack, and the visit ended there |
| 48 | Round 47, and explore's ping-pong guard: eight explore steps between two squares mark their frontier dead, so search takes over (`EXPLORE_PINGPONG`); a pack full at a store is dropped from, then the General Store is visited again; early, no lantern while the kit's torches last, and ten flasks to throw, not five (`OIL_EARLY`) | 11 / 10 | 14 / 14 | Two budget runs (five in rounds 46-47). Kobolds killed 11, most on the first trip with one flask or none: the General Store stocked one flask at a time. Two Priests died in town to a Battle-Scarred Veteran and a Mean-Looking Mercenary, fought to the end |
| 49 | Game: a store stocks the VMS template's number (5 rations, torches and flasks; 3 Word of Recall; 2 Cure Light Wounds, Phase Door and a few more; `sro_stock_qty`), not one of each. Bot: hurt beside a town creature, walk to the stairs down (`town_escape`) | 11 / 10 | 11 / 14 | 21 deaths at level 1-3 (14), 16 of them at level 1, mostly Kobolds. Point-blank flasks: round 45's `melee_weak` scored a flask with the melee skill, but a throw takes three quarters of the missile skill (a Dwarf's +15 is melee only), so Dwarf Priests threw where a Mace hit harder; and five rations a stocking bought a level-1 character 15 |
| 50 | Bot: `melee_weak` at a throw's skill (3/4 of the missile skill, `CLASS_BTHB`); below level 5 at most eight rations (`FOOD_EARLY_MAX`) | 13 / 11 | 15 / 14 | 15 deaths at level 1-3 (21). A level-5 Human Priest hit 66 times in 377 swings: a store screen shows no stats, so the Weaponsmith pick assumed STR 10, and a Morningstar too heavy for the character looked fine |
| 51 | Bot: the stats last read from the status lines at a store, not STR and DEX 10 (`last_stats`) | 16 / 14 | 15 / 16 | Human `clvl10` and Dwarf `reach_dl8` pass. No budget runs. 14 deaths at level 1-3: Kobolds 7, and traps: a level-1 Priest crushed by a rockfall that stayed a trap (VMS and Umoria turn it to rubble) |
| 52 | Round 51's bot. Game: a sprung rockfall trap becomes rubble and leaves the trap table (VMS `pusht(tptr); place_rubble(y, x)`) | 16 / 14 | 14 / 15 | The same seeds die at level 1 round after round (Human 1002, 1008, 1016, 1018; Dwarf 1001, 1002, 1005), Kobolds 7: seed 1008 fought at 6 of 12 HP with four potions, under `QUAFF_HP`'s 3.6, and the next bite (1d6) killed it |
| 53 | Bot: within one turn's worst melee from the creatures beside it (the lore's dice at their maximum), heal: a prayer, else a potion (`under_blow`) | 15 / 13 | 17 / 15 | 7 deaths at level 1-3 (13): Dwarf `clvl10` passes. Mid deaths lead now: DL5 Green Nagas 4, fought from full HP because every step to the stairs ran into contact, and Novice Mages 3 |
| 54 | Bot: an outmatched creature in contact (`outmatched`: a naga) is left by Phase Door at any HP, before the fight | 14 / 16 | 18 / 16 | Bars from this round: 15/20 for Priests (§16.1, amended 2026-10-26). Three of four pass; Human `reach_dl8` up from 13 with no naga deaths. Human `clvl10` misses by one: DL2 Novice Mages, the same three seeds as round 53 (one cast took 20 of 42 HP; two casts in one step did 31) |
| 55 | Bot: the spell threat in view sums every caster, not the strongest one (`spell_threat`) | 17 / 15 | 17 / 17 | **All four meet the Priest bar (15/20).** Frozen from a `--freeze` run of the same code (round 55f: the same 17 / 15 / 17 / 17): `playtest/suites/{clvl10,reach_dl8}-{human,dwarf}-priest.json`. Gates: `make -j7 -O test` passed (the Apple IIe, CX16, Atari and BBC runtime suites skipped: no ROM paths set); `make test128` 128/129, the real-boot diagnostic build 9 bytes over its startup overlay from the level-1 mana table, fixed (stat bands) and `real_boot_crash_harness` passes. **M5b Priest met 2026-10-26** |

## 18. M5d: Rogue and Ranger (from 2026-10-26)

Started by the maintainer on 2026-10-26 (`/goal M5d`), after M5b, with M5c
deferred (§16.2). Characters: Human Rogue, Human Ranger, both goals, the
16/20 bar.

Class data checked against Umoria `data_player.cpp` before the baseline, and
all match: the class table (hit die, disarm, search, stealth, FOS, BTH, BTHB,
save, XP factor), per-level adjustments, the Mage-book spell levels, mana and
fail rates for both classes (Rogue spells from level 5, Ranger from 3), and
no starting spells or mana. The starting kit differs only by the recorded
delta (`docs/FEATURE_MAP.md`, "Starting Weapons & Armor"): with no cloak
slot, every class wears Soft Leather Armor in place of the Cloak.

### 18.1 Baseline (the M5b brain)

| Character | `clvl10` | `reach_dl8` |
|---|---|---|
| Human Rogue | 0 | 0 |
| Human Ranger | 0 | 0 |

Every character ran out its 100,000 steps on DL1. Each reached its class's
first spell level (Ranger 3, Rogue 5), studied, and met the Mage-book
"Study" list: Mage-book casters choose the spell they learn
(`item_gain_spell`, `core/player_gain_spell_impl.s`), where the game picks a
prayer at random. The bot did not know that screen (an `unknown_prompt`
finding per character) and then stalled. The M5b cast layer knew prayers
only; the list title it expected ("Magic Book") is "Mage Book" in the game.

### 18.2 Game questions surfaced

1. **Firing a launcher is far weaker than VMS** (`core/ranged_fire.s`
   against VMS `moria.inc` `throw_object`, 3163-3360): no launcher damage
   bonus (VMS +2 Sling, Short Bow and Light Crossbow; +3 Long Bow; +4
   Composite Bow and Heavy Crossbow), one range of 19 for every launcher
   (VMS 20-35), no to-hit penalty for distance, no critical hits, and
   ammunition always destroyed (VMS drops a missed shot near the target 9
   times in 10). Umoria multiplies the damage (x2-x4) where VMS adds.
   `docs/FEATURE_MAP.md` calls VMS and Umoria identical here and describes
   Moria8 bonuses the code does not have. **Fixed 2026-10-26** (maintainer:
   "usually i prefer vms unless umoria was improving/fixing something" ...
   "go with recommendations"): VMS for range, the distance penalty,
   critical hits and a missed shot landing; Umoria's multiplier for damage,
   a fix its source states (MON-018 in `docs/MONSTER_STATE_CONTRACT.md`,
   `docs/FEATURE_MAP.md` "Ranged Weapon Fire"). The maintainer also wants the
   missing Long Bow, Composite Bow and Heavy Crossbow (VMS +3 / +4 / +4,
   Umoria x3 / x4 / x4), as a separate change after this one.

### 18.3 Round log

| Round | Change | Rogue | Ranger | Notes |
|---|---|---|---|---|
| base | M5b brain | 0 / 0 | 0 / 0 | Every character stalled on DL1 at the Study list (§18.1) |
| 1 | Bot: Mage-book casting (`m`, "Spell book", "Mage Book" list), the Study list (learn by `LEARN_ORDER`: Magic Missile, Phase Door, Cure Light Wounds, Detect Monsters), Magic Missile at a creature worth it in line, the Phase Door spell after the scroll, the Mage book's Cure Light Wounds (4d4) | 19 / 19 | 14 / 17 | Rogue passes both. Ranger `clvl10` 4 budget runs: a full pack dropped "Spellbook Beginners-Magick" (`KEEP_PREFIXES` knew only "Holy Book"), then every cast found "You have nothing there." with no turn passing and was asked again (56,018 times on seed 1007). 2 deaths at level 1 on DL1 |
| 2 | Bot: spellbooks kept when dropping junk ("Spellbook" in `KEEP_PREFIXES`); "You have nothing there." on a cast or study refuses it until the next level | 19 / 20 | 18 / 17 | **All four meet the 16/20 bar.** 6 deaths, all at level 1-3 on DL1-2 (Ranger seeds 1006 and 1018 die at the same steps in both goals). No budget runs |
| 3 | Game: fired missiles follow VMS, damage Umoria's multiplier (MON-018, §18.2). Bot: a Rogue or Ranger buys the best launcher it can (Light Crossbow, Short Bow, Sling) and 20 shots, wields it as a creature approaches in line 3 or more squares off, fires from 2 to 8, wields the melee weapon again beside a creature (no swap command: a turn each way), keeps the launcher and ammunition when dropping junk, and collects missed shots | 18 / 20 | 18 / 14 | Ranger `reach_dl8` misses. Few shots fired (56 across 20 Rangers): every launcher came with about one shot. Stores stocked ammunition one at a time, where VMS gives every missile stack 7d6 (`misc.inc` `magic_treasure`, stores too); dungeon stacks were 5-10 |
| 4 | Game: ammunition stocked 24 at a time (VMS 7d6 averaged at Umoria's store cap; the C64 town overlay has no room for the roll) and dungeon stacks 7d6 (`magic_treasure`) | 19 / 18 | 14 / 14 | Launchers fire now (216-389 shots a run, a bit over half hitting). Ranger misses both: 9 deaths on DL1 at level 2-4, most to Kobolds, four of them casting Magic Missile at 1-9 HP beside the Kobold (a third of the casts failing) while holding Phase Door: `invoke` comes before `retreat` and `phase_door` |
| 5 | Bot: no Magic Missile below `RETREAT_HP` with a creature beside (the escapes first) | 19 / 18 | 17 / 17 | **All four meet the bar with launchers in use.** 9 deaths, 6 of them at level 1-2 on DL1. Frozen from a `--freeze` run of the same code (round 5f: the same 19 / 18 / 17 / 17): `playtest/suites/{clvl10,reach_dl8}-human-{rogue,ranger}.json`. **M5d met 2026-10-26** |

Not built at the freeze (maintainer, 2026-10-26: "let's freeze and we'll
come back to the launchers"): the Long Bow, Composite Bow and Heavy Crossbow,
added after it as item IDs 137-139 once shared call helpers freed the bytes
(the bot buys and fires them; the frozen suites predate them); letting sleeping creatures
lie, since a player (and the bot) cannot see sleep state; and Detect
Monsters. Also found: Moria8 has no `x` weapon swap (VMS has one), and
throwing differs from VMS (a thrown item always lands, STR adds damage, no
distance penalty).

## 19. M5e: Mage (from 2026-10-26)

Started by the maintainer on 2026-10-26 (`/goal M5e make it so`), after M5d
and its follow-ups (VMS firing and throwing, the three missing launchers).
Character: Human Mage, both goals, the 15/20 bar for pure casters (§16.1).

The Mage's class data was checked with the Rogue and Ranger in §18 (class
table, per-level gains, the Mage-book spell table). It starts knowing
spells 0-3 (Magic Missile, Detect Monsters, Phase Door, Light Area), the
recorded starting-spell delta (§17.3), and casts through the M5d Mage-book
layer.

### 19.1 Baseline (the M5d brain, after the VMS throwing change)

| Character | `clvl10` | `reach_dl8` |
|---|---|---|
| Human Mage | 19 | 18 |

Both goals pass the 15/20 caster bar with no new bot work: the M5d
Mage-book layer (learning by `LEARN_ORDER`, Magic Missile at a creature worth
it, the Phase Door spell, Cure Light Wounds) and the M5b readiness and heal
rules carry a Mage. Three deaths, none a stall or a budget run: a level-1
Mage to a DL1 Kobold beside it while it threw oil (seed 1016, step 705), one
to a Giant Yellow Centipede on DL1 (1011), and one to a Novice Mage's spell
on DL2 after 43,741 steps (1013).

### 19.2 Freeze

Frozen from a `--freeze` run of the same code (the same 19 / 18):
`playtest/suites/{clvl10,reach_dl8}-human-mage.json`. **M5e met
2026-10-26** with no Mage-specific bot work. Two harness fixes found on the
way, neither changing a decision: the dashboard took every session's
character from its name, and names without the character at the end
(`m5e-base-clvl10`, `m5d-r1-human-rogue-clvl10`) showed as Half-Troll
Warriors; it now reads the goal and character each session records in
`summary.json` (`dashboard.session_parts`). And every junk drop was filed as
an `unknown_prompt` finding, since `expects_item_prompt` ignored the drop the
bot had asked for. Detect Monsters, which M5e had expected to need, was not
needed for the bar.


## 20. M5f: every other race (from 2026-10-26)

Started by the maintainer on 2026-10-26 (`/goal M5f make it so`): the 17
combinations without suites (§16.2), both goals, 34 suites. M5c was moved out
of M5 the same day (§16.2).

### 20.1 Baseline and the bar

The baseline (the M5e brain) froze 17 of 34 at once: every Rogue, the
Half-Elf Paladin, and most Half-Orc, Half-Troll and Half-Elf Priests. What
failed tracked starting HP, which matches VMS (`create.inc`
`mhp := con_adj + hitdie`): the 6-9 HP casters (Elf, Gnome and Halfling Mages,
Gnome Priest) died at level 1-2 on DL1, four deaths in five, to two Kobold
bites (1d6), one 2d6 trap, poison gas, or a Novice Mage's Cause Light Wounds
(3d8, VMS flags `0000089C`). After 13 rounds the maintainer lowered the
Mage and Priest bar to 10/20 (§16.1, amended 2026-10-27).

### 20.2 Game changes (VMS parity, maintainer: "fix em all")

- **Traps per level** follow VMS `randint(alloc_level)`,
  `alloc_level = clamp(dlvl/3, 2, 10)` (`generate.inc:854-866`): 1-2 to DL8,
  up to 10 from DL30. Moria8 placed `2..dlvl+2`, 1.7× VMS on DL1 and 3× on
  DL5.
- **Pits** do VMS's 2d6 (1d4 before).
- **The falling-rock message** is VMS's: "You are hit by falling rock."
- Tests: C64 `test_trap_door_destruction.s` t4-t5. The string bank fixture in
  `test_subsystems.s` was re-encoded with the new Huffman tree, as its
  comment requires.

The trap mix (6 of VMS's 18 types) was not changed: no new trap types were
wanted. The secret-door bolt case (below) was checked against VMS
`fire_bolt` and is faithful: a bolt strikes only on `fopen` squares.

### 20.3 Bot changes

Each kept change has a test that fails without it:

- **The full spell repertoire** (maintainer: "mages are only successful by
  using their full spell repertoire"): Mages buy each Mage book at the Magic
  Shop when its first spell is in reach (Magick I at level 3), learn by
  `LEARN_ORDER`, and cast the attack that kills in the fewest casts (Magic
  Missile, Stinking Cloud, Lightning, Frost and Fire Bolt, the balls), Find
  Hidden Traps/Doors on each new level and every 40 steps, Cure Poison when
  poisoned, and Teleport Self to escape. Priests gained Bless (before Chant is
  known), Find Traps and Slow or Neutralize Poison.
- **Missiles held back only when an escape will act** (`phase_due`): with
  Phase Door learned at level 1, Mages threw oil at full mana.
- **Mages rest for mana**, buy potions before armour and no weapons; Priests
  hold potion gold before armour too.
- **Nothing aimed at nothing:** a bolt or flask that reaches no creature
  unmarks the glyph (14,805 Magic Missiles at floor gold in one round), and
  no missile goes at a creature standing in a secret door.
- **A retreat runs to the stairs**, and a **caster seen or heard** whose two
  spells could kill sends the character to them.
- **Slow creatures by name:** a Large Brown Snake (speed 0) shares `'R'` at
  level 1 with the faster White Snake, so the bot traded blows with it.

Tried and removed, by A/B: a potion before an early prayer (Gnome and Elf
Priests 5 of 40 worse) and a stairs tether for fragile casters (35 against
45 of 120 on the six holdouts).

### 20.4 Tooling

The traces record the status line and the bot's potions and oil; the
dashboard became one page and is published to https://playtest.moria8.org
(§6.9); VICE can run JiffyDOS or any other ROM pair (§6.1).

### 20.5 Freeze (2026-10-27)

**M5f met 2026-10-27: 62 of 62 goals frozen**, all 31 combinations on both
goals. The Elf Mage's clvl10 froze at 12/20 (round 19). The five that
stayed below 10/20 through rounds 17-19 were frozen at their level
(maintainer decision 2026-10-27, "freeze at their level", `CHARACTER_BARS`):
Gnome Mage clvl10 8 and reach_dl8 7, Halfling Mage clvl10 8 and reach_dl8 5,
Gnome Priest reach_dl8 5, the same scores in rounds 18-21.

M5 closes when a regression of every frozen suite passes (§8, M5's exit).

## 21. M6: every port plays (planned 2026-10-27)

### 21.1 Decision

The maintainer set the priorities after M5 on 2026-10-27: first, "basic
workability for all ports" ("I'd like to be able to ship a version of the
game where I know that all of the ports are workable"); second, game
balance ("rate each race/class with a difficulty level for players to
know"); third, killing the Balrog. Platform coverage comes before feature
coverage, so M6 is the ports and M7 the features and balance.

### 21.2 What workable means

The same bot plays real games on each port. The primary set covers the four
main classes ("warrior, priest, mage, rogue are the main ones to cover for
workable"): the Half-Troll Warrior and a Human Warrior, Priest, Mage and
Rogue, on `clvl5` and `reach_dl5`, frozen per port. Paladin and Ranger are
not in it. A port too slow for 20 seeds may qualify on fewer, with the bar
as the same fraction. A frozen suite records its platform
(`clvl5-human-mage-plus4.json`); the C64's names are unchanged.

Running the same characters on another port also tests all of `core/` under
that port's banking, overlays and screen: bugs found are fixed as game
changes with their contracts loaded, as in M4 (§15.4).

### 21.3 Backends, in order

The brain, goals and recorder stay platform-neutral; a backend reads the
screen and map, sends keys, and snapshots (§12.7: extracted now, at the
second platform).

1. **Plus/4**, then **C128**: VICE's binary monitor, as the C64 (`xplus4`,
   `x128`). The C128's VDC screen, banked reads and 198×66 map need
   `docs/C128_MEMORY_CONTRACT.md`.
2. **Apple IIe, Atari 8-bit, BBC Master 128**: one MAME backend (a Lua
   plugin or the debugger), then a memory map per machine. Each port's
   `harness_smoke.py` already drives it headless. ROMs come from `A2ROMS`,
   `ATARI8ROMS` and `BBCMROMS`.
3. **Commander X16** last: `x16emu -testbench` has no snapshots or
   breakpoints.

### 21.4 Coverage map

The dashboard gains a grid of race and class down the side and the seven
platforms across, each cell's goals frozen, at the bar, below it or not run,
with a coverage count per platform and the date each cell last ran.

### 21.5 M7 and after

- **Feature coverage:** count what each run exercises (spells by name,
  items used and identified, creature kinds met and killed, trap types,
  stores, recall trips, depth), shown as a features grid with its gaps.
- **Deeper:** the first Word of Recall cycle, then `reach_dl15` and
  `clvl15`, for the mid-game (creature tiers 2-3, ego items, wands and
  staves). Bars are expected to fall with depth (maintainer, 2026-10-27).
- **Difficulty ratings:** all 31 combinations on 40 seeds to the deeper
  goals; survival, median level at death and early-death share rate each
  Easy to Very Hard, published for players. M5f already shows the spread
  (§20.1).
- **The monster compendium's tactics** (maintainer, 2026-10-27): the
  website's compendium (`docs/monsters.html`, `buildStrategy`) derives play
  advice from the same creature tables the bot's `knowledge.py` reads. In
  M7: one shared generator for the threat label, safe HP, recommended level
  and hazard flags, used by both, so the site's advice and the bot cannot
  drift and the playtest tests the advice; then the tactics the bot lacks,
  one at a time with a trace, a test and an A/B round: break line of sight
  around corners against casters first (Novice Mage and Priest spells were
  M5f's top Priest killer), then Sleep and Confusion to neutralise or
  escape, fighting breeders in a 1-tile corridor, and curing blindness or
  confusion before reading a scroll.
- **The Balrog:** the deep ladder (§12.4), the danger model and readiness
  checklists (§12.3), and the assisted track (§12.1), on the C64.


### 21.6 The port layer (from 2026-10-27)

`playtest/moria_playtest/ports.py` describes each port to the driver: its
emulator, disk and symbols, the source constants and labels the ABI table
checks (`abi.tables(port)`), its KERNAL addresses, how a crash entry is
told from banked RAM code, where the screen, colours and map are read, and
how a key is fed. `make playtest-qualify PORT=plus4` (or `c128`) plays
another port; a suite records `"port"` and is named with it
(`clvl5-human-mage-plus4.json`), and `--regress` runs one port's suites.
`make playtest-check` checks every port's ABI table against its build.

| | C64 | Plus/4 | C128 |
|---|---|---|---|
| Emulator, disk | `x64sc`, `.d64`, REU | `xplus4`, `.d64`, no REU | `x128`, `.d71` on a 1571, REU, `-80col` |
| Key feed | KERNAL buffer `$0277`/`$C6` | KERNAL buffer `$0527`/`$EF` | the game scans the matrix (no buffer): the driver stops in `input_get_key`'s or `input_get_key_fast`'s wait loop and returns the key through its `sta igk_key` exit |
| Crash entries | `$FCE2`, `$FE66` with `$01` HIRAM set | `$FFF6` with TED `$FF13` bit 0 set | `$FF3D`, `$FF05` with MMU `$D500` bits 5-4 clear |
| Screen, map | `$0400`, `$C000` | `$0C00`, `$C800` | VDC `$0000` (80 columns), Bank 1 `$4000` |
| ROMs | optional JiffyDOS pair | JiffyDOS required (`PLAYTEST_PLUS4_KERNAL`, `PLAYTEST_DOS1541`) | VICE's |

- **The Plus/4 plays under JiffyDOS** (maintainer, 2026-10-27: "definitely
  use the jiffydos kernal on plus/4, it's too slow otherwise"): with no
  REU, every overlay and tier crossing loads from the 1541. The drive ROM
  is the C64's (`JiffyDOS_C1541.bin`).
- **x128 snapshots leave out the VDC.** A restored C128 showed the VDC's
  power-on pattern, and the game reads VDC RAM back, so the driver saves the
  VDC's 64 KB beside each snapshot (`<name>.vdc`) and writes it back after
  the undump (`Port.snapshot_banks`).
- **The C128's key stop is in the wait loop, not at the entry.** Jumping
  from `input_get_key`'s entry to its exit skipped
  `c128_restore_runtime_vectors` (the MMU mode, the common-RAM map helpers,
  the VDC mode), which the game runs on every key: round m6d's 19 "hangs"
  had the PC in tables and zero page, with map/monster-table mismatches
  beside them. These were the harness's, not the game's; m6d is void.
- **Plus/4 snapshots do not replay exactly.** Restoring a mid-game Plus/4
  snapshot and feeding the recorded keys diverged from the original run
  (seed 1020 below), so a Plus/4 finding is reproduced from the seed, not
  the snapshot.

### 21.7 Plus/4 (2026-10-27)

All ten primary suites froze on the first qualification, at the C64's bars
(16/20, 10/20 for the Mage and Priest):

| | Half-Troll Warrior | Human Warrior | Human Priest | Human Mage | Human Rogue |
|---|---|---|---|---|---|
| `clvl5` | 20/20 | 19/20 | 14/20 | 14/20 | 20/20 |
| `reach_dl5` | 18/20 | 20/20 | 12/20 | 15/20 | 20/20 |

**Open finding: a JiffyDOS load fails on the Plus/4** (maintainer,
2026-10-27: noted, not fixed). Half-Troll Warrior `reach_dl5` seed 1020,
step 2141: `>` on the town's staircase loads `4.GEN`, and the KERNAL `LOAD`
returns error 4 (file not found) with ST `$43` (serial timeouts). The name
and device are right, the disk image is unchanged, the IRQ vector is the
KERNAL's own (`$CE0E`), and every earlier load in that game worked. It
fails at the same step from a fresh start; under VICE's stock Plus/4 KERNAL
and 1541 ROMs the seed reaches DL5. `level_change_generate_current` then
takes `jmp entry_main`, which on the Plus/4 runs into `restart_entry` and
the title, and the character is lost (the auditor files it as a `stack`
finding at the new character's first command). Open: whether the
transfer timeout is VICE's or the game's, and whether a failed overlay load
should retry before giving up.

### 21.8 Bigger maps (from 2026-10-27)

The four 80-column ports (C128, Apple IIe, BBC Master, Commander X16) play
Umoria's own 198x66 level, 3.4 times the C64's 80x48 (`Port.map_scale`).

- **Budgets** (maintainer, 2026-10-27: "they can be different"): a port's
  goals get the C64 budget times its map scale (`goals.for_port`):
  `reach_dl5` 68,062 steps, `clvl5` 102,094. A frozen suite records its own.
- **Reserves:** the food and light that send the bot home scale with the
  area too (`Brain.map_scale`). The first C128 round (m6a) starved 53 of its
  66 deaths, on DL1-2, with the C64's one-ration shallow reserve; scaled by
  the width alone (two rations), 4 of the next 6 (m6b): an up staircase not
  yet seen is a level's exploring away. On the 40-column ports the scale is 1
  and nothing changes.
- Other step-counted patience (`STALL_STEPS`, `STUCK_STEPS`, the search
  budget, restock waits) is left as tuned until a trace shows it binding.
- **Stairs** (maintainer, 2026-10-28: "I'd match"): levels had one up and
  two down staircases, so the way out of a 198x66 level was a long walk.
  They now carry upstream's 1..2 up and 3..4 down on every port
  (`DGN-016`, `docs/DUNGEON_GENERATION_CONTRACT.md`). Every frozen suite's
  levels change with it.
- **X16 map reads** (2026-10-28): the testbench reads a byte a command, so
  the whole map every step cost each X16 driver a full core.
  `X16Game.read_map` keeps a copy and rereads the view and the character's
  room (a lit room reaches past the screen edge), with the whole map on a
  new level, after a key that can change squares out of sight, and every 50
  steps: about six times less reading, and two seeds' 5,600 steps matched a
  whole read. An `x16emu` patched for block reads (`RQB`, `RQV`, `STB`;
  `docs/BACKLOG.md`) is used with `PLAYTEST_X16_BLOCK=1`: about 1.9 times
  the steps a second again. The default is byte reads, as a stock x16emu
  needs, until the patch is released upstream. X16 games are not
  deterministic run to run on either read path (two runs of one seed press
  different keys); the cause is not yet found.
- **Search mode off** (m6h): a monster's spell does not end search mode
  (VMS, unlike Umoria), and nor does a creature out of the light. A C128
  Warrior fled a Novice Priest at half speed for 30 steps, and Apple IIe
  Mages rested from poison searching. The bot turns it off itself when hurt
  (below `HUNT_HP`) or under attack, and does not turn it back on then.

### 21.9 BBC Master auto-rest cancelled itself (fixed 2026-10-28)

On the BBC Master, Ctrl+R armed auto-rest and the main loop cleared it before
the first rest turn, so a damaged BBC character tried to rest for its whole
budget (round m6a: clvl5 games ran out their 102,094 steps on DL1). It was
the game, on real hardware too, not the harness: OSBYTE `$79` returned
X = `$FF` (no key) and `input_run_key_held` put 0 in A, but its closing
`ply`/`plx` left Z from the caller's X, and `core/game_loop.s` branches on
the flags straight after `hal_input_any_key_held`. With X nonzero, auto-rest
and running were cancelled at once. Found with System VIA and write taps in
MAME; fixed by setting the flags from A (`cmp #0`) as every other port's
probe does. The BBC `dungeon_descend` scenario now rests hurt with Ctrl+R
and fails without the fix.

The BBC `dungeon_descend` scenario also checks tier 1 is loaded on DL1:
`MONDB1` was left off the BBC disk from 2026-10-25 (tier 1 stopped being
cached in Sideways RAM), so every DL 1-5 creature was a nameless `?` with no
glyph. Rounds m6a and m6j played on that disk and are void.

### 21.10 M6 met (2026-10-28)

**M6 met 2026-10-28: 70 of 70 goals frozen**, `clvl5` and `reach_dl5` for
the Half-Troll Warrior and a Human Warrior, Priest, Mage and Rogue on all
seven ports. The last port, the BBC Master (round m6k): Half-Troll 20 and
18, Human Warrior 20 and 20, Rogue 18 and 18, Priest 14 and 13, Mage 12
and 10 (`clvl5`, `reach_dl5`; bars 16, 10 for the Priest and Mage). The
level changes of the round (upstream stair counts, DGN-016) were followed
by a regression of every port's Human Warrior suites: 19/20 or 20/20 on
each, the C64's clvl10 and reach_dl8 too.

Game defects M6 found and fixed: the C128 tier cache overwriting the item
names (`check_c128_payloads.py` now gates the payloads), stale monster tiers
on the Apple IIe and X16 disks, the BBC Master's held-key probe (§21.9) and
its missing `MONDB1`. Port differences fixed: stair counts (DGN-016).
