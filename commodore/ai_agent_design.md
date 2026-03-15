# AI Agent Test & Training System — Design Plan

> Design document for an interactive AI system that can play Moria on the
> C64/C128 via VICE emulation, serving dual purposes: automated integration
> testing and reinforcement learning training.

---

## 1. Goals

| Goal | Description |
|------|-------------|
| **Automated integration testing** | Fuzz-test the game with thousands of random actions to find crashes, hangs, and edge cases that scripted tests miss. |
| **Regression testing** | Replay scripted action sequences to verify game behavior after code changes. |
| **AI training** | Train a reinforcement learning agent to play Moria well — navigate dungeons, fight monsters, manage resources, descend deeper. |
| **Performance benchmarking** | Measure frame/turn throughput under controlled conditions across builds. |

**Non-goals (for now):** Real-time visual streaming, multiplayer, or modifying game code to add a "bot mode." The system should work with unmodified game binaries.

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                    Training / Test Harness                │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ Gymnasium   │  │ Scripted     │  │ Fuzz / Soak      │  │
│  │ RL Env      │  │ Test Runner  │  │ Test Runner      │  │
│  └──────┬──────┘  └──────┬───────┘  └──────┬───────────┘  │
│         │                │                 │              │
│         └────────┬───────┴─────────────────┘              │
│                  │                                        │
│         ┌────────▼────────┐                               │
│         │  Game Interface  │                               │
│         │  (Observation +  │                               │
│         │   Action Layer)  │                               │
│         └────────┬────────┘                               │
│                  │                                        │
│         ┌────────▼────────┐                               │
│         │  VICE Bridge     │  TCP → localhost:6502         │
│         │  (Binary Monitor │                               │
│         │   Protocol)      │                               │
│         └────────┬────────┘                               │
└──────────────────│───────────────────────────────────────┘
                   │ TCP
         ┌─────────▼─────────┐
         │  VICE x128/x64sc  │
         │  -binarymonitor   │
         │  -warp -sound 0   │
         │  (headless)       │
         └───────────────────┘
```

### Component Summary

| Component | Language | Role |
|-----------|----------|------|
| `vice_bridge.py` | Python | Low-level TCP client for the VICE binary monitor protocol. Memory read/write, breakpoints, keystroke injection, continue/stop. |
| `memory_map.py` | Python | Maps RAM addresses to structured game state. Knows about ZP layout, map tiles, monster table, inventory. |
| `game_interface.py` | Python | High-level API: `get_state() → GameState`, `send_action(action)`, `wait_for_input_prompt()`. Hides the breakpoint/memory dance. |
| `moria_env.py` | Python | Gymnasium `Env` subclass. Wraps `game_interface` with `reset()`, `step()`, observation/action spaces, reward function. |
| `test_runner.py` | Python | Scripted and fuzz test execution. Uses `game_interface` directly. |
| `train.py` | Python | RL training loop (PPO via stable-baselines3 or CleanRL). |

---

## 3. VICE Bridge Layer

### 3.1 Connection

Launch VICE with the binary monitor enabled:

```bash
x128 -binarymonitor -binarymonitoraddress 127.0.0.1:6502 \
     -warp -sound 0 -80col \
     -virtualdev8 -fs8 commodore/c128/out \
     -autostartprgmode 1 -autostart commodore/c128/out/moria128.prg
