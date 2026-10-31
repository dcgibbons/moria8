#!/usr/bin/env python3
"""Stand in for x128 in run_tests128.sh: keep what VICE is about to boot.

Before VICE starts, every file named on its command line (disk images,
monitor command files) and the .vs symbol files beside them are copied into
$C128_KEEP_DIR/run-<n>/ with a manifest of their SHA-256 sums and the command
line, and the random seed this script chooses and passes VICE (its power-on
RAM pattern depends on it). Then this process becomes VICE (exec), so
harnesses that wait for or kill the PID they started still talk to VICE.

run_named_suite keeps that directory for a failed suite and, through
``--keep-check DIR``, reports any input that changed on disk after its run
started; ``--keep-drop DIR`` removes a passed suite's. ``--keep-replay DIR/run-<n>``
runs VICE alone on one kept run's copies.
Without C128_KEEP_DIR it only runs VICE.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


# Files VICE writes, not boots: they change during every run.
OUTPUT_OPTIONS = {"-monlogname", "-exitscreenshot"}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def keep(keep_root: Path, args: list[str], seed: int) -> None:
    keep_root.mkdir(parents=True, exist_ok=True)
    run = 1
    while True:   # parallel workers in one suite each claim their own run
        run_dir = keep_root / f"run-{run}"
        try:
            run_dir.mkdir()
            break
        except FileExistsError:
            run += 1
    files: list[Path] = []
    for previous, arg in zip([""] + args, args):
        path = Path(arg)
        if previous not in OUTPUT_OPTIONS and path.is_file():
            files.append(path)
            files.extend(sorted(path.resolve().parent.glob("*.vs")))
    kept = {}
    for path in dict.fromkeys(p.resolve() for p in files):
        copy = run_dir / f"{len(kept):02d}-{path.name}"
        shutil.copyfile(path, copy)
        kept[str(path)] = {"copy": copy.name, "sha256": sha256(copy)}
    (run_dir / "manifest.json").write_text(json.dumps(
        {"cwd": os.getcwd(), "args": args, "seed": seed, "files": kept}, indent=1) + "\n")


def check(keep_root: Path) -> None:
    """For a failed suite: name each kept input that differs on disk now."""
    for manifest in sorted(keep_root.glob("run-*/manifest.json")):
        files = json.loads(manifest.read_text())["files"]
        for original, info in files.items():
            path = Path(original)
            now = sha256(path) if path.is_file() else "gone"
            if now != info["sha256"]:
                state = "gone" if now == "gone" else "changed"
                print(f"    {state} since {manifest.parent.name} started: {original}")


def replay(run_dir: Path) -> int:
    """Run VICE again on one kept run's copies and seed, alone; its log, exit
    screen and output land beside them (replay.log, replay_exit.png,
    replay_vice.txt)."""
    manifest = json.loads((run_dir / "manifest.json").read_text())
    copies = {original: str((run_dir / info["copy"]).resolve())
              for original, info in manifest["files"].items()}
    outputs = {"-monlogname": run_dir / "replay.log", "-exitscreenshot": run_dir / "replay_exit.png"}
    args: list[str] = []
    for previous, arg in zip([""] + manifest["args"], manifest["args"]):
        if previous in outputs:
            args.append(str(outputs[previous].resolve()))
            continue
        path = Path(manifest["cwd"], arg).resolve()
        args.append(copies.get(str(path), arg))
    real = os.environ.get("C128_VICE_REAL", "x128")
    with (run_dir / "replay_vice.txt").open("w") as out:
        return subprocess.run([real, "-seed", str(manifest["seed"])] + args, cwd=manifest["cwd"],
                              stdout=out, stderr=subprocess.STDOUT).returncode


def main() -> None:
    if sys.argv[1:2] == ["--keep-check"]:
        check(Path(sys.argv[2]))
        return
    if sys.argv[1:2] == ["--keep-replay"]:
        raise SystemExit(replay(Path(sys.argv[2])))
    if sys.argv[1:2] == ["--keep-drop"]:   # a passed suite's inputs are not kept
        shutil.rmtree(sys.argv[2], ignore_errors=True)
        return
    real = os.environ["C128_VICE_REAL"]
    args = sys.argv[1:]
    keep_dir = os.environ.get("C128_KEEP_DIR")
    if not keep_dir or "-seed" in args or "--version" in args:
        os.execv(real, [real] + args)
    # VICE seeds its power-on RAM pattern (RAMInitRandomChance) and more from
    # a random seed of its own: choose it here so a replay boots the same RAM.
    seed = int.from_bytes(os.urandom(4), "little") & 0x7FFFFFFF
    try:
        keep(Path(keep_dir), args, seed)
    except OSError as exc:   # keeping is diagnostics: never block the run
        print(f"vice_keep_inputs: {exc}", file=sys.stderr)
    os.execv(real, [real, "-seed", str(seed)] + args)


if __name__ == "__main__":
    main()
