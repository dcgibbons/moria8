#!/usr/bin/env python3
"""Record non-wizard Balrog gameplay GIFs for MAME ports (Apple IIe, Atari 8-bit, BBC Master 128).

Packages each platform's assigned non-wizard Balrog Town checkpoint onto a
native save disk, boots MAME with ``mame_snap_bridge.lua`` under ``-video soft``,
loads the save off-camera, descends to the character's real max dungeon depth via
Word of Recall off-camera, drives genuine non-wizard gameplay with
``playtest/moria_playtest/brain.py``, selects 4 action-packed 4-6s clips,
normalizes aspect ratios with nearest-neighbor scaling, and encodes GIFs via
``tools/make_gameplay_gif.sh``.

Must be launched via ``tools/isolated.sh`` with ``A2ROMS``, ``ATARI8ROMS``,
and ``BBCMROMS`` set in the environment.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, replace
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Any

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ASSETS = ROOT / "docs" / "assets"
BUILD = ROOT / "build"
WORK = Path(os.environ.get("GIFCAP_WORK", BUILD / "gifcapture")).resolve()
BRIDGE = HERE / "mame_snap_bridge.lua"
AC_BIN = ROOT / "tools" / "applecommander" / "ac"
GIF_SCRIPT = ROOT / "tools" / "make_gameplay_gif.sh"
BALROG_ROOT = ROOT / "var" / "moria8" / "balrog"

sys.path.insert(0, str(HERE))
import balrog_save as bs  # noqa: E402

sys.path.insert(0, str(ROOT / "tools"))
from make_atr import AtrBuilder  # noqa: E402
from make_ssd import DfsFileSpec, build_ssd_image  # noqa: E402

sys.path.insert(0, str(ROOT / "playtest"))
from moria_playtest import abi as abimod  # noqa: E402
from moria_playtest import goals, knowledge, launch, nav, ports, session  # noqa: E402
from moria_playtest.brain import Brain  # noqa: E402
from moria_playtest.game import KEY_SPACE, Mode, Observation  # noqa: E402
from moria_playtest.mame import MameGame, MameProcess  # noqa: E402
from moria_playtest.view import build_view  # noqa: E402


MAME_PLATFORMS = ("apple2", "atari8", "bbcmaster")
PORT_BY_NAME = {
    "apple2": ports.APPLE2,
    "atari8": replace(ports.ATARI8, mame_machine="a130xe"),
    "bbcmaster": ports.BBCMASTER,
}

TARGET_FPS = 10
MIN_CLIP_FRAMES = 42   # 4.2s at 10 fps
MAX_CLIP_FRAMES = 58   # 5.8s at 10 fps

FIGHT_RE = re.compile(
    r"(You (?:hit|miss|cast|pray|aim|slay|shoot|fire|throw)|"
    r"You have slain|hits you|misses you|casts a|breathes|frightens you|"
    r"stings you|bites you|claws you|gazes at you|touches you|wails at you|"
    r"You feel yourself|appears|wakes up|dies)",
    re.I,
)
LOOT_RE = re.compile(r"(You picked up|You open|You bash|You disarm|Welcome to level)", re.I)
IMPORTANT_RE = re.compile(r"(You have slain|casts a|breathes|Welcome to level)", re.I)


def find_wor_slot(save_bytes: bytes) -> str:
    """Return the pack slot letter ('a'..'v') holding a Scroll of Word of Recall."""
    inv = save_bytes[bs.OFF_INV : bs.OFF_INV + bs.LEN_INV]
    inv_id = inv[0:34]
    inv_qty = inv[34:68]
    inv_ego = inv[238:272]
    for i in range(22):
        iid, _ = bs.decode_paged_item(inv_id[i], inv_ego[i])
        if iid == bs.WOR_ITEM_ID and inv_qty[i] > 0:
            return chr(ord("a") + i)
    raise RuntimeError("Assigned Balrog save has no Scroll of Word of Recall in pack")


def build_apple2_save_disk(save_bytes: bytes, out_po: Path) -> Path:
    """Create a 140 KB ProDOS save disk containing MORIA8.ID and THE.GAME."""
    out_po.parent.mkdir(parents=True, exist_ok=True)
    out_po.unlink(missing_ok=True)
    subprocess.run([str(AC_BIN), "-pro140", str(out_po), "SAVE1"], check=True, capture_output=True)
    id_tmp = out_po.with_suffix(".id.tmp")
    save_tmp = out_po.with_suffix(".game.tmp")
    id_tmp.write_bytes(bs.MARKER_MAGIC)
    save_tmp.write_bytes(save_bytes)
    try:
        with id_tmp.open("rb") as fh:
            subprocess.run([str(AC_BIN), "-p", str(out_po), "MORIA8.ID", "bin", "0"], stdin=fh, check=True, capture_output=True)
        with save_tmp.open("rb") as fh:
            subprocess.run([str(AC_BIN), "-p", str(out_po), "THE.GAME", "bin", "0"], stdin=fh, check=True, capture_output=True)
    finally:
        id_tmp.unlink(missing_ok=True)
        save_tmp.unlink(missing_ok=True)
    return out_po


def build_atari8_save_disk(save_bytes: bytes, out_atr: Path) -> Path:
    """Create a 130 KB DOS 2.5 ED save disk with MORIA8.ID and SAVE0.SAV."""
    out_atr.parent.mkdir(parents=True, exist_ok=True)
    builder = AtrBuilder()
    builder.add_file("MORIA8.ID", bs.MARKER_MAGIC)
    builder.add_preallocated_empty_slot("HISCORE.DAT", 2)
    builder.add_file("SAVE0.SAV", save_bytes, contiguous=True)
    for slot in range(1, 4):
        builder.add_preallocated_empty_slot(f"SAVE{slot}.SAV", 68)
    out_atr.write_bytes(builder.to_bytes())
    return out_atr


def build_bbcmaster_save_disk(save_bytes: bytes, out_ssd: Path) -> Path:
    """Create an 80-track Acorn DFS save disk with MORIAID and SAVE0."""
    out_ssd.parent.mkdir(parents=True, exist_ok=True)
    img = build_ssd_image(
        [
            DfsFileSpec("MORIAID", "$", False, 0xFFFF0E00, 0xFFFF0E00, bs.MARKER_MAGIC),
            DfsFileSpec("SAVE0", "$", False, 0xFFFF0E00, 0xFFFF0E00, save_bytes),
        ],
        title="M8SAVE",
        boot_opt=0,
    )
    out_ssd.write_bytes(img)
    return out_ssd


def package_save_disk(platform: str, save_bytes: bytes, scratch_dir: Path) -> Path:
    if platform == "apple2":
        return build_apple2_save_disk(save_bytes, scratch_dir / "save.po")
    if platform == "atari8":
        return build_atari8_save_disk(save_bytes, scratch_dir / "save.atr")
    if platform == "bbcmaster":
        return build_bbcmaster_save_disk(save_bytes, scratch_dir / "save.ssd")
    raise ValueError(f"Unsupported MAME platform: {platform}")


def _read_dfs_file(image: bytes, name: str) -> bytes:
    count = image[0x105] // 8
    for i in range(count):
        entry = image[8 + i * 8 : 16 + i * 8]
        if entry[:7].decode("ascii", "replace").rstrip() != name or (entry[7] & 0x7F) != ord("$"):
            continue
        info = image[0x108 + i * 8 : 0x110 + i * 8]
        length = info[4] | info[5] << 8 | ((info[6] >> 4) & 3) << 16
        start = info[7] | (info[6] & 3) << 8
        return image[start * 256 : start * 256 + length]
    raise FileNotFoundError(f"{name} not in DFS catalogue")


def write_bbc_fastboot_manifest(disk_path: Path, boot_sym_path: Path, scratch: Path) -> Path:
    """Extract MORIA8P entries from the shipping BBC .ssd for instant off-camera boot."""
    image = disk_path.read_bytes()
    boot = _read_dfs_file(image, "MORIA8")
    pak = _read_dfs_file(image, "MORIA8P")
    syms: dict[str, int] = {}
    for line in boot_sym_path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^\.label\s+([A-Za-z0-9_]+)\s*=\s*\$([0-9A-Fa-f]+)", line.strip())
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
    loader_dest = 0x0400
    block = syms["loader_src"] - syms["boot_start"]
    count = pak[0]
    banks = boot[block + syms["file_bank_table"] - loader_dest :][:count]
    pages = boot[block + syms["file_hi_table"] - loader_dest :][:count]
    offset = 512
    fb_dir = scratch / "fastboot"
    fb_dir.mkdir(parents=True, exist_ok=True)
    lines = []
    for i in range(count):
        length = pak[2 + i * 2] | pak[3 + i * 2] << 8
        payload_path = fb_dir / f"entry_{i:02d}.bin"
        payload_path.write_bytes(pak[offset : offset + length])
        lines.append(f"{banks[i]:02X} {pages[i] << 8:04X} {payload_path}")
        offset += length
    manifest = fb_dir / "manifest.txt"
    manifest.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return manifest


class SnapMameProcess(MameProcess):
    """MameProcess extended for two-floppy mounts, -video soft, and SNAP bridge."""

    def __init__(
        self,
        *args: Any,
        snap_dir: Path,
        save_disk: Path | None = None,
        bbc_fastboot: Path | None = None,
        **kwargs: Any,
    ) -> None:
        super().__init__(*args, **kwargs)
        self.snap_dir = snap_dir
        self.save_disk = save_disk
        self.bbc_fastboot = bbc_fastboot

    def start(self, rom_args: list[str], tap_spec: str, connect_timeout: float = 60.0) -> "SnapMameProcess":
        fifo_in, fifo_out = self.workdir / "bridge.in", self.workdir / "bridge.out"
        for fifo in (fifo_in, fifo_out):
            fifo.unlink(missing_ok=True)
            os.mkfifo(fifo)
        cfg = self.workdir / "mame"
        cfg.mkdir(parents=True, exist_ok=True)
        self.snap_dir.mkdir(parents=True, exist_ok=True)
        port = self.target
        self.args = [
            "mame", port.mame_machine, *rom_args,
            *(arg for kind in ("cfg", "nvram", "state", "diff", "comment", "input")
              for arg in (f"-{kind}_directory", str(cfg))),
            "-snapshot_directory", str(self.snap_dir),
            *(("-cart1", str(self.cartridge)) if self.cartridge is not None else ()),
            port.mame_media, str(self.disk),
            *(("-flop2", str(self.save_disk)) if self.save_disk is not None else ()),
            "-video", "soft", "-sound", "none", "-nothrottle",
            "-skip_gameinfo", "-seconds_to_run", "299",
            "-autoboot_script", str(BRIDGE), "-autoboot_delay", "0",
        ]
        env = dict(
            os.environ,
            SDL_VIDEODRIVER="dummy",
            SDL_AUDIODRIVER="dummy",
            MORIA8_BRIDGE_IN=str(fifo_in),
            MORIA8_BRIDGE_OUT=str(fifo_out),
            MORIA8_BRIDGE_ITEMS=port.mame_items,
            MORIA8_BRIDGE_TAPS=tap_spec,
            MORIA8_BRIDGE_HANG=str(self.hang_emulated_seconds),
            MORIA8_BRIDGE_BOOT=port.mame_boot,
            MORIA8_BBC_FASTBOOT=str(self.bbc_fastboot) if self.bbc_fastboot is not None else "",
        )
        self.log_path = self.workdir / "mame.log"
        log = self.log_path.open("ab")
        self.proc = subprocess.Popen(
            self.args, cwd=self.workdir, stdin=subprocess.DEVNULL, stdout=log,
            stderr=subprocess.STDOUT, env=env, start_new_session=True,
        )
        log.close()
        deadline = time.monotonic() + connect_timeout
        self._in = self._open(fifo_in, os.O_WRONLY, deadline)
        self._out = self._open(fifo_out, os.O_RDONLY, deadline)
        return self


class SnapMameGame(MameGame):
    """MameGame capable of capturing tear-free PNG snapshots via mame_snap_bridge.lua."""

    def snap(self, filename: str, wait_frames: int = 2) -> Path:
        proc = self.process
        assert isinstance(proc, SnapMameProcess)
        proc.send(f"SNAP {filename} {wait_frames}")
        reply = proc.receive(self.resume_budget)
        if reply != "O":
            raise RuntimeError(f"Unexpected SNAP reply {reply!r} for {filename}")
        out = proc.snap_dir / filename
        if not out.is_file():
            raise RuntimeError(f"MAME snapshot missing on disk: {out}")
        return out


def petscii_key(ch: str) -> int:
    """Convert single ASCII character ('a'-'z', '0'-'9', etc.) to Moria8 PETSCII."""
    if "a" <= ch <= "z":
        return ord(ch.upper())       # $41..$5A = unshifted lowercase in Moria8 PETSCII
    if "A" <= ch <= "Z":
        return ord(ch) | 0x80        # $C1..$DA = shifted uppercase in Moria8 PETSCII
    return ord(ch)


def load_balrog_save(game: SnapMameGame, obs: Observation, platform: str) -> Observation:
    """Drive Title -> Disk Setup -> Load Slot 1 off-camera until Town Command mode."""
    if obs.stage != "title":
        raise RuntimeError(f"{platform}: expected title screen, got {obs.mode} / {obs.stage}")

    obs = game.press(ord("L"))
    for _ in range(40):
        if obs.mode == Mode.COMMAND and obs.dlvl == 0:
            if obs.game_flags & game.abi.GAME_FLAG_WIZARD:
                raise RuntimeError(f"{platform}: loaded save unexpectedly has WIZARD flag set")
            return obs
        screen = "\n".join(obs.rows)
        if "R) Rescan" in screen:
            digit = None
            for row in obs.rows:
                m = re.search(r"(\d)\)\s+/SAVE1\b", row)
                if m:
                    digit = m.group(1)
                    break
            if digit is None:
                raise RuntimeError(f"{platform}: /SAVE1 not listed in ProDOS volume picker:\n{screen}")
            obs = game.press(ord(digit))
        elif "Save drive" in screen:
            # BBC Master: :1 is '1'; Atari 8-bit: D2: is '2'
            obs = game.press(ord("1" if platform == "bbcmaster" else "2"))
        elif "DISK SETUP" in screen or "Pick save drive" in screen:
            if platform == "apple2" and "SAVE1" not in screen:
                obs = game.press(ord("2"))
            elif platform == "bbcmaster" and ":1" not in screen:
                obs = game.press(ord("2"))
            else:
                obs = game.press(ord("3"))
        elif "Save Slots:" in screen or "Select Slot 1-4" in screen:
            obs = game.press(ord("1"))
        elif "Initialize this disk?" in screen:
            raise RuntimeError(f"{platform}: save disk marker MORIA8.ID not recognized:\n{screen}")
        elif "-more-" in screen or "Press any key" in screen or "Welcome back" in screen:
            obs = game.press(KEY_SPACE)
        else:
            obs = game.press(KEY_SPACE)
    raise RuntimeError(f"{platform}: timed out loading Balrog save; last screen:\n" + "\n".join(obs.rows))


def descend_via_recall(game: SnapMameGame, obs: Observation, expected_dl: int) -> Observation:
    """Read a Scroll of Word of Recall in Town and rest until arrival on max_dl."""
    obs = game.press(ord("R"))
    asked_list = False
    for _ in range(12):
        screen = "\n".join(obs.rows)
        if any("Word of Rec" in row for row in obs.rows):
            letter = None
            for row in obs.rows:
                m = re.search(r"\b([a-z])\)\s+.*Word of Rec", row)
                if m:
                    letter = m.group(1)
                    break
            if letter is None:
                raise RuntimeError(f"Could not parse Word of Recall letter from:\n{screen}")
            obs = game.press(petscii_key(letter))
            break
        if ("Read which" in screen or obs.mode == Mode.ITEM) and not asked_list:
            asked_list = True
            obs = game.press(ord("?"))
        elif "-more-" in screen:
            obs = game.press(KEY_SPACE)
        else:
            raise RuntimeError(f"Unexpected state while reading Word of Recall:\n{screen}")
    else:
        raise RuntimeError("Never reached Word of Recall scroll menu")

    # Wait out the recall timer (~15-35 turns) in Town until dlvl reaches dungeon.
    for _ in range(80):
        if obs.dlvl > 0 and obs.mode == Mode.COMMAND:
            if obs.dlvl != expected_dl:
                print(f"  note: Word of Recall landed on DL{obs.dlvl} (expected DL{expected_dl})", flush=True)
            return obs
        if obs.mode == Mode.COMMAND:
            obs = game.press(ord("5"))
        else:
            obs = game.press(KEY_SPACE)
    raise RuntimeError(f"Word of Recall did not descend within 80 turns (dlvl={obs.dlvl})")


def prepare_brain(platform: str, ckpt_dir: Path, info: dict[str, Any], obs: Observation) -> Brain:
    """Load the checkpoint's Brain and configure it for active non-wizard dungeon play."""
    port = PORT_BY_NAME[platform]
    combo = f"{info['race'].lower()}-{info['class'].lower()}"
    base_goal = goals.for_port(goals.for_character(goals.GOALS["balrog"], combo), port)
    # Keep target_dlvl slightly above current depth so Brain explores and fights here
    # rather than heading right back up to Town.
    tuned_goal = replace(
        base_goal,
        target_dlvl=obs.dlvl + 2,
        ready_margin=0,
        threat_depth=False,
        want_xp=True,
        exercise=False,
    )
    brain = session.load_brain(ckpt_dir / "graduate.vsf", tuned_goal)
    brain.map_scale = port.map_scale
    brain.recalling = False
    brain.recall = max(0, brain.recall - 1)
    brain.last_dlvl = None
    brain.shopped = True
    brain.food = max(brain.food, 50.0)
    brain.pack_check_due = False
    brain.equip_checked = True
    brain.listing_pack = False
    brain.listing_equipment = False
    brain.light_left = max(brain.light_left, 5000)
    return brain


