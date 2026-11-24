#!/usr/bin/env python3
"""Record non-wizard Commander X16 gameplay GIFs from a Balrog Save V2 checkpoint.

Reads a transferred 17,164 B 198x66 Commander X16 save (``THE.GAME``) or
converts a C64 Balrog checkpoint via ``balrog_save.py``, boots ``x16emu
-testbench`` with the unzipped ``build/moria8-cx16.zip`` payload in a scratch
``-fsroot``, loads the character off-camera, descends via real gameplay (no
wizard mode) using ``playtest``'s ``Brain``, captures pixel-exact 640x480
VERA frames directly from live VRAM/palette/tile registers, and encodes 4
clips via ``tools/make_gameplay_gif.sh`` into ``docs/assets/``.
"""

from __future__ import annotations

import argparse
import dataclasses
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path
from PIL import Image, ImageChops

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BUILD = ROOT / "build"
ASSETS = ROOT / "docs" / "assets"
PLAYTEST_DIR = ROOT / "playtest"

for p in (str(HERE), str(PLAYTEST_DIR)):
    if p not in sys.path:
        sys.path.insert(0, p)

from moria_playtest import abi as abimod  # noqa: E402
from moria_playtest import knowledge, nav  # noqa: E402
from moria_playtest.brain import Brain, Decision, LevelMemory  # noqa: E402
from moria_playtest.game import KEY_SPACE, Mode, Observation, derive_rng  # noqa: E402
from moria_playtest.goals import CHARACTERS, CLASSES, DEFAULT_TACTICS, RACE_KEYS, Goal  # noqa: E402
from moria_playtest.ports import CX16  # noqa: E402
from moria_playtest.screen import decode_rows  # noqa: E402
from moria_playtest.session import load_brain  # noqa: E402
from moria_playtest.view import View, build_view  # noqa: E402
from moria_playtest.x16 import X16Game, X16Monitor, X16Process  # noqa: E402

RACES = tuple(RACE_KEYS)
COMBAT_NEWS = ("hit", "miss", "dies", "slain", "destroyed", "cast", "pray", "shoot", "zap", "-more-")


def find_x16_binaries() -> tuple[str, str]:
    """Return ``(x16emu, rom_bin)`` from environment variables (or PATH for x16emu)."""
    emu = os.environ.get("X16EMU") or shutil.which("x16emu") or ""
    rom = os.environ.get("X16ROM") or ""
    if not emu or not Path(emu).is_file():
        raise FileNotFoundError("X16EMU is not set to an executable x16emu binary")
    if not rom or not Path(rom).is_file():
        raise FileNotFoundError("X16ROM is not set to a valid Commander X16 rom.bin")
    return emu, rom