```

Connect via TCP socket. The binary protocol is simple: 11-byte request header + body, 12-byte response header + body. All integers little-endian.

### 3.2 Protocol Commands Used

| Command | Byte | Purpose in our system |
|---------|------|-----------------------|
| Memory Get | `0x01` | Read game state from RAM (ZP, map, monster table) |
| Memory Set | `0x02` | Write to keyboard buffer, set test conditions |
| Checkpoint Set | `0x12` | Set exec breakpoint at `input_get_key` |
| Checkpoint Delete | `0x13` | Remove temporary breakpoints |
| Registers Get | `0x31` | Read PC to verify breakpoint location |
| Keyboard Feed | `0x72` | Inject PETSCII keystrokes for actions |
| Exit (Continue) | `0xaa` | Resume execution after breakpoint stop |
| Display Get | `0x84` | Capture screen framebuffer (for visual observation or debugging) |
| Ping | `0x81` | Connection health check |
| Quit | `0xbb` | Terminate VICE instance |

### 3.3 Core Interaction Loop

The fundamental cycle for each game turn:

```
1. VICE hits breakpoint at input_get_key → sends Stopped event (0x62)
2. Bridge receives Stopped event
3. Bridge reads game state via Memory Get (ZP $02-$8F, map, monsters)
4. Game Interface constructs observation, computes reward
5. Agent (or test script) selects an action
6. Bridge sends Keyboard Feed (0x72) with the PETSCII keycode
7. Bridge sends Exit/Continue (0xaa)
8. VICE resumes execution, processes the turn, loops back to input_get_key
9. Repeat from step 1
```

### 3.4 Breakpoint Strategy

**Primary breakpoint:** Set an exec breakpoint at the address of `input_get_key` (extracted from the `.vs` symbol file after assembly). This is where the game blocks waiting for player input — the natural synchronization point.

**Death detection:** Set a secondary breakpoint at the death handler entry point (where `zp_game_flags` bit 0 is set). Alternatively, poll `zp_game_flags` on each turn.

**Hang detection:** If no Stopped event arrives within N seconds after Continue, assume a hang. Kill the VICE process, log the action history, report the bug.

### 3.5 Symbol File Integration

After each build, parse the KickAssembler `.vs` symbol file to extract addresses:

```python
# Key symbols to extract:
SYMBOLS = {
    'input_get_key':    None,  # Primary breakpoint
    'game_loop':        None,  # Game loop entry
    'test_pass':        None,  # Test pass marker (for test mode)
    'player_data':      None,  # Player struct base
    'mon_x':            None,  # Monster position arrays
    'mon_y':            None,
    'mon_type':         None,
    'mon_hp_lo':        None,
    'mon_hp_hi':        None,
    'mon_flags':        None,
}
```

This makes the bridge resilient to code changes that shift addresses.

### 3.6 Existing Python Libraries

**pyvicemon** — Python library for the VICE binary monitor. Provides `read_memory()`, `write_memory()`, `set_breakpoint()`, `wait_for_debugger_event()`. Could be used as-is or as reference for our own implementation.

**Decision:** Write a minimal custom bridge (~200 lines) rather than depending on pyvicemon. The protocol is simple, and we need tight control over async event handling and timeout behavior. Use pyvicemon as reference.

---

## 4. Game State Observation

### 4.1 Memory Map for State Extraction

All addresses below are for the C128 build. The C64 build uses the same ZP layout; only map/monster base addresses differ.

#### Zero Page — Player State (read via Memory Get, bank 0)

| Address | ZP Label | Field | Type |
|---------|----------|-------|------|
| `$2B` | `zp_player_x` | Player map X (0–79) | u8 |
| `$2C` | `zp_player_y` | Player map Y (0–47) | u8 |
| `$2D-$2E` | `zp_player_hp` | Current HP | u16 LE |
| `$2F-$30` | `zp_player_mhp` | Max HP | u16 LE |
| `$31` | `zp_player_mp` | Current mana | u8 |
| `$32` | `zp_player_mmp` | Max mana | u8 |
| `$33` | `zp_player_lvl` | Player level (1–40) | u8 |
| `$34` | `zp_player_dlvl` | Dungeon level (0=town) | u8 |
| `$35` | `zp_player_ac` | Armor class | u8 |
| `$36-$3B` | `zp_player_str..chr` | Six ability scores | u8×6 |
| `$3C` | `zp_player_race` | Race index (0–7) | u8 |
| `$3D` | `zp_player_class` | Class index (0–5) | u8 |
| `$3E-$3F` | `zp_player_food` | Hunger counter | u16 LE |
| `$40-$41` | `zp_turn` | Turn counter | u16 LE |
| `$43` | `zp_game_flags` | Game over (bit 0), wizard (bit 1) | flags |
| `$44` | `zp_current_tier` | Loaded creature tier | u8 |
| `$47` | `zp_run_dir` | Running direction ($FF=not) | u8 |
| `$4A` | `zp_hunger_state` | 0=full, 1=hungry, 2=weak, 3=faint | u8 |
| `$4B` | `zp_light_radius` | Light radius | u8 |
| `$4D` | `zp_mon_count` | Active monster count (0–32) | u8 |
| `$4E` | `zp_item_count` | Floor item count (0–32) | u8 |

#### Status Effects ($50–$5F)

| Address | Effect | Notes |
|---------|--------|-------|
| `$50` | Poison timer | 0 = not poisoned |
| `$51` | Blindness | |
| `$52` | Confusion | |
| `$53` | Paralysis | |
| `$54` | Haste/Slow | Signed: >0 haste, <0 slow |
| `$55` | Protection | |
| `$56` | Invisibility | |
| `$57` | Infravision | |
| `$58` | Resistance flags | Bit-packed |
| `$59` | Bless | |
| `$5A` | Heroism | |
| `$5B` | Regeneration | |
| `$5C` | Free action | |
| `$5D` | See invisible | |
| `$5E` | Word of Recall | |
| `$5F` | Death source | $00=alive |

#### Dungeon Map

- **C128:** Bank 1 `$4000–$4EFF` (3,840 bytes, 80×48 tiles)
- **C64:** Bank 0 `$C000–$CEFF`

Each tile byte:
```
Bits 7-4: tile type (wall, floor, door, stairs, rubble, magma, quartz)
Bit 3:    lit
Bit 2:    visited/known
Bit 1:    treasure present
Bit 0:    creature present
```

Reading the C128 map requires specifying bank 1 in the Memory Get command.

#### Monster Table (up to 32 active monsters)

SoA arrays in main RAM. Base addresses extracted from symbol file:
- `mon_x[32]`, `mon_y[32]` — positions
- `mon_type[32]` — creature type index
- `mon_hp_lo[32]`, `mon_hp_hi[32]` — hit points
- `mon_flags[32]` — status (awake, confused, etc.)

#### Floor Items (up to 32)

- **C128:** Bank 0 `$1A00–$1AFF`
- **C64:** `$CF00–$CFFF`

8 parallel arrays × 32 entries: position, type, enchantment, quantity.

### 4.2 Observation Space (for Gymnasium)

```python
observation_space = Dict({
    # Player vitals
    'player_pos':     Box(0, 255, shape=(2,), dtype=np.uint8),    # x, y
    'player_hp':      Box(0, 65535, shape=(2,), dtype=np.uint16), # current, max
    'player_mp':      Box(0, 255, shape=(2,), dtype=np.uint8),    # current, max
    'player_level':   Discrete(41),
    'dungeon_level':  Discrete(101),
    'player_ac':      Box(0, 255, shape=(1,), dtype=np.uint8),
    'player_stats':   Box(0, 255, shape=(6,), dtype=np.uint8),    # STR-CHR
    'hunger_state':   Discrete(4),
    'light_radius':   Discrete(16),

    # Status effects (16 bytes, all timers)
    'effects':        Box(0, 255, shape=(16,), dtype=np.uint8),

    # Local map (visible tiles around player)
    # Extract a window centered on player from the full map
    'local_map':      Box(0, 255, shape=(19, 38), dtype=np.uint8),

    # Visible monsters (sorted by distance)
    # Each: (dx, dy, type, hp_lo, hp_hi, flags)
    'monsters':       Box(0, 255, shape=(8, 6), dtype=np.uint8),

    # Meta
    'turn_count':     Box(0, 65535, shape=(1,), dtype=np.uint16),
    'on_stairs':      Discrete(2),   # derived: tile under player is stairs
})
```

### 4.3 Derived Observations

Some observations are computed from raw memory, not read directly:

- **`on_stairs`**: Check tile at `(player_x, player_y)` for stair tile type
- **`visible_monsters`**: Cross-reference `mon_x/mon_y` with viewport bounds and LOS
- **`hp_percent`**: `current_hp / max_hp` — useful for reward shaping
- **`threat_level`**: Sum of visible monster HPs vs player HP — tactical assessment

---

## 5. Action Space

### 5.1 PETSCII Key Mapping

The game uses vi-keys and command letters. Each action maps to a PETSCII code
injected via Keyboard Feed (`0x72`).

```python
class Action(IntEnum):
    # Movement (8 directions + rest)
    NORTH     = 0   # 'K' ($4B)
    SOUTH     = 1   # 'J' ($4A)
    WEST      = 2   # 'H' ($48)
    EAST      = 3   # 'L' ($4C)
    NORTHWEST = 4   # 'Y' ($59)
    NORTHEAST = 5   # 'U' ($55)
    SOUTHWEST = 6   # 'B' ($42)
    SOUTHEAST = 7   # 'N' ($4E)
    REST      = 8   # '.' ($2E)

    # Stairs
    GO_DOWN   = 9   # '>' ($3E)
    GO_UP     = 10  # '<' ($3C)

    # Combat / interaction
    SEARCH    = 11  # 'S' ($53)
    OPEN      = 12  # 'O' ($4F) — then direction key
    CLOSE     = 13  # 'C' ($43) — then direction key (shifted)

    # Items
    PICKUP    = 14  # 'G' ($47)
    DROP      = 15  # 'D' ($44)
    INVENTORY = 16  # 'I' ($49)
    EQUIPMENT = 17  # 'E' ($45)
    WEAR      = 18  # 'W' ($57)
    TAKEOFF   = 19  # 'T' ($54)
    EAT       = 20  # 'E' (shifted)
    QUAFF     = 21  # 'Q' ($51)
    READ_SCR  = 22  # 'R' ($52)

    # Magic
    CAST      = 23  # 'M' ($4D) — mage spell
    PRAY      = 24  # 'P' ($50) — priest prayer

    # Ranged
    FIRE      = 25  # 'F' ($46) — then direction

    # Meta
    LOOK      = 26  # 'X' ($58) — look around
    SAVE      = 27  # shifted 'S'
