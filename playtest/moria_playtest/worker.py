"""One worker: an owned VICE process, its Game driver, snapshots and restart (§6.1, §6.7).

Cold boot loads every tier and overlay into the REU through the true-drive
1541. The first boot of a build dumps a title-screen snapshot into
``build/playtest/cache/<key>/``; later starts undump it instead of booting.
Every snapshot gets a ``.brain.json`` beside it, because bot memory is not part
of VICE state.
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass, field
from pathlib import Path

from . import abi as abimod
from .game import Game, Observation
from .launch import (PLAYTEST_OUT, SHIPPING, Build, ViceProcess, allocate_port, check_disk,
                     prepare_worker, rom_args, sha256)
from .mame import MameGame, MameProcess
from .x16 import X16Game, X16Process

CACHE = PLAYTEST_OUT / "cache"


def cache_key(emulator: str, build: Build = SHIPPING) -> str:
    # A title snapshot taken under one KERNAL is not restored under another.
    roms = rom_args(port=build.target)
    material = "|".join([sha256(build.prg), sha256(build.disk), emulator, *build.target.resource_args,
                         *(sha256(Path(a)) if i % 2 else a for i, a in enumerate(roms))])
    return hashlib.sha256(material.encode()).hexdigest()[:16]


@dataclass
class Snapshot:
    path: Path
    brain: dict[str, object] = field(default_factory=dict)

    @property
    def brain_path(self) -> Path:
        return self.path.with_suffix(".brain.json")

    def save_brain(self) -> None:
        self.brain_path.write_text(json.dumps(self.brain, indent=1, sort_keys=True))

    def delete(self) -> None:
        self.path.unlink(missing_ok=True)
        self.brain_path.unlink(missing_ok=True)
        for side in self.path.parent.glob(f"{self.path.stem}.*"):   # ports.Port.snapshot_banks
            side.unlink(missing_ok=True)

    @classmethod
    def load(cls, path: Path) -> "Snapshot":
        brain_path = path.with_suffix(".brain.json")
        brain = json.loads(brain_path.read_text()) if brain_path.exists() else {}
        return cls(path, brain)


class Worker:
    def __init__(self, run_dir: Path, worker_id: int = 0, *, emulator: str | None = None,
                 hang_emulated_seconds: float = 300.0, build: Build = SHIPPING) -> None:
        self.run_dir = run_dir
        self.worker_id = worker_id
        self.emulator = emulator or build.target.emulator
        self.hang_emulated_seconds = hang_emulated_seconds
        self.build = build
        check_disk(build)
        self.workdir, self.disk = prepare_worker(run_dir, worker_id, build.disk)
        self.abi = abimod.load(build.vs, port=build.target)
        self.vp: ViceProcess | MameProcess | None = None
        self.game: Game | None = None
        self.restarts = 0

    # -- lifecycle --------------------------------------------------------

    def _spawn(self, autostart: bool) -> Game:
        self.stop()
        port = self.build.target
        if port.backend == "mame":
            process = MameProcess(self.worker_id, self.workdir, self.disk, port,
                                  self.hang_emulated_seconds)
            self.vp = process.start(rom_args(port=port), MameGame.tap_spec(self.abi, port))   # type: ignore[assignment]
            self.game = MameGame(process, self.abi, self.workdir, port=port,
                                 hang_emulated_seconds=self.hang_emulated_seconds)
            return self.game
        if port.backend == "x16":
            process = X16Process(self.worker_id, self.workdir, self.disk, port)
            emulator = os.environ.get("X16EMU") or port.emulator
            self.vp = process.start_x16(emulator, rom_args(port=port)[1])   # type: ignore[assignment]
            self.game = X16Game(process, self.abi, self.workdir, port=port)
            return self.game
        self.vp = ViceProcess(self.worker_id, self.workdir, self.disk,
                              allocate_port(self.worker_id), self.emulator, self.build.target)
        monitor = self.vp.start(autostart=autostart)
        self.game = Game(monitor, self.abi, self.workdir,
                         hang_emulated_seconds=self.hang_emulated_seconds, port=self.build.target)
        return self.game

    def stop(self) -> None:
        if self.vp is not None:
            self.vp.kill()
        self.vp = None
        self.game = None

    def title_snapshot(self) -> Path:
        """Cached title-screen snapshot for this build and resource set."""
        path = CACHE / cache_key(self.emulator, self.build) / "title.vsf"
        if not path.exists():
            game = self._spawn(autostart=True)
            game.boot()
            # Unique per process: concurrent sessions each have a worker 3,
            # and one's rename removed the other's file (M5a round 3).
            tmp = path.with_suffix(f".tmp{os.getpid()}.vsf")
            game.dump(tmp)
            for bank in self.build.target.snapshot_banks:   # beside it, before it appears
                tmp.with_suffix(f".{bank}").replace(path.with_suffix(f".{bank}"))
            tmp.replace(path)
            self.stop()
        return path

    def start_at_title(self) -> Observation:
        """Fresh VICE with the private disk attached, resumed from the title
        snapshot; a port without snapshots boots."""
        if not self.build.target.snapshots:
            return self._spawn(autostart=True).boot()
        title = self.title_snapshot()
        return self._spawn(autostart=False).undump(title)

    def restore(self, snapshot: Snapshot) -> Observation:
        """Kill-and-restart path: new VICE process, then undump the snapshot."""
        self.restarts += 1
        game = self._spawn(autostart=False)
        obs = game.undump(snapshot.path)
        seed = snapshot.brain.get("seed")
        if isinstance(seed, int):
            game.seed = seed
        return obs

    # -- snapshots --------------------------------------------------------

    def snapshot(self, name: str, brain: dict[str, object]) -> Snapshot | None:
        """None on a port that cannot snapshot (``Port.snapshots``)."""
        if not self.build.target.snapshots:
            return None
        assert self.game is not None
        snap = Snapshot(self.workdir / "snapshots" / f"{name}.vsf", dict(brain))
        self.game.dump(snap.path)
        snap.save_brain()
        return snap
