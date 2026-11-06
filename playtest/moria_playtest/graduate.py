"""Balrog starts as a saved game, for ports whose mid-game snapshots do not
restore (``Port.graduate_save``, §23.9).

VICE 3.10's C128 snapshot leaves out the VDC: restored, it replays every
raster line from the new emulator's power-on clock to the snapshot's before
the CPU runs, about 50 s of wall time per 2.5 emulated hours, without
answering the monitor (2026-11-02: every C128 Balrog run from a DL28 start
timed out). A graduate there saves its game through the real UI to a save
disk in drive 9 instead; a Balrog run boots, loads that save from the title
and goes on with the graduate's brain.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

from .disk import TextMonitor, blank_d64
from .game import Mode, Observation

KEY_SAVE = 0xD3   # SHIFT+S: save and quit
SAVE_DISK = "save.d64"
BRAIN = "graduate.vsf"   # the name the brain files hang off (session.brain_pickle_path)
TEXT_MONITOR_WORKER = 500   # launch.allocate_port range far above the binary monitors'


class GraduateError(Exception):
    """The save or the load did not go through the screens it should."""


def drive9_args(image: Path, text_port: int) -> tuple[str, ...]:
    """VICE options: drive 9 with ``image`` in it, and the text monitor that
    flushes it (the binary monitor cannot attach images)."""
    return ("-remotemonitor", "-remotemonitoraddress", f"127.0.0.1:{text_port}",
            "-drive9type", "1541", "-drive9truedrive", "-9", str(image))


def fresh_disk(run_dir: Path) -> Path:
    return blank_d64(run_dir / SAVE_DISK)


def _screen(obs: Observation) -> str:
    return "\n".join(obs.rows)


def _press(game: Any, text: TextMonitor, key: int | str) -> Observation:
    text.drain()   # the text monitor writes a prompt at each stop: a full socket blocks VICE
    return game.press(ord(key) if isinstance(key, str) else key)


def _expect(obs: Observation, want: str) -> None:
    if want.lower() not in _screen(obs).lower():
        raise GraduateError(f"expected {want!r} on screen:\n{_screen(obs)}")


# The save's screens and their keys: a first save goes through Disk Setup
# (Done with the shown save drive 9), takes the disk and initializes it; a
# game loaded from the save disk goes straight to the slots and overwrites
# slot 1 (a Balrog checkpoint, 2026-11-05).
SAVE_SCREENS = (("Disk Setup", "3"), ("Insert a Save Disk", " "), ("Initialize this disk?", "Y"),
                ("Select Slot", "1"), ("Overwrite?", "Y"), ("-more-", " "))


def save(game: Any, text: TextMonitor, image: Path) -> None:
    """At the command prompt, SHIFT+S, then slot 1 through the screens
    SAVE_SCREENS names; the save ends at the title. Then reattach ``image``:
    true drive emulation writes its tracks to the file only then
    (disk.save_first_time, Rig.flush)."""
    obs = _press(game, text, KEY_SAVE)
    for _ in range(12):
        screen = _screen(obs).lower()
        if "n)ew  l)oad" in screen:
            break
        # The last match: "Overwrite?" and "-more-" show below the slot list.
        keys = [(screen.rfind(want.lower()), key) for want, key in SAVE_SCREENS if want.lower() in screen]
        if not keys:
            raise GraduateError(f"unexpected screen saving the game:\n{_screen(obs)}")
        obs = _press(game, text, max(keys)[1])
    _expect(obs, "N)ew  L)oad")
    out = text.command(f'attach "{image}" 9')
    if "error" in out.lower():
        raise GraduateError(f"flush of {image.name}: {out.strip()}")


def load(game: Any, text: TextMonitor) -> Observation:
    """From the title: L)oad, Disk Setup's Done (the save disk is in drive
    9), slot 1, back at the command prompt."""
    obs = _press(game, text, "L")
    for _ in range(12):
        if obs.mode == Mode.COMMAND:
            return obs
        screen = _screen(obs)
        if "Select Slot" in screen:
            obs = _press(game, text, "1")
        elif "3) Done" in screen:
            obs = _press(game, text, "3")
        elif "Press any key" in screen or "Insert" in screen:
            obs = _press(game, text, " ")
        else:
            raise GraduateError(f"unexpected screen loading the save:\n{screen}")
    raise GraduateError(f"the load never reached the command prompt:\n{_screen(obs)}")


def keep(run_dir: Path, image: Path, state: dict[str, Any], brain: Any, name: str = "graduate") -> Path:
    """A start: the save disk, brain and state, in run_dir/``name`` (the
    graduate's, or a Balrog run's checkpoint)."""
    from .session import save_brain
    dest = run_dir / name
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copy2(image, dest / SAVE_DISK)
    (dest / BRAIN).with_suffix(".brain.json").write_text(json.dumps(state, indent=1))
    if not save_brain(brain, dest / BRAIN):
        raise GraduateError("the brain could not be saved")
    return dest