```

### 5.2 Multi-Step Actions

Some commands require follow-up input (direction for Open/Close/Fire, slot letter for item use). Two approaches:

**Option A — Macro actions:** Define compound actions like `OPEN_NORTH`, `QUAFF_SLOT_A`. Simpler action space but combinatorial explosion.

**Option B — Sequential sub-actions:** After sending a command that prompts for more input, detect the sub-prompt (message line changes or another `input_get_key` breakpoint hit), then send the follow-up. More flexible, matches actual game flow.

**Recommendation:** Start with Option B. The breakpoint at `input_get_key` fires for sub-prompts too, so the same observation-action loop handles them naturally. The agent learns to send "O" then "K" (open north) as two sequential steps.

### 5.3 Simplified Action Space (for initial training)

For early RL experiments, restrict to the core survival actions:

```python
SIMPLE_ACTIONS = [
    NORTH, SOUTH, WEST, EAST,
    NORTHWEST, NORTHEAST, SOUTHWEST, SOUTHEAST,
    REST,
    GO_DOWN, GO_UP,
    SEARCH,
    PICKUP,
    EAT, QUAFF,
]
# 15 actions — movement, stairs, search, pickup, consumables
```

Expand incrementally as the agent learns basic navigation and survival.

---

## 6. Reward Function

### 6.1 Composite Reward

```python
def compute_reward(prev: GameState, curr: GameState) -> float:
    reward = 0.0

    # Exploration: reward visiting new tiles
    new_tiles = curr.visited_count - prev.visited_count
    reward += new_tiles * 0.1

    # Progress: reward descending
    depth_delta = curr.dungeon_level - prev.dungeon_level
    if depth_delta > 0:
        reward += depth_delta * 50.0

    # Combat: reward XP gains
    xp_delta = curr.xp - prev.xp
    reward += xp_delta * 0.01

    # Resources: reward gold
    gold_delta = curr.gold - prev.gold
    reward += gold_delta * 0.005

    # Survival: penalize HP loss
    hp_delta = curr.hp - prev.hp
    if hp_delta < 0:
        reward += hp_delta * 0.5  # negative

    # Death: large penalty
    if curr.is_dead:
        reward -= 500.0

    # Anti-stall: small per-turn cost to discourage idling
    reward -= 0.01

    # Level up: bonus
    if curr.player_level > prev.player_level:
        reward += 100.0

    return reward