@dataclass
class TurnRecord:
    index: int
    snap_path: Path
    dlvl: int
    pos: tuple[int, int]
    hp: int
    mhp: int
    mode: Mode
    layer: str
    reason: str
    messages: str
    creatures_near: int
    screen_sig: str


def play_and_capture(
    game: SnapMameGame,
    obs: Observation,
    brain: Brain,
    snap_dir: Path,
    *,
    max_turns: int = 550,
) -> list[TurnRecord]:
    """Run genuine Brain gameplay on the dungeon level and snapshot every turn."""
    records: list[TurnRecord] = []
    rows_count = (
        game.abi.CATALOG_DUNGEON_CREATURES
        if knowledge.uses_catalog()
        else game.abi.TIER_DUNGEON_CREATURES
    )
    for idx in range(max_turns):
        if game.stop is not None and game.stop.time > 275.0:
            print(f"  stopping capture cleanly at emulated {game.stop.time:.1f}s (<299s limit)", flush=True)
            break
        if obs.mode == Mode.DEATH or obs.mode == Mode.CHARGEN:
            break
        if obs.dlvl == 0 and idx > 0:
            break
        if obs.game_flags & game.abi.GAME_FLAG_WIZARD:
            raise RuntimeError("WIZARD flag unexpectedly became set!")

        screen_text = "\n".join(obs.rows)
        if "GENERATING" in screen_text or "Disk Setup" in screen_text:
            obs = game.press(KEY_SPACE)
            continue

        view = None
        creatures_near = 0
        if obs.mode == Mode.COMMAND:
            tiles = nav.read_map(game)
            levels = game.mon.mem_get(game.abi.cr_level, rows_count + game.abi.MAX_TOWN_CREATURES, game.ram)
            view = build_view(game, obs, tiles, levels)
            creatures_near = len(view.creatures)

        decision = brain.decide(obs, view)
        # Keep the character active in the dungeon (avoid recalling to Town or long idle auto-rests).
        if obs.mode == Mode.COMMAND and view is not None and (
            decision.layer == "recall"
            or (decision.key == 0x12 and obs.hp >= int(obs.mhp * 0.85))
        ):
            brain.shopped = True
            alt = brain.explore(obs, view) or brain.hunt(obs, view)
            if alt is not None:
                decision = alt

        snap_path = game.snap(f"turn_{idx:04d}.png", wait_frames=2)
        msgs = (obs.rows[0] + " " + obs.rows[1]).strip()
        records.append(
            TurnRecord(
                index=idx,
                snap_path=snap_path,
                dlvl=obs.dlvl,
                pos=obs.pos,
                hp=obs.hp,
                mhp=obs.mhp,
                mode=obs.mode,
                layer=decision.layer,
                reason=decision.reason,
                messages=msgs,
                creatures_near=creatures_near,
                screen_sig=screen_text,
            )
        )
        obs = game.press(decision.key)
    return records