class VeraFrameRenderer:
    """Pixel-exact VERA 80x30 16-color text renderer reading live VRAM & registers."""

    def __init__(self) -> None:
        self._tile_cache: dict[int, bytes] = {}
        self._strip_cache: dict[tuple[int, int, int], list[bytes]] = {}

    def reset(self) -> None:
        self._tile_cache.clear()
        self._strip_cache.clear()

    def _read_vera_block(self, mon: X16Monitor, addr: int, length: int) -> bytes:
        if mon.block:
            return bytes(mon._run([f"RQV {addr:05X} {length:X}"]))
        saved = mon._run([f"RQM {r:04X}" for r in (0x9F20, 0x9F21, 0x9F22, 0x9F25)])
        cmds = [
            "STM 9F25 00",
            f"STM 9F22 {(addr >> 16) | 0x10:02X}",
            f"STM 9F21 {(addr >> 8) & 0xFF:02X}",
            f"STM 9F20 {addr & 0xFF:02X}",
        ] + ["RQM 9F23"] * length + [
            f"STM {r:04X} {v:02X}" for r, v in zip((0x9F20, 0x9F21, 0x9F22, 0x9F25), saved)
        ]
        return bytes(mon._run(cmds))

    def capture(self, mon: X16Monitor) -> Image.Image:
        """Read live VERA display/layer registers, palette, font, and 80x30 text VRAM."""
        vregs = mon.mem_get(0x9F29, 18, ("cpu", 0))
        dc_vscale = vregs[2]    # $9F2B (0x40 => 2x vertical scale, 240 -> 480 px)
        l1_map = vregs[12]      # $9F35
        l1_tile = vregs[13]     # $9F36
        map_base = l1_map << 9
        tile_base = (l1_tile & 0xFC) << 9

        pal_raw = self._read_vera_block(mon, 0x1FA00, 32)
        palette: list[int] = []
        for i in range(16):
            entry = pal_raw[2 * i] | (pal_raw[2 * i + 1] << 8)
            palette.extend((((entry >> 8) & 0xF) * 17, ((entry >> 4) & 0xF) * 17, (entry & 0xF) * 17))
        palette.extend([0] * (256 - 16) * 3)

        font_raw = self._tile_cache.get(tile_base)
        if font_raw is None:
            font_raw = self._read_vera_block(mon, tile_base, 2048)
            self._tile_cache[tile_base] = font_raw

        if mon.block:
            rows_raw = bytes(mon._run([f"RQV {map_base + r * 256:05X} A0" for r in range(30)]))
        else:
            rows_buf = bytearray()
            for r in range(30):
                rows_buf.extend(self._read_vera_block(mon, map_base + r * 256, 160))
            rows_raw = bytes(rows_buf)

        buf = bytearray(640 * 240)
        for r in range(30):
            row_off = r * 160
            for c in range(80):
                code = rows_raw[row_off + c * 2]
                attr = rows_raw[row_off + c * 2 + 1]
                key = (tile_base, code, attr)
                strips = self._strip_cache.get(key)
                if strips is None:
                    fg = attr & 0x0F
                    bg = (attr >> 4) & 0x0F
                    f_off = code * 8
                    strips = [
                        bytes(fg if (font_raw[f_off + py] & (0x80 >> px)) else bg for px in range(8))
                        for py in range(8)
                    ]
                    self._strip_cache[key] = strips
                x0 = c * 8
                y0 = r * 8
                for py in range(8):
                    off = (y0 + py) * 640 + x0
                    buf[off : off + 8] = strips[py]

        img = Image.frombytes("P", (640, 240), bytes(buf))
        img.putpalette(palette)
        target_h = 480 if dc_vscale <= 0x40 else 240
        if target_h != 240:
            img = img.resize((640, target_h), Image.NEAREST)
        return img.convert("RGB")


def prepare_fsroot(fsroot: Path, save_path: Path | None) -> None:
    """Populate a clean scratch ``-fsroot`` from ``build/moria8-cx16.zip`` + optional save."""
    if fsroot.exists():
        shutil.rmtree(fsroot)
    fsroot.mkdir(parents=True, exist_ok=True)
    zip_path = BUILD / "moria8-cx16.zip"
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(fsroot)
    if save_path is not None:
        shutil.copy2(save_path, fsroot / "THE.GAME")
        (fsroot / "MORIA8.ID").write_bytes(b"M8SAVE")


def suppress_kernal_load_messages(game: X16Game) -> None:
    """Call X16 KERNAL ``SETMSG ($FF90)`` with A=0 so HostFS preloads match ``-run`` cleanly."""
    game.mon.mem_set(0x0700, bytes((0xA9, 0x00, 0x20, 0x90, 0xFF, 0x60)))
    game.process.send("RUN 0700")
    game.process.ready(30.0)


def decode_player_name(obs: Observation) -> str:
    raw = obs.player[:16].split(b"\x00", 1)[0]
    return decode_rows(raw.ljust(16, b" "), 16)[0].strip()


def assert_no_wizard(obs: Observation) -> None:
    assert obs.abi is not None
    if obs.game_flags & obs.abi.GAME_FLAG_WIZARD:
        raise RuntimeError("wizard flag detected; wizard mode is strictly forbidden")