```

### 6.2 Reward Variants for Experimentation

| Variant | Focus | Modification |
|---------|-------|-------------|
| `explore_only` | Navigation training | Only tile discovery + stairs, no combat rewards |
| `combat_heavy` | Fight training | 10× XP multiplier, death penalty reduced |
| `survival` | Cautious play | 5× HP loss penalty, healing rewarded |
| `speedrun` | Depth-first | 100× depth bonus, small turn penalty |

### 6.3 Intrinsic Motivation (Advanced)

For deeper training, add curiosity-driven rewards:
- **Novelty:** Reward encountering new monster types, item types, dungeon features
- **Competence:** Reward improving kill-to-damage ratio over time
- **Map coverage:** Reward percentage of current level explored before descending

---

## 7. Training System

### 7.1 Algorithm Selection

**PPO (Proximal Policy Optimization)** via stable-baselines3 or CleanRL:
- Handles discrete action spaces well
- Stable training with default hyperparameters
- Works with complex observation spaces (Dict)
- Good sample efficiency for turn-based games

### 7.2 Curriculum Learning

Training in stages, each building on the previous:

| Stage | Goal | Episode Length | Observation | Actions |
|-------|------|---------------|-------------|---------|
| **1. Navigate** | Find stairs, go down | 200 turns | Local map only | 8 dirs + stairs |
| **2. Survive** | Stay alive for 500 turns | 500 turns | + HP, hunger | + rest, eat |
| **3. Fight** | Kill monsters, gain XP | 1000 turns | + monsters, effects | + all movement |
| **4. Equip** | Use items effectively | 2000 turns | + inventory | + pickup, wear, quaff |
| **5. Full game** | Descend as deep as possible | 5000+ turns | Full observation | Full action space |

### 7.3 Training Infrastructure

**Parallel environments:** Run N VICE instances simultaneously, each on a different port:

```bash
# Instance 0
x128 -binarymonitor -binarymonitoraddress 127.0.0.1:6502 -warp -sound 0 ...
# Instance 1
x128 -binarymonitor -binarymonitoraddress 127.0.0.1:6503 -warp -sound 0 ...
# ...
```

stable-baselines3's `SubprocVecEnv` manages multiple environments natively.

**Speed estimate:** VICE in warp mode runs ~10-50× real-time on modern hardware. At ~60 FPS emulated, the game processes a turn in <1 frame when the AI responds instantly. Bottleneck is the TCP round-trip per turn (~1ms local). Realistic throughput: **500-2000 turns/sec per instance**. With 8 parallel instances: **4000-16000 turns/sec**.

**Checkpointing:** Save VICE snapshots (via Dump command `0x41`) at known-good states (town entrance, dungeon level 1, etc.) for fast episode resets instead of replaying character creation every time.

### 7.4 Episode Management

```python
class MoriaEnv(gymnasium.Env):
    def reset(self, seed=None):
        # Option A: Undump a saved snapshot (fast, ~100ms)
        self.bridge.undump("checkpoints/town_start.vsf")

        # Option B: Full restart (slow but tests more code paths)
        self.bridge.quit()
        self._launch_vice()
        self._wait_for_title_screen()
        self._automate_character_creation()

        return self._get_observation(), {}

    def step(self, action):
        # Wait for input_get_key breakpoint
        self.bridge.wait_for_stop(timeout=5.0)

        # Read pre-action state
        prev_state = self._read_game_state()

        # Send the action
        petscii = ACTION_TO_PETSCII[action]
        self.bridge.keyboard_feed(petscii)
        self.bridge.continue_execution()

        # Wait for next input_get_key
        self.bridge.wait_for_stop(timeout=5.0)

        # Read post-action state
        curr_state = self._read_game_state()

        # Compute reward and done
        reward = compute_reward(prev_state, curr_state)
        terminated = curr_state.is_dead
        truncated = curr_state.turn_count >= self.max_turns

        return self._get_observation(), reward, terminated, truncated, {}