def record_frame_repeats(rec: TurnRecord) -> int:
    """Hold movement at 5 steps/s and combat/spell/kill frames slightly longer for readability."""
    if IMPORTANT_RE.search(rec.messages):
        return 4
    if (
        rec.mode == Mode.DISMISS
        or FIGHT_RE.search(rec.messages)
        or rec.layer in ("fight", "cast", "pray", "aim", "throw")
    ):
        return 3
    return 2


def select_action_clips(records: list[TurnRecord], num_clips: int = 4) -> list[list[TurnRecord]]:
    """Select 4 non-overlapping 4.5-5.8s action-packed dungeon segments."""
    clean = [
        r for r in records
        if r.dlvl >= 1 and r.mode not in (Mode.CHARGEN, Mode.DEATH)
        and "GENERATING" not in r.screen_sig
        and "Disk Setup" not in r.screen_sig
        and "N)ew" not in r.screen_sig
    ]
    if len(clean) < 20:
        raise RuntimeError(f"Too few valid dungeon turns recorded ({len(clean)})")

    candidates: list[tuple[float, int, int, dict[str, int]]] = []
    n = len(clean)
    for i in range(n):
        if clean[i].mode != Mode.COMMAND:
            continue
        frames = 0
        for j in range(i, n):
            frames += record_frame_repeats(clean[j])
            if frames > MAX_CLIP_FRAMES:
                break
            if frames < MIN_CLIP_FRAMES:
                continue
            if clean[j].mode != Mode.COMMAND:
                continue
            seg = clean[i : j + 1]
            unique_screens = len({r.screen_sig for r in seg})
            if unique_screens < 8:
                continue
            idle_rests = sum(
                1 for r in seg
                if r.mode == Mode.COMMAND and r.layer in ("rest", "fallback") and r.creatures_near == 0
            )
            if idle_rests > len(seg) * 0.35:
                continue
            unique_pos = len({r.pos for r in seg})
            fight_turns = sum(
                1 for r in seg
                if (
                    (r.layer in ("fight", "throw", "aim") or FIGHT_RE.search(r.messages))
                    and "create food" not in r.messages.lower()
                )
            )
            loot_turns = sum(1 for r in seg if LOOT_RE.search(r.messages))
            kills_spells = sum(1 for r in seg if IMPORTANT_RE.search(r.messages))
            seen_turns = sum(1 for r in seg if r.creatures_near > 0)
            dl_changes = sum(1 for k in range(1, len(seg)) if seg[k].dlvl != seg[k - 1].dlvl)
            score = (
                fight_turns * 20.0
                + kills_spells * 18.0
                + seen_turns * 8.0
                + loot_turns * 6.0
                + unique_pos * 2.0
                + dl_changes * 12.0
                - idle_rests * 12.0
            )
            stats = {
                "fights": fight_turns,
                "seen": seen_turns,
                "loot": loot_turns,
                "pos": unique_pos,
            }
            candidates.append((score, i, j + 1, stats))

    if not candidates:
        chosen: list[list[TurnRecord]] = []
        step = max(1, (n - 40) // num_clips)
        for k in range(num_clips):
            start = min(k * step, max(0, n - 45))
            while start < n - 10 and clean[start].mode != Mode.COMMAND:
                start += 1
            frames = 0
            end = start + 1
            while end < n and frames < 48:
                frames += record_frame_repeats(clean[end])
                end += 1
            chosen.append(clean[start:end])
        return chosen

    candidates.sort(key=lambda item: item[0], reverse=True)
    picked: list[tuple[int, int, float, dict[str, int]]] = []
    for score, s, e, stats in candidates:
        if all(e + 4 <= ps or s >= pe + 4 for ps, pe, _, _ in picked):
            picked.append((s, e, score, stats))
            if len(picked) == num_clips:
                break

    if len(picked) < num_clips:
        for score, s, e, stats in candidates:
            if all(e <= ps or s >= pe for ps, pe, _, _ in picked):
                picked.append((s, e, score, stats))
                if len(picked) == num_clips:
                    break

    if len(picked) < num_clips:
        # Relax filters to fill remaining non-overlapping slots cleanly if needed.
        for i in range(n):
            if clean[i].mode != Mode.COMMAND:
                continue
            if any(ps <= i < pe for ps, pe, _, _ in picked):
                continue
            frames = 0
            best_j = None
            for j in range(i, n):
                frames += record_frame_repeats(clean[j])
                if frames > MAX_CLIP_FRAMES:
                    break
                if frames >= MIN_CLIP_FRAMES and clean[j].mode == Mode.COMMAND:
                    best_j = j + 1
                    break
            if best_j is not None and all(best_j <= ps or i >= pe for ps, pe, _, _ in picked):
                picked.append((i, best_j, 0.0, {"fights": 0, "seen": 0, "loot": 0, "pos": len({r.pos for r in clean[i:best_j]})}))
                if len(picked) == num_clips:
                    break

    if len(picked) < num_clips:
        raise RuntimeError(f"Only found {len(picked)} non-overlapping clips from {n} turns")

    picked.sort(key=lambda item: item[0])
    for idx, (s, e, sc, st) in enumerate(picked, 1):
        sample_msgs = [r.messages for r in clean[s:e] if FIGHT_RE.search(r.messages) or LOOT_RE.search(r.messages)]
        sample = sample_msgs[0][:60] if sample_msgs else clean[s].reason[:60]
        print(
            f"  clip {idx}: turns {s}..{e} ({e - s}t, score={sc:.1f}, "
            f"fights={st['fights']}, seen={st['seen']}, loot={st['loot']}, pos={st['pos']}) | {sample!r}",
            flush=True,
        )
    return [clean[s:e] for s, e, _, _ in picked]


def detect_atari_crop(sample_paths: list[Path]) -> tuple[int, int, int, int]:
    """Verify and return active 320x200 ANTIC crop box inside MAME's 335x239 output."""
    x_min, y_min, x_max, y_max = 335, 239, 0, 0
    for p in sample_paths[:30]:
        im = Image.open(p).convert("RGB")
        bbox = im.getbbox()
        if bbox:
            x_min = min(x_min, bbox[0])
            y_min = min(y_min, bbox[1])
            x_max = max(x_max, bbox[2])
            y_max = max(y_max, bbox[3])
    # Active ANTIC 40x25 area begins at (8, 10) for 320x200 inside 335x239.
    x0 = 8 if x_min >= 8 and x_max <= 328 else max(0, min(x_min, 335 - 320))
    y0 = 10 if y_min >= 10 and y_max <= 210 else max(0, min(y_min, 239 - 200))
    return (x0, y0, x0 + 320, y0 + 200)


def normalize_frame(
    platform: str,
    src_path: Path,
    dst_path: Path,
    *,
    atari_crop: tuple[int, int, int, int] = (8, 10, 328, 210),
) -> tuple[int, int]:
    """Crop overscan/bezels, scale with NEAREST where needed, and pad cleanly to 4:3."""
    im = Image.open(src_path).convert("RGB")
    if platform == "apple2":
        # 560x192 -> 2x vertical nearest-neighbor 560x384 -> pad 18px top/bottom to 560x420 (4:3)
        scaled = im.resize((560, 384), Image.NEAREST)
        canvas = Image.new("RGB", (560, 420), (0, 0, 0))
        canvas.paste(scaled, (0, 18))
    elif platform == "atari8":
        # Active 320x200 ANTIC playfield -> centered in 384x288 (4:3, matching C64/Plus4)
        cropped = im.crop(atari_crop)
        canvas = Image.new("RGB", (384, 288), (0, 0, 0))
        canvas.paste(cropped, (32, 44))
    elif platform == "bbcmaster":
        # Active 640x192 Mode 0 bitmap (drops bottom MAME LED bezel) -> 2x vertical 640x384 -> pad to 640x480 (4:3)
        cropped = im.crop((0, 0, 640, 192))
        scaled = cropped.resize((640, 384), Image.NEAREST)
        canvas = Image.new("RGB", (640, 480), (0, 0, 0))
        canvas.paste(scaled, (0, 48))
    else:
        raise ValueError(f"Unknown platform {platform}")
    canvas.save(dst_path)
    return canvas.size


def encode_clip(
    platform: str,
    clip_idx: int,
    seg: list[TurnRecord],
    clip_dir: Path,
    out_gif: Path,
    atari_crop: tuple[int, int, int, int],
) -> tuple[int, int, int, float]:
    """Materialize normalized PNG frames, pack lossless MKV, and encode GIF."""
    shutil.rmtree(clip_dir, ignore_errors=True)
    clip_dir.mkdir(parents=True, exist_ok=True)
    out_gif.parent.mkdir(parents=True, exist_ok=True)

    frame_num = 0
    width = height = 0
    for rec in seg:
        reps = record_frame_repeats(rec)
        for _ in range(reps):
            dst = clip_dir / f"f{frame_num:05d}.png"
            width, height = normalize_frame(platform, rec.snap_path, dst, atari_crop=atari_crop)
            frame_num += 1

    mkv_path = clip_dir.with_suffix(".mkv")
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-framerate", str(TARGET_FPS),
            "-i", str(clip_dir / "f%05d.png"),
            "-c:v", "ffv1",
            str(mkv_path),
        ],
        check=True,
    )
    env = dict(os.environ, FPS=str(TARGET_FPS), COLORS="64", DITHER="none")
    subprocess.run(
        [str(GIF_SCRIPT), str(mkv_path), str(out_gif), "0", "", "-1"],
        check=True,
        env=env,
    )
    return width, height, frame_num, frame_num / TARGET_FPS