def load_saved_character(game: X16Game, obs: Observation) -> Observation:
    """From the Title screen, load slot 1 off-camera and wait for Town command loop."""
    if "N)ew" not in "\n".join(obs.rows):
        raise RuntimeError("expected title menu before loading save:\n" + "\n".join(obs.rows))
    obs = game.press(ord("L"))
    for _ in range(12):
        screen = "\n".join(obs.rows)
        if obs.mode == Mode.COMMAND:
            assert_no_wizard(obs)
            return obs
        if "Save Slots:" in screen or "Select Slot" in screen:
            obs = game.press(ord("1"))
        elif obs.mode == Mode.DISMISS or "Welcome back" in screen or "Press any key" in screen:
            obs = game.press(KEY_SPACE)
        else:
            raise RuntimeError(f"unexpected screen during save load ({obs.mode}/{obs.stage}):\n{screen}")
    raise RuntimeError("timed out loading save slot 1")


def build_brain_for_save(obs: Observation, target_dl: int, brain_pickle: Path | None,
                         work_dir: Path) -> tuple[Goal, Brain]:
    assert obs.abi is not None
    race = RACES[obs.player[obs.abi.PL_RACE]]
    klass = CLASSES[obs.player[obs.abi.PL_CLASS]]
    max_dlvl = obs.player[obs.abi.PL_MAX_DLVL]
    goal = Goal(
        name="gif_cx16",
        description=f"Non-wizard CX16 capture on DL{target_dl}",
        reached=lambda o: False,
        character=CHARACTERS[f"{race}-{klass}"],
        race=race,
        klass=klass,
        step_budget=60_000,
        target_dlvl=target_dl,
        want_xp=False,
        ready_margin=-20,
        tactics=DEFAULT_TACTICS,
    )
    if brain_pickle is not None and brain_pickle.is_file():
        scratch_snap = work_dir / "brain_copy.vsf"
        shutil.copy2(brain_pickle, scratch_snap.with_suffix(".brain.pickle"))
        brain = load_brain(scratch_snap, goal)
        meta_json = brain_pickle.with_suffix(".json")
        if meta_json.is_file():
            meta = json.loads(meta_json.read_text(encoding="utf-8"))
            brain.last_xp = int(meta.get("xp", obs.xp))
    else:
        brain = Brain(goal)
    brain.map_scale = CX16.map_scale
    brain.max_dlvl = max(brain.max_dlvl, max_dlvl)
    brain.pack_check_due = True
    brain.equip_checked = False
    brain.level = LevelMemory()
    brain.last_dlvl = None
    brain.trail.clear()
    brain.loop_trail.clear()
    brain.positions.clear()
    brain.last_pos = None
    return goal, brain


def step_brain(game: X16Game, brain: Brain, obs: Observation) -> tuple[Observation, Decision, View | None]:
    assert_no_wizard(obs)
    if obs.mode == Mode.DEATH:
        raise RuntimeError(f"character died at DL{obs.dlvl} step {game.step}:\n" + "\n".join(obs.rows))
    view: View | None = None
    if obs.mode == Mode.COMMAND:
        tiles = nav.read_map(game)
        rows = game.abi.CATALOG_DUNGEON_CREATURES if knowledge.uses_catalog() else game.abi.TIER_DUNGEON_CREATURES
        levels = game.mon.mem_get(game.abi.cr_level, rows + game.abi.MAX_TOWN_CREATURES, game.ram)
        view = build_view(game, obs, tiles, levels)
    decision = brain.decide(obs, view)
    next_obs = game.press(decision.key)
    assert_no_wizard(next_obs)
    return next_obs, decision, view


def settle_for_dungeon(game: X16Game, brain: Brain, obs: Observation, target_dl: int,
                       max_steps: int = 8000) -> Observation:
    """Drive the loaded hero off-camera until settled cleanly on ``target_dl``."""
    last_dl = obs.dlvl
    for step_i in range(max_steps):
        if obs.dlvl != last_dl:
            last_dl = obs.dlvl
            print(f"  off-camera descent: reached DL{obs.dlvl} (step {step_i}, hp={obs.hp}/{obs.mhp})", flush=True)
        if (obs.mode == Mode.COMMAND and obs.dlvl >= target_dl and not brain.recalling
                and not brain.pack_check_due and brain.equip_checked and not brain.to_wear
                and obs.hp >= int(0.65 * obs.mhp)):
            return obs
        obs, _, _ = step_brain(game, brain, obs)
    raise RuntimeError(f"did not reach DL{target_dl} within {max_steps} steps (dlvl={obs.dlvl}, hp={obs.hp}/{obs.mhp})")