```

---

## 8. Testing System

### 8.1 Fuzz Testing (Random Agent)

```python
def fuzz_test(num_episodes=100, max_turns=5000):
    """Play randomly, looking for crashes and hangs."""
    env = MoriaEnv(max_turns=max_turns)
    for ep in range(num_episodes):
        obs, _ = env.reset()
        action_log = []
        for turn in range(max_turns):
            action = env.action_space.sample()
            action_log.append(action)
            try:
                obs, reward, term, trunc, info = env.step(action)
            except TimeoutError:
                save_crash_report(ep, turn, action_log, "HANG")
                break
            if term or trunc:
                break
        print(f"Episode {ep}: {turn} turns, dlvl={info['dungeon_level']}")
```

This exercises code paths that deterministic tests never reach: unusual item combinations, edge-case monster spawns, rare dungeon layouts.

### 8.2 Scripted Regression Tests

```python
def test_descend_to_level_3():
    """Verify the game can handle 3 dungeon level transitions."""
    env = MoriaEnv()
    env.reset()
    script = [
        # Navigate to stairs (assumes known layout from snapshot)
        *[Action.SOUTH] * 5,
        *[Action.EAST] * 10,
        Action.GO_DOWN,
        # Level 2
        *[Action.SEARCH] * 3,  # find doors
        *[Action.SOUTH] * 8,
        Action.GO_DOWN,
        # Level 3
    ]
    for action in script:
        obs, reward, term, trunc, info = env.step(action)
        assert not term, f"Died on turn {info['turn']}"
    assert info['dungeon_level'] == 3