def record_platform(platform: str, *, max_turns: int = 550) -> dict[str, Any]:
    port = PORT_BY_NAME[platform]
    scratch = WORK / platform
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True, exist_ok=True)

    ckpt_name = bs.BALROG_ASSIGNMENTS[platform]
    ckpt_dir = BALROG_ROOT / ckpt_name
    raw_balrog = bs.extract_balrog_save(ckpt_name)
    save_bytes = bs.convert_save_for_platform(raw_balrog, platform)
    info = bs.verify_save(save_bytes)
    wor_slot = find_wor_slot(save_bytes)

    disk_copy = scratch / Path(port.disk).name
    shutil.copy2(BUILD / port.disk, disk_copy)
    save_disk = package_save_disk(platform, save_bytes, scratch)
    snap_dir = scratch / "snaps"

    print(
        f"=== {platform}: {info['race']} {info['class']} clvl={info['clvl']} "
        f"maxDL={info['max_dl']} WoR=slot '{wor_slot}' ===",
        flush=True,
    )

    build = launch.Build.shipping(port)
    abi = abimod.load(build.vs, port=port)
    knowledge.use_port(port.platform)

    bbc_fastboot = (
        write_bbc_fastboot_manifest(disk_copy, build.prg.parent / "boot.sym", scratch)
        if platform == "bbcmaster"
        else None
    )

    proc = SnapMameProcess(
        0, scratch, disk_copy, port,
        snap_dir=snap_dir, save_disk=save_disk, bbc_fastboot=bbc_fastboot,
    )
    proc.start(launch.rom_args(port=port), MameGame.tap_spec(abi, port))
    game = SnapMameGame(proc, abi, scratch, port=port)
    try:
        t0 = time.monotonic()
        obs = game.boot()
        print(f"  booted to title in {time.monotonic() - t0:.2f}s", flush=True)

        obs = load_balrog_save(game, obs, platform)
        print(f"  loaded Balrog save in Town: clvl={obs.clvl} hp={obs.hp}/{obs.mhp} pos={obs.pos}", flush=True)

        obs = descend_via_recall(game, obs, info["max_dl"])
        actual_dl = obs.dlvl
        print(f"  arrived on DL{actual_dl} at {obs.pos}", flush=True)

        brain = prepare_brain(platform, ckpt_dir, info, obs)
        records = play_and_capture(game, obs, brain, snap_dir, max_turns=max_turns)
        print(f"  recorded {len(records)} turns in {time.monotonic() - t0:.1f}s total", flush=True)
    finally:
        proc.kill()

    clips = select_action_clips(records, num_clips=4)
    atari_crop = detect_atari_crop([r.snap_path for r in records]) if platform == "atari8" else (0, 0, 0, 0)
    if platform == "atari8":
        print(f"  atari8 active crop: {atari_crop}", flush=True)

    clip_meta = []
    for k, seg in enumerate(clips, 1):
        out_gif = ASSETS / f"moria8-{platform}-gameplay-{k}.gif"
        w, h, nframes, dur = encode_clip(platform, k, seg, scratch / f"clip{k}", out_gif, atari_crop)
        size_b = out_gif.stat().st_size
        clip_meta.append({
            "clip": k,
            "path": str(out_gif),
            "size_bytes": size_b,
            "width": w,
            "height": h,
            "frames": nframes,
            "duration_s": round(dur, 2),
            "dl_range": sorted({r.dlvl for r in seg}),
        })
        print(f"  wrote {out_gif.name}: {w}x{h}, {nframes} frames ({dur:.1f}s), {size_b} B", flush=True)

    return {
        "platform": platform,
        "race": info["race"],
        "class": info["class"],
        "clvl": info["clvl"],
        "dl": actual_dl,
        "clips": clip_meta,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Capture non-wizard Balrog gameplay GIFs on MAME ports.")
    ap.add_argument("--platform", choices=(*MAME_PLATFORMS, "all"), default="all")
    ap.add_argument("--turns", type=int, default=550, help="Dungeon turns to record per platform")
    args = ap.parse_args(argv)

    targets = MAME_PLATFORMS if args.platform == "all" else (args.platform,)
    results = [record_platform(p, max_turns=args.turns) for p in targets]
    print("\n=== SUMMARY ===")
    for res in results:
        sizes = ", ".join(f"c{c['clip']}={c['size_bytes']//1024}KB({c['duration_s']}s)" for c in res["clips"])
        w, h = res["clips"][0]["width"], res["clips"][0]["height"]
        print(f"{res['platform']:10s} | {w}x{h} | {res['race']} {res['class']} clvl {res['clvl']} DL{res['dl']} | {sizes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