def find_action_moment(game: X16Game, brain: Brain, obs: Observation, min_dl: int,
                       min_gap_steps: int = 10, max_wait_steps: int = 600) -> tuple[Observation, View]:
    """Advance off-camera until an active monster encounter on ``min_dl``+ is ready."""
    steps_taken = 0
    for _ in range(max_wait_steps):
        obs, _, view = step_brain(game, brain, obs)
        steps_taken += 1
        if (steps_taken >= min_gap_steps and obs.mode == Mode.COMMAND and obs.dlvl >= min_dl
                and not brain.recalling and not brain.pack_check_due and brain.equip_checked
                and not brain.to_wear and obs.hp >= int(0.65 * obs.mhp)):
            if view is None:
                tiles = nav.read_map(game)
                rows = game.abi.CATALOG_DUNGEON_CREATURES if knowledge.uses_catalog() else game.abi.TIER_DUNGEON_CREATURES
                levels = game.mon.mem_get(game.abi.cr_level, rows + game.abi.MAX_TOWN_CREATURES, game.ram)
                view = build_view(game, obs, tiles, levels)
            if view.creatures and (len(view.creatures) >= 2 or steps_taken >= min_gap_steps + 15):
                return obs, view
    raise RuntimeError(f"could not find active dungeon encounter (dlvl={obs.dlvl}, mode={obs.mode})")


def _frames_equal(a: Image.Image, b: Image.Image) -> bool:
    return ImageChops.difference(a, b).getbbox() is None


def record_clip(game: X16Game, brain: Brain, renderer: VeraFrameRenderer, obs: Observation,
                clip_dir: Path, min_dl: int, fps: int, clip_secs: float) -> tuple[Observation, bool]:
    """Capture one ~``clip_secs`` gameplay clip. Returns ``(obs, accepted)``."""
    shutil.rmtree(clip_dir, ignore_errors=True)
    clip_dir.mkdir(parents=True, exist_ok=True)
    target_frames = max(1, round(clip_secs * fps))
    frames: list[Image.Image] = []
    positions: set[tuple[int, int]] = set()
    distinct_imgs = 0
    idle_streak = 0
    last_img: Image.Image | None = None
    combat_or_action = False

    def push_frame(img: Image.Image, count: int) -> None:
        nonlocal distinct_imgs, idle_streak, last_img
        same = last_img is not None and _frames_equal(img, last_img)
        if same:
            idle_streak += 1
        else:
            distinct_imgs += 1
            idle_streak = 0
            last_img = img
        for _ in range(count):
            frames.append(img)

    start_dlvl = obs.dlvl
    # Initial frame
    push_frame(renderer.capture(game.mon), 3)
    positions.add(obs.pos)

    for _ in range(target_frames * 2):
        if len(frames) >= target_frames - 4 and obs.mode == Mode.COMMAND:
            break
        if obs.dlvl != start_dlvl or obs.dlvl < min_dl or obs.mode == Mode.DEATH:
            return obs, False
        if idle_streak > 8:
            return obs, False
        obs, decision, _ = step_brain(game, brain, obs)
        positions.add(obs.pos)
        if decision.layer in ("fight", "aim", "shoot", "throw", "pray", "invoke", "devices"):
            combat_or_action = True
        msg = (obs.rows[0] + " " + obs.rows[1]).lower()
        is_news = obs.mode != Mode.COMMAND or any(w in msg for w in COMBAT_NEWS)
        img = renderer.capture(game.mon)
        if last_img is not None and _frames_equal(img, last_img):
            push_frame(img, 1)
        else:
            push_frame(img, 3 if is_news else 2)

    # Hold cleanly on COMMAND mode at the end of the clip (no -more- hangs)
    for _ in range(8):
        if obs.mode == Mode.COMMAND:
            break
        obs, _, _ = step_brain(game, brain, obs)
        push_frame(renderer.capture(game.mon), 2)
    if obs.mode != Mode.COMMAND or obs.dlvl != start_dlvl or obs.dlvl < min_dl:
        return obs, False

    push_frame(renderer.capture(game.mon), 4)
    if distinct_imgs < 7 or not (combat_or_action or len(positions) >= 5):
        return obs, False

    for idx, frame in enumerate(frames):
        frame.save(clip_dir / f"f{idx:05d}.png")
    return obs, True