```

### 8.3 Property-Based Tests

```python
def test_hp_never_exceeds_max(num_turns=10000):
    """Invariant: current HP should never exceed max HP."""
    env = MoriaEnv()
    obs, _ = env.reset()
    for _ in range(num_turns):
        action = env.action_space.sample()
        obs, _, term, _, _ = env.step(action)
        assert obs['player_hp'][0] <= obs['player_hp'][1], \
            f"HP {obs['player_hp'][0]} > max {obs['player_hp'][1]}"
        if term:
            obs, _ = env.reset()
```

### 8.4 Soak Testing

Long-running random play to detect memory leaks, accumulating corruption, or rare crashes:

```bash
python -m moria_ai.soak --episodes 1000 --max-turns 10000 \
    --parallel 4 --report soak_results.json
```

---

## 9. Alternative Architecture: vice-libretro

### 9.1 Overview

The `vice-libretro` project provides a libretro core for VICE, including full C128 support via `vice_x128`. This could integrate with stable-retro (Farama Foundation's Gymnasium wrapper for libretro cores) for an in-process emulation path.

### 9.2 Advantages

- **In-process:** No TCP overhead. Frame-level stepping via `retro_run()`.
- **Standard API:** `retro_get_memory_data()` exposes RAM directly.
- **Proven RL pipeline:** stable-retro already handles observation/action/reward for retro games.
- **Faster:** No IPC serialization per frame.

### 9.3 Disadvantages

- **Integration work:** stable-retro doesn't ship with C64/C128 support. Need to add a new platform, write `data.json` / `scenario.json`, compile the core.
- **VDC uncertainty:** 80-column VDC output goes through a separate framebuffer. Need to verify it renders correctly through libretro's video callbacks.
- **Less flexibility:** Harder to do memory reads from arbitrary banks (C128 MMU) vs the binary monitor's bank parameter.
- **Maintenance:** Tied to libretro core updates. The binary monitor protocol is stable across VICE versions.

### 9.4 Recommendation

**Start with the binary monitor approach (Path A).** It works today with stock VICE, requires no C integration, and gives full access to C128 banking via the memspace/bank parameters. If training throughput becomes the bottleneck, evaluate the libretro path as an optimization.

---

## 10. Project Structure

```
moria8-ai/
├── README.md
├── pyproject.toml               # Dependencies: gymnasium, stable-baselines3, numpy
├── moria_ai/
│   ├── __init__.py
│   ├── vice_bridge.py           # VICE binary monitor TCP client
│   ├── memory_map.py            # RAM address → game state mapping
│   ├── symbol_loader.py         # Parse KickAssembler .vs symbol files
│   ├── game_interface.py        # High-level game state + action API
│   ├── action_map.py            # Action enum → PETSCII keycode tables
│   ├── reward.py                # Reward function variants
│   ├── moria_env.py             # Gymnasium Env wrapper
│   └── utils.py                 # VICE process management, logging
├── tests/
│   ├── test_bridge.py           # Unit tests for protocol layer
│   ├── test_memory_map.py       # Verify address mappings
│   ├── test_fuzz.py             # Random agent fuzz tests
│   ├── test_regression.py       # Scripted scenario tests
│   ├── test_invariants.py       # Property-based game invariants
│   └── conftest.py              # Shared fixtures (VICE launch, env setup)
├── training/
│   ├── train_ppo.py             # PPO training script
│   ├── curriculum.py            # Stage definitions and progression
│   ├── hyperparams.yaml         # Tunable parameters
│   └── evaluate.py              # Run trained model, report stats
├── checkpoints/                 # VICE snapshots for fast resets
│   ├── town_start.vsf
│   ├── dungeon_l1.vsf
│   └── dungeon_l5.vsf
├── scripts/
│   ├── launch_vice.sh           # Start VICE with correct flags
│   ├── launch_parallel.sh       # Start N VICE instances
│   └── extract_symbols.py       # Build-time symbol extraction
└── logs/
    └── crash_reports/           # Fuzz test crash logs
