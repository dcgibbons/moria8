"""``make playtest-repro FINDING=<findings/Fnnnn.json>``: replay a finding.

Undumps the finding's snapshot (with the brain/auditor state saved beside it),
feeds the recorded keys one per input stop, and checks that the same finding
(kind and detail) occurs again.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import nav
from .auditor import Auditor
from .game import GameFault, Mode
from .launch import PLAYTEST_OUT, Build
from .worker import Snapshot, Worker


def reproduce(finding_path: Path) -> tuple[bool, str]:
    finding = json.loads(finding_path.read_text())
    if not finding.get("snapshot"):
        return False, "finding has no snapshot to replay from"
    snapshot = Snapshot.load(Path(finding["snapshot"]))
    build = Build(**{k: v if k == "port" else Path(v) for k, v in finding["build"].items()})
    worker = Worker(PLAYTEST_OUT / "repro" / finding_path.stem, build=build)
    auditor = Auditor()
    auditor.command_sp = snapshot.brain.get("auditor_command_sp")
    try:
        obs = worker.restore(snapshot)
        game = worker.game
        assert game is not None
        keys = list(finding["keys"])
        for index in range(len(keys) + 1):
            tiles = nav.read_map(game) if obs.mode == Mode.COMMAND else None
            for found in auditor.check(obs, tiles):
                if (found.kind, found.detail) == (finding["kind"], finding["detail"]):
                    return True, f"reproduced after {index} of {len(keys)} keys"
            if index == len(keys):
                break
            try:
                obs = game.press(keys[index])
            except GameFault as fault:
                same = (fault.kind, fault.detail) == (finding["kind"], finding["detail"])
                return same, f"{fault.kind}: {fault.detail} after {index + 1} keys"
        return False, f"replayed {len(keys)} keys without the finding"
    finally:
        worker.stop()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-repro")
    parser.add_argument("finding", type=Path)
    args = parser.parse_args(argv)
    ok, detail = reproduce(args.finding)
    print(f"{args.finding.name}: {'REPRODUCED' if ok else 'NOT REPRODUCED'} ({detail})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
