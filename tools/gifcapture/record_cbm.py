#!/usr/bin/env python3
"""Record genuine non-wizard gameplay GIFs for Commodore 64, Plus/4, and C128.

Usage:
  python3 tools/gifcapture/record_cbm.py c64      # clip 1 (boot art + chargen) + clips 2-4 (Gnome Warrior DL7)
  python3 tools/gifcapture/record_cbm.py plus4    # clips 1-4 (Half-Troll Warrior DL9)
  python3 tools/gifcapture/record_cbm.py c128     # clips 1-4 (Half-Elf Mage DL26, 80-col VDC)
  python3 tools/gifcapture/record_cbm.py all      # all three platforms

Strict rules:
- ZERO wizard mode (Ctrl+W is never invoked).
- Real Balrog Save Format V2 ($22) checkpoints via ``balrog_save.py``.
- Driven by ``playtest/moria_playtest/brain.py`` (real non-wizard AI).
- C64 clip 1 only includes boot art + title + character creation + entering town.
- All emulator scratch stays under ``build/gifcapture/{c64,plus4,c128}/``.
- Final GIFs written to ``docs/assets/moria8-{c64,plus4,c128}-gameplay-{1..4}.gif``.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, replace
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT / "build"
ASSETS = ROOT / "docs" / "assets"
WORK = Path(os.environ.get("GIFCAP_WORK", BUILD / "gifcapture"))

sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "playtest"))
sys.path.insert(0, str(ROOT / "tools"))

import balrog_save as bs  # noqa: E402
from moria_playtest import knowledge, nav  # noqa: E402
from moria_playtest.brain import Brain  # noqa: E402
from moria_playtest.game import KEY_SPACE, Mode, Observation  # noqa: E402
from moria_playtest.goals import GOALS, for_character  # noqa: E402
from moria_playtest.launch import Build  # noqa: E402
from moria_playtest.ports import C64, C128, PLUS4, Port  # noqa: E402
from moria_playtest.session import load_brain  # noqa: E402
from moria_playtest.vice import write_png  # noqa: E402
from moria_playtest.view import build_view  # noqa: E402
from moria_playtest.worker import Worker  # noqa: E402

FPS = 10
ACTION_MIN_FRAMES = 46
ACTION_MAX_FRAMES = 62

COMBAT_KEYWORDS = (
    "you hit",
    "you miss",
    "hits you",
    "misses you",
    "you cast",
    "you zap",
    "you quaff",
    "you slay",
    "you have slain",
    "dies!",
    "is destroyed",
    "welcome to level",
    "picked up",
    "open the door",
    "bash",
    "casts a spell",
    "breathes",
    "bites you",
    "claws you",
    "touches you",
    "stings you",
    "gazes at you",
    "wails",
    "you fire",
    "you shoot",
    "arrows",
    "bolts",
)


@dataclass
class PlatformConfig:
    name: str
    port: Port
    char_slug: str
    num_action_clips: int
    first_clip_num: int
    colors: int
    target_size: tuple[int, int]
    max_turns: int


PLAT_CFGS: dict[str, PlatformConfig] = {
    "c64": PlatformConfig("c64", C64, "gnome-warrior", num_action_clips=3, first_clip_num=2, colors=32, target_size=(384, 288), max_turns=700),
    "plus4": PlatformConfig("plus4", PLUS4, "half-troll-warrior", num_action_clips=4, first_clip_num=1, colors=128, target_size=(384, 288), max_turns=700),
    "c128": PlatformConfig("c128", C128, "half-elf-mage", num_action_clips=4, first_clip_num=1, colors=32, target_size=(656, 492), max_turns=1200),
}


class CustomPortBuild(Build):
    """Build wrapper allowing an overridden Port instance (e.g. stock Plus/4 ROMs)."""

    def __init__(self, base: Build, custom_port: Port) -> None:
        super().__init__(base.disk, base.prg, base.vs, base.port)
        self._custom_port = custom_port

    @property
    def target(self) -> Port:
        return self._custom_port


def make_build(port: Port) -> Build:
    base = Build.shipping(port)
    if port.name == "plus4" and (not os.environ.get("PLAYTEST_PLUS4_KERNAL") or not os.environ.get("PLAYTEST_DOS1541")):
        return CustomPortBuild(base, replace(port, required_roms=()))
    return base


class FrameRenderer:
    """Caches static ROM font & VICE palette so per-turn snapshots cost only ~1 KB read."""

    def __init__(self, game, plat: str) -> None:
        self.game = game
        self.plat = plat
        mon = game.mon
        self.pal = mon.palette(vdc=(plat == "c128"))
        if plat == "c64":
            io = mon.bank("io")
            dd00, d018 = mon.mem_get(0xDD00, 1, io)[0], mon.mem_get(0xD018, 1, io)[0]
            base, chars = (3 - (dd00 & 3)) * 0x4000, ((d018 >> 1) & 7) * 0x800
            if base in (0x0000, 0x8000) and chars in (0x1000, 0x1800):
                self.font = mon.mem_get(0xD000 + chars - 0x1000, 0x800, mon.bank("rom"))
            else:
                self.font = mon.mem_get(base + chars, 0x800, game.ram)
        elif plat == "plus4":
            self.font = mon.mem_get(0xD400, 0x400, mon.bank("rom"))
        elif plat == "c128":
            vdc = mon.bank("vdc")
            self.font = mon.mem_get(0x2000, 0x2000, vdc)
        else:
            raise ValueError(plat)

    def grab(self, obs: Observation) -> tuple[bytes, bytes, int, int]:
        mon = self.game.mon
        if self.plat == "c64":
            io = mon.bank("io")
            cols = mon.mem_get(self.game.abi.COLOR_RAM, 1000, io)
            frame, back = (c & 0x0F for c in mon.mem_get(0xD020, 2, io))
            return obs.screen, cols, frame, back
        if self.plat == "plus4":
            io = mon.bank("io")
            cols = mon.mem_get(self.game.abi.COLOR_RAM, 1000, self.game.ram)
            bg = mon.mem_get(0xFF15, 1, io)[0] & 0x7F
            bd = mon.mem_get(0xFF19, 1, io)[0] & 0x7F
            return obs.screen, cols, bd, bg
        if self.plat == "c128":
            vdc = mon.bank("vdc")
            attrs = mon.mem_get(self.game.abi.VDC_ATTRIB_BASE, 2000, vdc)
            return obs.screen, attrs, 0, 0
        raise ValueError(self.plat)

    def render_png(self, snap: tuple[bytes, bytes, int, int], out_path: Path, target_size: tuple[int, int]) -> None:
        scr, cols, border_idx, bg_idx = snap
        pal = self.pal
        font = self.font
        if self.plat == "c128":
            black = pal[0]
            lines = []
            for row in range(25):
                for y in range(8):
                    line = bytearray(b"\x00")
                    for c in range(80):
                        at = row * 80 + c
                        attr = cols[at]
                        bits = font[((scr[at] + (256 if attr & 0x80 else 0)) * 16 + y) % len(font)]
                        if attr & 0x40:
                            bits ^= 0xFF
                        fg = pal[attr & 0x0F]
                        line += b"".join(fg if bits & (0x80 >> x) else black for x in range(8))
                    lines += [bytes(line), bytes(line)]
            raw_path = out_path.with_suffix(".raw.png")
            write_png(raw_path, 640, 400, b"".join(lines))
        else:
            b = 32
            bg = pal[bg_idx]
            bd = pal[border_idx]
            edge = bd * (320 + 2 * b)
            lines = [b"\x00" + edge] * b
            for row in range(25):
                for y in range(8):
                    line = bytearray(b"\x00" + bd * b)
                    for c in range(40):
                        at = row * 40 + c
                        ch = scr[at]
                        if self.plat == "plus4":
                            fg = pal[cols[at] & 0x7F]
                            bits = font[(ch & 0x7F) * 8 + y]
                            if ch & 0x80:
                                bits ^= 0xFF
                        else:
                            fg = pal[cols[at] & 0x0F]
                            bits = font[ch * 8 + y]
                        line += b"".join(fg if bits & (0x80 >> x) else bg for x in range(8))
                    lines.append(bytes(line + bd * b))
            lines += [b"\x00" + edge] * b
            raw_path = out_path.with_suffix(".raw.png")
            write_png(raw_path, 384, 264, b"".join(lines))

        im = Image.open(raw_path).convert("RGB")
        raw_path.unlink(missing_ok=True)
        if im.size != target_size:
            tw, th = target_size
            canvas = Image.new("RGB", (tw, th), (0, 0, 0))
            canvas.paste(im, ((tw - im.width) // 2, (th - im.height) // 2))
            im = canvas
        im.save(out_path)


def load_balrog_and_recall(worker: Worker, expected_info: dict) -> Observation:
    game = worker.game
    assert game is not None
    obs = game.last
    assert obs is not None

    obs = game.press(ord("L"))
    for _ in range(15):
        if obs.mode == Mode.COMMAND:
            break
        scr = "\n".join(obs.rows)
        if "Select Slot" in scr:
            obs = game.press(ord("1"))
        elif "3) Done" in scr:
            obs = game.press(ord("3"))
        elif "Press any key" in scr or "-more-" in scr:
            obs = game.press(KEY_SPACE)
        else:
            raise RuntimeError(f"Unexpected load screen:\n{scr}")
    if obs.mode != Mode.COMMAND or obs.dlvl != 0:
        raise RuntimeError(f"Failed to load save in Town: {obs.summary()}")
    if obs.clvl != expected_info["clvl"]:
        raise RuntimeError(f"Loaded clvl {obs.clvl}, expected {expected_info['clvl']}")

    while obs.hp < obs.mhp and obs.mode in (Mode.COMMAND, Mode.DISMISS):
        obs = game.press(KEY_SPACE if obs.mode == Mode.DISMISS else ord("5"))

    obs = game.press(ord("R"))
    if obs.mode != Mode.ITEM:
        raise RuntimeError(f"Expected ITEM prompt for R, got {obs.mode}: {obs.rows[:3]}")
    obs = game.press(ord("?"))
    letter = None
    for row in obs.rows:
        m = re.search(r"([a-z])\)\s*.*Word of Recall", row, re.I)
        if m:
            letter = m.group(1).upper()
            break
    if letter is None:
        raise RuntimeError("Scroll of Word of Recall not found in pack:\n" + "\n".join(obs.rows))
    obs = game.press(ord(letter))

    target_dl = expected_info["max_dl"]
    for _ in range(100):
        if obs.dlvl > 0:
            break
        obs = game.press(KEY_SPACE if obs.mode == Mode.DISMISS else ord("5"))
    while obs.mode == Mode.DISMISS:
        obs = game.press(KEY_SPACE)
    if obs.dlvl != target_dl or obs.mode != Mode.COMMAND:
        raise RuntimeError(f"Failed Word of Recall to DL{target_dl}: {obs.summary()}")
    return obs


@dataclass
class TurnRec:
    step_idx: int
    snap: tuple[bytes, bytes, int, int]
    mode: Mode
    dlvl: int
    pos: tuple[int, int]
    hp: int
    mp: int
    creatures: int
    msg: str
    repeat: int
    score: int


def classify_turn(obs: Observation, prev_pos: tuple[int, int] | None, prev_hp: int, creatures: int, attacked: bool) -> tuple[int, int]:
    msg = (obs.rows[0] + " " + obs.rows[1]).lower()
    has_action_msg = any(k in msg for k in COMBAT_KEYWORDS)
    is_big = ("welcome to level" in msg or "you have slain" in msg or "dies!" in msg or "is destroyed" in msg)
    hp_delta = obs.hp != prev_hp
    moved = prev_pos is not None and obs.pos != prev_pos

    score = 0
    if attacked or has_action_msg or hp_delta:
        score += 16
    if is_big:
        score += 10
    if creatures > 0:
        score += min(14, 6 + creatures * 2)
    if obs.mode in (Mode.SPELL, Mode.ITEM, Mode.DIRECTION):
        score += 6
    if moved:
        score += 2
    if score == 0:
        score = -4

    if is_big:
        repeat = 6
    elif attacked or has_action_msg or hp_delta:
        repeat = 5
    elif obs.mode != Mode.COMMAND or creatures > 0:
        repeat = 3
    else:
        repeat = 2
    return repeat, score


def select_highlight_windows(
    recs: list[TurnRec],
    num_clips: int,
    min_frames: int = ACTION_MIN_FRAMES,
    max_frames: int = ACTION_MAX_FRAMES,
) -> list[tuple[int, int]]:
    """Select ``num_clips`` non-overlapping contiguous highlight segments [start, end_incl]."""
    n = len(recs)
    candidates: list[tuple[int, int, int, int, int]] = []
    for i in range(n):
        if recs[i].mode != Mode.COMMAND or recs[i].dlvl <= 0:
            continue
        frames = 0
        total_score = 0
        distinct_pos: set[tuple[int, int]] = set()
        combat_turns = 0
        creature_turns = 0
        for j in range(i, n):
            r = recs[j]
            if r.dlvl <= 0 or r.mode == Mode.DEATH or "you have died" in r.msg.lower():
                break
            frames += r.repeat
            total_score += r.score
            distinct_pos.add(r.pos)
            if r.score >= 16:
                combat_turns += 1
            if r.creatures > 0:
                creature_turns += 1
            if frames > max_frames:
                break
            if frames >= min_frames and r.mode == Mode.COMMAND:
                bonus = len(distinct_pos) * 2 + combat_turns * 8 + creature_turns * 4
                candidates.append((total_score + bonus, combat_turns, creature_turns, i, j))

    # Prefer windows with real combat + visible monsters; fallback gracefully if scarce
    for min_combat, min_creatures, min_gap in ((3, 3, 6), (2, 2, 5), (1, 1, 4), (0, 1, 3), (0, 0, 0)):
        chosen: list[tuple[int, int, int, int]] = []
        pool = [c for c in candidates if c[1] >= min_combat and c[2] >= min_creatures]
        pool.sort(key=lambda x: x[0], reverse=True)
        for score, ct, crt, s, e in pool:
            if any(not (e + min_gap < cs or s > ce + min_gap) for _, _, cs, ce in chosen):
                continue
            chosen.append((ct, crt, s, e))
            if len(chosen) == num_clips:
                chosen.sort(key=lambda x: x[2])
                for k, (rct, rcrt, rs, re_) in enumerate(chosen):
                    print(f"  window {k + 1}: turns {rs}..{re_} combat={rct} visible={rcrt}")
                return [(rs, re_) for _, _, rs, re_ in chosen]

    raise RuntimeError(f"Could not select {num_clips} highlight windows out of {n} turns")


def encode_clip(clip_dir: Path, out_gif: Path, colors: int) -> None:
    mkv = clip_dir.with_suffix(".mkv")
    subprocess.run(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-framerate",
            str(FPS),
            "-i",
            str(clip_dir / "f%05d.png"),
            "-c:v",
            "ffv1",
            str(mkv),
        ],
        check=True,
    )
    out_gif.parent.mkdir(parents=True, exist_ok=True)
    env = {
        **os.environ,
        "FPS": str(FPS),
        "COLORS": str(colors),
        "DITHER": "none",
    }
    subprocess.run(
        [str(ROOT / "tools" / "make_gameplay_gif.sh"), str(mkv), str(out_gif), "0", "", "-1"],
        check=True,
        env=env,
    )


def record_action_platform(cfg: PlatformConfig, max_turns: int | None = None, max_attempts: int = 3) -> list[dict]:
    plat = cfg.name
    turns_limit = max_turns or cfg.max_turns
    workdir = WORK / plat
    workdir.mkdir(parents=True, exist_ok=True)
    save_bytes = bs.convert_save_for_platform(plat, plat)
    info = bs.verify_save(save_bytes)
    save_d64 = (workdir / "save.d64").resolve()
    bs.package_cbm_save_disk(save_bytes, save_d64)

    ckpt_dir = bs.BALROG_ROOT / bs.BALROG_ASSIGNMENTS[plat]
    snap_ref = ckpt_dir / "graduate.vsf"
    base_goal = for_character(GOALS["balrog"], cfg.char_slug)
    rec_goal = replace(
        base_goal,
        target_dlvl=info["max_dl"] + 3,
        ready_margin=0,
        tactics=base_goal.tactics - {"restock", "dangerous", "summoner"},
    )
    build = make_build(cfg.port)

    for attempt in range(1, max_attempts + 1):
        print(f"[{plat}] attempt {attempt}/{max_attempts}: loading {info['race']} {info['class']} clvl {info['clvl']} -> DL {info['max_dl']}")
        run_dir = (workdir / f"run_{attempt}").resolve()
        shutil.rmtree(run_dir, ignore_errors=True)
        run_dir.mkdir(parents=True, exist_ok=True)

        w = Worker(
            run_dir,
            0,
            build=build,
            extra_args=("-drive9type", "1541", "-drive9truedrive", "-9", str(save_d64)),
        )
        try:
            w.start_at_title()
            game = w.game
            assert game is not None
            if attempt > 1:
                game.mon.mem_set(game.abi.zp_rng_0, bytes([0x31 * attempt, 0x7B, 0xC3, 0x19]), game.ram)

            obs = load_balrog_and_recall(w, info)
            renderer = FrameRenderer(game, plat)
            brain = load_brain(snap_ref, rec_goal)
            brain.goal = rec_goal
            brain.recall = info["wor_qty"]
            brain.max_dlvl = info["max_dl"]
            brain.recalling = False
            brain.restock_scumming = False
            brain.last_dlvl = obs.dlvl
            brain.equip_checked = False
            brain.town_trip = lambda _obs: False

            recs: list[TurnRec] = []
            prev_pos: tuple[int, int] | None = None
            prev_hp = obs.hp
            combat_turns = 0

            for step_i in range(turns_limit):
                if obs.mode == Mode.DEATH or obs.dlvl == 0:
                    break
                assert not (obs.game_flags & 0x02), "Wizard mode flag must never be set!"

                tiles = nav.read_map(game) if obs.mode == Mode.COMMAND else None
                view = None
                creatures = 0
                if tiles is not None:
                    rows = game.abi.CATALOG_DUNGEON_CREATURES if knowledge.uses_catalog() else game.abi.TIER_DUNGEON_CREATURES
                    levels = game.mon.mem_get(game.abi.cr_level, rows + game.abi.MAX_TOWN_CREATURES, game.ram)
                    view = build_view(game, obs, tiles, levels)
                    creatures = len(view.creatures)

                snap = renderer.grab(obs)
                decision = brain.decide(obs, view)
                rep, score = classify_turn(obs, prev_pos, prev_hp, creatures, brain.attacked)
                if score >= 16:
                    combat_turns += 1
                recs.append(
                    TurnRec(
                        step_idx=step_i,
                        snap=snap,
                        mode=obs.mode,
                        dlvl=obs.dlvl,
                        pos=obs.pos,
                        hp=obs.hp,
                        mp=obs.zp8("zp_player_mp"),
                        creatures=creatures,
                        msg=(obs.rows[0].strip() + " | " + obs.rows[1].strip()).strip(" |"),
                        repeat=rep,
                        score=score,
                    )
                )
                prev_pos = obs.pos
                prev_hp = obs.hp

                # Stop early once we have rich combat encounters & enough spacing
                if step_i >= 280 and combat_turns >= 28 and obs.mode == Mode.COMMAND:
                    break

                key = decision.key
                assert key != 0x17, "Wizard mode Ctrl+W is strictly forbidden"
                if obs.mode == Mode.COMMAND and obs.dlvl <= 1 and key == ord("<"):
                    key = ord(".")
                if brain.recalling:
                    brain.recalling = False
                obs = game.press(key)

            print(f"[{plat}] recorded {len(recs)} turns (combat turns={combat_turns})")
            windows = select_highlight_windows(recs, cfg.num_action_clips)
        except Exception as exc:
            print(f"[{plat}] attempt {attempt} failed: {exc}")
            continue
        finally:
            w.stop()

        results = []
        for idx, (s, e) in enumerate(windows):
            clip_num = cfg.first_clip_num + idx
            clip_dir = workdir / f"clip_{clip_num}"
            shutil.rmtree(clip_dir, ignore_errors=True)
            clip_dir.mkdir(parents=True, exist_ok=True)
            fidx = 0
            rendered_cache: dict[int, Path] = {}
            for ti in range(s, e + 1):
                if ti not in rendered_cache:
                    p = clip_dir / f"_u{ti:05d}.png"
                    renderer.render_png(recs[ti].snap, p, cfg.target_size)
                    rendered_cache[ti] = p
                rep = recs[ti].repeat
                if ti == s or ti == e:
                    rep = max(rep, 4)
                for _ in range(rep):
                    shutil.copyfile(rendered_cache[ti], clip_dir / f"f{fidx:05d}.png")
                    fidx += 1
            for p in rendered_cache.values():
                p.unlink(missing_ok=True)
            out_gif = ASSETS / f"moria8-{plat}-gameplay-{clip_num}.gif"
            encode_clip(clip_dir, out_gif, cfg.colors)
            im = Image.open(out_gif)
            dls = sorted({recs[t].dlvl for t in range(s, e + 1)})
            results.append(
                {
                    "platform": plat,
                    "clip": clip_num,
                    "path": out_gif,
                    "size_b": out_gif.stat().st_size,
                    "dims": f"{im.size[0]}x{im.size[1]}",
                    "frames": getattr(im, "n_frames", fidx),
                    "race": info["race"],
                    "class": info["class"],
                    "clvl": info["clvl"],
                    "dls": dls,
                    "turns": (s, e),
                }
            )
            print(
                f"  -> {out_gif.name}: {out_gif.stat().st_size} B, {im.size[0]}x{im.size[1]}, "
                f"{getattr(im, 'n_frames', fidx)}f, DL {dls}"
            )
        return results

    raise RuntimeError(f"[{plat}] exhausted {max_attempts} attempts")


def _art_visible(im: Image.Image) -> bool:
    raw = im.convert("RGB").crop((136, 51, 456, 251)).tobytes()
    hits = 0
    for i in range(0, len(raw), 3):
        if raw[i] > 150 and raw[i + 1] > 110 and raw[i + 2] < 90:
            hits += 1
            if hits > 3000:
                return True
    return False


def _choose_menu(g, label: str) -> str:
    for line in g.text():
        m = re.search(r"\b([A-Z])\) " + label, line)
        if m:
            g.key(m.group(1), 0)
            return m.group(1)
    raise RuntimeError("menu entry not found: " + label)


def record_c64_clip1() -> dict:
    """Record C64 clip 1 (boot art + title + character creation + entering town, no wizard mode)."""
    from rec import Game, encode
    from vice_config import vice_config

    workdir = WORK / "c64" / "clip1_frames"
    cmd = [
        "x64sc",
        "-console",
        "-config",
        vice_config("x64sc"),
        "-default",
        "+saveres",
        "-binarymonitor",
        "-binarymonitoraddress",
        "ip4://127.0.0.1:6502",
        "+sound",
        "-sounddev",
        "dummy",
        "-drive8truedrive",
        "-drive8type",
        "1541",
        "+busdevice8",
        "-autostartprgmode",
        "1",
        "-autostart",
        str(BUILD / "moria8-c64.d64"),
    ]
    out_gif = ASSETS / "moria8-c64-gameplay-1.gif"
    last_exc: Exception | None = None
    for attempt in range(1, 4):
        shutil.rmtree(workdir, ignore_errors=True)
        workdir.mkdir(parents=True, exist_ok=True)
        prev_cwd = os.getcwd()
        g = None
        try:
            os.chdir(WORK)
            g = Game(cmd, 6502, str(workdir), (104, 16, 488, 288), (0x0400, 40, 25), fps=FPS)
            g.v.vic = True
            deadline = time.monotonic() + 45.0
            while time.monotonic() < deadline:
                frame = g.v.frame()
                if frame is not None and _art_visible(frame):
                    break
                time.sleep(0.2)
            else:
                raise RuntimeError("Timed out waiting for C64 boot artwork")
            g.hold(5)
            g.wait("N)EW")
            g.hold(2)
            g.key("N")
            g.wait("CHOOSE YOUR RACE")
            g.hold(1.5)
            _choose_menu(g, "DWARF")
            g.wait("ROLL STATISTICS")
            g.hold(1)
            g.key("R", 1)
            g.key("R", 1)
            g.key("\r")
            g.wait("CHOOSE YOUR CLASS")
            g.hold(1.5)
            _choose_menu(g, "WARRIOR")
            g.wait("ENTER YOUR NAME")
            g.hold(0.6)
            for ch in "DURIN":
                g.key(ch, 0.3)
            g.key("\r")
            g.wait("CHOOSE YOUR SEX")
            g.hold(1)
            g.key("A")
            g.wait("CHARACTER INFO")
            g.hold(2.5)
            g.key(" ")
            g.wait("WELCOME TO MORIA")
            g.hold(1.5)
            encode(str(workdir), str(out_gif), fps=FPS)
            break
        except Exception as exc:
            last_exc = exc
            print(f"[c64] clip 1 attempt {attempt}/3 failed: {exc}")
        finally:
            if g is not None:
                g.close()
            os.chdir(prev_cwd)
    else:
        raise RuntimeError(f"[c64] clip 1 failed after 3 attempts: {last_exc}")

    im = Image.open(out_gif)
    return {
        "platform": "c64",
        "clip": 1,
        "path": out_gif,
        "size_b": out_gif.stat().st_size,
        "dims": f"{im.size[0]}x{im.size[1]}",
        "frames": getattr(im, "n_frames", 1),
        "race": "Dwarf",
        "class": "Warrior",
        "clvl": 1,
        "dls": [0],
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Record non-wizard Commodore gameplay GIFs")
    ap.add_argument("platform", choices=["c64", "plus4", "c128", "all"])
    ap.add_argument("--clip1-only", action="store_true", help="C64 only: record only clip 1 (boot art + chargen)")
    ap.add_argument("--action-only", action="store_true", help="C64 only: record only action clips 2-4")
    ap.add_argument("--turns", type=int, default=0, help="Override max turns to record before selecting clips")
    args = ap.parse_args(argv)

    WORK.mkdir(parents=True, exist_ok=True)
    targets = ["c64", "plus4", "c128"] if args.platform == "all" else [args.platform]
    summary = []
    for plat in targets:
        if plat == "c64" and not args.action_only:
            summary.append(record_c64_clip1())
        if not (plat == "c64" and args.clip1_only):
            summary.extend(record_action_platform(PLAT_CFGS[plat], max_turns=args.turns or None))

    print("\n=== SUMMARY ===")
    for row in summary:
        print(
            f"{row['platform']:6s} clip {row['clip']}: {row['path'].name} | "
            f"{row['size_b']:,} B | {row['dims']} | {row['frames']}f | "
            f"{row['race']} {row['class']} clvl {row['clvl']} DL {row['dls']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
