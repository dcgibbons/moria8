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
from dataclasses import dataclass, field
from pathlib import Path

from . import abi as abimod
from .game import Game, Observation
from .launch import (PLAYTEST_OUT, SHIPPING, VICE_RESOURCE_ARGS, Build, ViceProcess,
                     allocate_port, prepare_worker, sha256)

CACHE = PLAYTEST_OUT / "cache"


def cache_key(emulator: str, build: Build = SHIPPING) -> str:
    material = "|".join([sha256(build.prg), sha256(build.disk), emulator, *VICE_RESOURCE_ARGS])
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

    @classmethod
    def load(cls, path: Path) -> "Snapshot":
        brain_path = path.with_suffix(".brain.json")
        brain = json.loads(brain_path.read_text()) if brain_path.exists() else {}
        return cls(path, brain)


class Worker:
    def __init__(self, run_dir: Path, worker_id: int = 0, *, emulator: str = "x64sc",
                 hang_emulated_seconds: float = 300.0, build: Build = SHIPPING) -> None:
        self.run_dir = run_dir
        self.worker_id = worker_id
        self.emulator = emulator
        self.hang_emulated_seconds = hang_emulated_seconds
        self.build = build
        self.workdir, self.disk = prepare_worker(run_dir, worker_id, build.disk)
        self.abi = abimod.load(build.vs)
        self.vp: ViceProcess | None = None
        self.game: Game | None = None
        self.restarts = 0

    # -- lifecycle --------------------------------------------------------

    def _spawn(self, autostart: bool) -> Game:
        self.stop()
        self.vp = ViceProcess(self.worker_id, self.workdir, self.disk,
                              allocate_port(self.worker_id), self.emulator)
        monitor = self.vp.start(autostart=autostart)
        self.game = Game(monitor, self.abi, self.workdir,
                         hang_emulated_seconds=self.hang_emulated_seconds)
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
            tmp = path.with_suffix(f".tmp{self.worker_id}.vsf")
            game.dump(tmp)
            tmp.replace(path)
            self.stop()
        return path

    def start_at_title(self) -> Observation:
        """Fresh VICE with the private disk attached, resumed from the title snapshot."""
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

    def snapshot(self, name: str, brain: dict[str, object]) -> Snapshot:
        assert self.game is not None
        snap = Snapshot(self.workdir / "snapshots" / f"{name}.vsf", dict(brain))
        self.game.dump(snap.path)
        snap.save_brain()
        return snap