```

---

## 11. Implementation Roadmap

### Phase 1 — Foundation (vice_bridge + game_interface)

- [ ] Implement `vice_bridge.py` — TCP connection, binary protocol encode/decode
- [ ] Implement request/response for: Memory Get, Memory Set, Checkpoint Set/Delete, Keyboard Feed, Exit, Ping, Quit
- [ ] Handle async Stopped/Resumed events
- [ ] Timeout and hang detection
- [ ] Implement `symbol_loader.py` — parse `.vs` files for breakpoint addresses
- [ ] Implement `memory_map.py` — ZP player state, map tiles, monster table
- [ ] Implement `game_interface.py` — `wait_for_input()`, `read_state()`, `send_action()`
- [ ] Write unit tests against a live VICE instance
- [ ] **Milestone:** Can read game state and inject actions programmatically

### Phase 2 — Testing Harness

- [ ] Implement fuzz test runner (random agent with crash detection)
- [ ] Implement scripted test runner with action sequences
- [ ] Add property-based invariant checks (HP≤maxHP, position in bounds, etc.)
- [ ] VICE process lifecycle management (launch, restart on crash, cleanup)
- [ ] Crash report logging (action history, last game state, VICE screenshot)
- [ ] **Milestone:** Can run 1000 random episodes without the harness itself failing

### Phase 3 — Gymnasium Environment

- [ ] Implement `moria_env.py` — observation/action spaces, step/reset
- [ ] Implement reward functions (composite + variants)
- [ ] Add VICE snapshot save/load for fast reset
- [ ] Episode truncation and turn limits
- [ ] Character creation automation (for full resets)
- [ ] Verify Gymnasium API compliance with `gymnasium.utils.env_checker`
- [ ] **Milestone:** `env.step()` / `env.reset()` work correctly for 100 episodes

### Phase 4 — Training Pipeline

- [ ] PPO training script with stable-baselines3
- [ ] Curriculum stage definitions and auto-progression
- [ ] Parallel VICE instances via SubprocVecEnv
- [ ] TensorBoard logging (reward curves, episode length, depth reached)
- [ ] Model checkpointing and evaluation
- [ ] **Milestone:** Agent learns to navigate rooms and find stairs (Stage 1)

### Phase 5 — Refinement

- [ ] Observation space tuning (what features matter?)
- [ ] Reward shaping experimentation
- [ ] Action masking (invalid actions based on context)
- [ ] Multi-step action handling for compound commands
- [ ] Human-vs-AI comparison benchmarks
- [ ] **Milestone:** Agent consistently reaches dungeon level 5+

---

## 12. C128-Specific Considerations

### 12.1 Bank Switching for Map Access

The C128 stores the dungeon map in Bank 1 (`$4000–$4EFF`). The VICE binary monitor's Memory Get command supports a bank parameter:

```python
# Read map from Bank 1
map_data = bridge.memory_get(
    start=0x4000,
    end=0x4EFF,
    memspace=0x00,    # main CPU
    bank_id=1         # Bank 1
)
```

This is a key advantage of the binary monitor approach — direct bank access without needing the game to do anything special.

### 12.2 VDC Screen Capture

The C128's 80-column display uses the VDC chip with its own 16/64KB VRAM, not directly accessible from the CPU address space. For screen observation:

- **Memory approach:** Read the game state from RAM (preferred — we don't need pixels)
- **Display Get:** The binary monitor's `Display Get` (`0x84`) should capture the VDC output for debugging/visualization
- **Screen RAM via VDC registers:** Read VDC VRAM indirectly through registers `$D600/$D601` if needed

### 12.3 Input Differences

The C128 build uses direct CIA1 matrix scanning instead of KERNAL GETIN. The breakpoint address for `input_get_key` will be different between C64 and C128 builds, but the symbol file handles this automatically.

Keyboard Feed (`0x72`) injects into VICE's keyboard emulation layer, which works regardless of whether the game uses KERNAL or direct scanning. However, the C128's edge-detection debounce logic may require specific timing. Test this early.

**Fallback:** If Keyboard Feed doesn't work reliably with the C128 direct-scan input, use Memory Set to write directly to the keyboard buffer location, or use Joyport Set (`0xa2`) for movement actions.

---

## 13. Open Questions

| # | Question | Impact | Resolution Path |
|---|----------|--------|-----------------|
| 1 | Does VICE Keyboard Feed (`0x72`) work with C128 direct CIA1 scanning? | Critical — determines input injection method | Test empirically in Phase 1 |
| 2 | Can Display Get (`0x84`) capture VDC 80-col output? | Low — only needed for visual debugging | Test in Phase 1, not blocking |
| 3 | What's the actual turns/sec throughput? | Sizing — determines parallel instance count | Benchmark in Phase 1 |
| 4 | Should character creation be automated or snapshot-skipped? | Training speed vs coverage | Start with snapshots, add automation later |
| 5 | How to handle `-more-` prompts? | Agent must learn to press space, or auto-dismiss | Detect via message flags at `$18`, auto-dismiss in harness |
| 6 | Inventory/spell sub-menus: separate Env or hierarchical actions? | Action space design | Start with sequential sub-actions, evaluate |

---

## 14. Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Python | ≥3.10 | Runtime |
| gymnasium | ≥0.29 | RL environment API |
| stable-baselines3 | ≥2.0 | PPO implementation |
| numpy | ≥1.24 | Array operations |
| tensorboard | ≥2.14 | Training visualization |
| VICE | ≥3.8 | C64/C128 emulator (x128 binary) |
| Kick Assembler | (project) | Assembler (for symbol file generation) |

---

## 15. Success Criteria

| Level | Criteria |
|-------|----------|
| **Bronze** | Bridge works: can read state, inject actions, play 100 random turns without crash |
| **Silver** | Fuzz testing finds at least one previously-unknown bug in the game |
| **Gold** | Trained agent consistently navigates to dungeon level 3 |
| **Platinum** | Trained agent reaches dungeon level 10 and manages inventory/combat |
| **Diamond** | Agent plays comparably to a novice human player |