def encode_clip(clip_dir: Path, out_gif: Path, fps: int) -> None:
    mkv = clip_dir.with_suffix(".mkv")
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-framerate", str(fps), "-i", str(clip_dir / "f%05d.png"),
            "-c:v", "ffv1", str(mkv),
        ],
        check=True,
    )
    out_gif.parent.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "FPS": str(fps), "COLORS": "64", "DITHER": "none"}
    subprocess.run(
        [str(ROOT / "tools" / "make_gameplay_gif.sh"), str(mkv), str(out_gif), "0", "", "-1"],
        check=True,
        env=env,
    )


def run_capture(
    *,
    save_path: Path,
    target_dl: int,
    brain_pickle: Path | None,
    seed: int,
    fps: int,
    clip_secs: float,
    out_dir: Path,
    work_dir: Path,
) -> list[dict[str, object]]:
    emu, rom = find_x16_binaries()
    os.environ["PLAYTEST_X16_BLOCK"] = "1"
    abi = abimod.load(BUILD / "cx16" / "main.sym", port=CX16)
    knowledge.use_port("cx16")
    renderer = VeraFrameRenderer()

    fsroot = work_dir / "fsroot"
    prepare_fsroot(fsroot, save_path)
    proc = X16Process(0, fsroot, fsroot, CX16)
    proc.start_x16(emu, rom)
    try:
        game = X16Game(proc, abi, fsroot, port=CX16)
        suppress_kernal_load_messages(game)
        obs = game.boot()
        obs = load_saved_character(game, obs)

        name = decode_player_name(obs)
        race = RACES[obs.player[abi.PL_RACE]]
        klass = CLASSES[obs.player[abi.PL_CLASS]]
        clvl = obs.clvl
        max_dl = obs.player[abi.PL_MAX_DLVL]
        print(f"Loaded CX16 hero: {name} | {race} {klass} | clvl={clvl} | hp={obs.hp}/{obs.mhp} | max_dl={max_dl}")

        game.mon.mem_set(abi.zp_rng_0, derive_rng(seed, 1), game.ram)
        if brain_pickle is not None and brain_pickle.with_suffix(".json").is_file():
            meta = json.loads(brain_pickle.with_suffix(".json").read_text(encoding="utf-8"))
            game.step = int(meta.get("step", game.step))
            game.map_step = game.step - 100
        goal, brain = build_brain_for_save(obs, target_dl, brain_pickle, work_dir)
        obs = settle_for_dungeon(game, brain, obs, target_dl)
        print(f"Descended off-camera to DL{obs.dlvl} at {obs.pos} (hp={obs.hp}/{obs.mhp})")

        # Keep Brain actively hunting/fighting near this depth during capture
        brain.goal = dataclasses.replace(goal, target_dlvl=obs.dlvl, want_xp=True)

        clips_info: list[dict[str, object]] = []
        clip_idx = 1
        attempts = 0
        while clip_idx <= 4 and attempts < 16:
            attempts += 1
            if obs.dlvl < target_dl:
                brain.goal = dataclasses.replace(goal, target_dlvl=target_dl, want_xp=False)
                obs = settle_for_dungeon(game, brain, obs, target_dl)
            brain.goal = dataclasses.replace(goal, target_dlvl=obs.dlvl, want_xp=True)
            obs, _ = find_action_moment(game, brain, obs, target_dl, min_gap_steps=25 if clip_idx == 1 else 18)
            # Lock target_dlvl to current dlvl while recording one clip
            brain.goal = dataclasses.replace(goal, target_dlvl=obs.dlvl, want_xp=True)
            clip_dir = work_dir / f"clip{clip_idx}"
            obs_after, accepted = record_clip(game, brain, renderer, obs, clip_dir, target_dl, fps, clip_secs)
            obs = obs_after
            if not accepted:
                print(f"Candidate for clip {clip_idx} rejected (attempt {attempts}), advancing...")
                continue
            out_gif = out_dir / f"moria8-cx16-gameplay-{clip_idx}.gif"
            encode_clip(clip_dir, out_gif, fps)
            im = Image.open(out_gif)
            durs = []
            for fi in range(im.n_frames):
                im.seek(fi)
                durs.append(im.info.get("duration", 100))
            info = {
                "clip": clip_idx,
                "path": str(out_gif),
                "bytes": out_gif.stat().st_size,
                "width": im.size[0],
                "height": im.size[1],
                "frames": im.n_frames,
                "duration_ms": sum(durs),
                "dlvl": obs.dlvl,
                "clvl": obs.clvl,
                "name": name,
                "race": race,
                "class": klass,
            }
            clips_info.append(info)
            print(f"Encoded clip {clip_idx}: {out_gif.name} {im.size[0]}x{im.size[1]} "
                  f"{im.n_frames}f {sum(durs)}ms {out_gif.stat().st_size}B (DL{obs.dlvl})")
            clip_idx += 1
            # Optionally descend one deeper level between clips 2 and 3 for visual variety
            if clip_idx == 3:
                brain.goal = dataclasses.replace(goal, target_dlvl=obs.dlvl + 1, want_xp=False)
                try:
                    obs = settle_for_dungeon(game, brain, obs, obs.dlvl + 1, max_steps=1500)
                except RuntimeError:
                    pass
                brain.goal = dataclasses.replace(goal, target_dlvl=obs.dlvl, want_xp=True)

        if len(clips_info) != 4:
            raise RuntimeError(f"only recorded {len(clips_info)}/4 clips after {attempts} attempts")
        return clips_info
    finally:
        proc.kill()


def main(argv: list[str] | None = None) -> int:
    import balrog_save

    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--save", type=Path, help="Path to 17,164 B transferred CX16 THE.GAME save")
    group.add_argument("--checkpoint", type=str, default="cx16",
                       help="Balrog checkpoint name/path or platform key (default: cx16)")
    parser.add_argument("--dl", type=int, default=0,
                        help="Target dungeon level (default: save's max_dl)")
    parser.add_argument("--brain-pickle", type=Path, help="Optional graduate.brain.pickle path")
    parser.add_argument("--seed", type=int, default=20261121, help="RNG seed for dungeon encounters")
    parser.add_argument("--fps", type=int, default=10, help="Output GIF FPS (default 10)")
    parser.add_argument("--clip-secs", type=float, default=5.0, help="Target seconds per clip (default 5.0)")
    parser.add_argument("--out-dir", type=Path, default=ASSETS, help="Output directory for GIFs")
    parser.add_argument("--work-dir", type=Path, default=BUILD / "gifcapture" / "cx16",
                        help="Scratch directory under build/")
    args = parser.parse_args(argv)

    args.work_dir.mkdir(parents=True, exist_ok=True)
    save_path = args.save
    brain_pickle = args.brain_pickle
    if save_path is None:
        d64_path = balrog_save.resolve_checkpoint_d64(args.checkpoint)
        payload = balrog_save.convert_save_for_platform(d64_path, "cx16")
        save_path = args.work_dir / "THE.GAME"
        save_path.write_bytes(payload)
        if brain_pickle is None:
            cand = d64_path.parent / "graduate.brain.pickle"
            if cand.is_file():
                brain_pickle = cand

    info = balrog_save.verify_save(save_path.read_bytes())
    target_dl = args.dl or int(info["max_dl"]) or 12

    clips = run_capture(
        save_path=save_path,
        target_dl=target_dl,
        brain_pickle=brain_pickle,
        seed=args.seed,
        fps=args.fps,
        clip_secs=args.clip_secs,
        out_dir=args.out_dir,
        work_dir=args.work_dir,
    )
    (args.work_dir / "summary.json").write_text(json.dumps(clips, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
