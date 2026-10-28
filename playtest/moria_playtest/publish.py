"""``make playtest-publish``: the dashboard, published as static files.

Every ``--every`` seconds, writes the dashboard page and a snapshot of its data
(the newest round's overview, the M5 milestone grid, M6's port coverage, and
each live worker's focus view) under ``build/playtest/publish/``, then copies
it with ``rsync`` over SSH to ``PLAYTEST_PUBLISH_TARGET`` (for example
``deploy@host:/var/www/playtest/``), using ``PLAYTEST_PUBLISH_KEY`` if set.
Both come from the caller's environment only (AGENTS.md rule 9). The page
reads the static files when it carries the ``playtest-static`` meta tag.

Absolute host paths are stripped from everything published: the page is
public (maintainer, 2026-10-27).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from . import dashboard
from .launch import PLAYTEST_OUT

OUT = PLAYTEST_OUT / "publish"
STATIC_META = '<meta name="playtest-static" content="1">'
HOST_PATH = re.compile(r"(?:/home|/Users|/tmp|/var|/backup|/root)/[^\s\"'|,;)]*")


def scrub(value: Any) -> Any:
    """``value`` with every absolute host path cut down to its last part."""
    if isinstance(value, str):
        return HOST_PATH.sub(lambda m: Path(m.group(0)).name, value)
    if isinstance(value, list):
        return [scrub(v) for v in value]
    if isinstance(value, dict):
        return {k: scrub(v) for k, v in value.items()}
    return value


def worker_file(session: str, worker: int) -> str:
    return f"{session}--w{worker}.json"


def write_json(path: Path, value: Any) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(scrub(value), default=str, separators=(",", ":")))
    tmp.replace(path)


def snapshot(out: Path = OUT) -> dict[str, int]:
    """Write the page and its data under ``out``: what ``rsync`` sends."""
    data = out / "data"
    workers = data / "workers"
    workers.mkdir(parents=True, exist_ok=True)
    overview = dashboard.overview(None)
    overview["rounds"] = [overview["round"]] if overview.get("round") else []
    write_json(data / "overview.json", overview)
    write_json(data / "milestone.json", dashboard.milestone())
    write_json(data / "ports.json", dashboard.ports())
    live = set()
    for suite in overview.get("suites", []):
        for status in suite.get("workers", []):
            if status.get("outcome"):
                continue
            name = worker_file(suite["session"], status["worker"])
            detail = dashboard.worker(suite["session"], status["worker"])
            if detail:
                write_json(workers / name, detail)
                live.add(name)
    for stale in workers.glob("*.json"):
        if stale.name not in live:
            stale.unlink()
    page = dashboard.INDEX.read_text().replace("<head>", "<head>\n" + STATIC_META, 1)
    (out / "index.html").write_text(page)
    return {"suites": len(overview.get("suites", [])), "workers": len(live)}


def push(out: Path, target: str, key: str | None) -> None:
    ssh = ["ssh", "-o", "BatchMode=yes"] + (["-i", key] if key else [])
    subprocess.run(["rsync", "-az", "--delete-after", "-e", " ".join(ssh), f"{out}/", target],
                   check=True, timeout=120)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="playtest-publish")
    parser.add_argument("--every", type=float, default=30.0, help="seconds between snapshots")
    parser.add_argument("--once", action="store_true", help="one snapshot and push, then stop")
    parser.add_argument("--no-push", action="store_true", help="write the snapshot only")
    args = parser.parse_args(argv)
    target = os.environ.get("PLAYTEST_PUBLISH_TARGET", "")
    key = os.environ.get("PLAYTEST_PUBLISH_KEY", "") or None
    if not args.no_push and not target:
        parser.error("PLAYTEST_PUBLISH_TARGET is not set (e.g. deploy@host:/var/www/playtest/)")
    if not args.no_push and not shutil.which("rsync"):
        parser.error("rsync is not installed")
    while True:
        started = time.monotonic()
        try:
            counts = snapshot()
            if not args.no_push:
                push(OUT, target, key)
            print(f"{time.strftime('%H:%M:%S')} published {counts['suites']} suites, "
                  f"{counts['workers']} live workers", flush=True)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"{time.strftime('%H:%M:%S')} publish failed: {error}", file=sys.stderr, flush=True)
        if args.once:
            return 0
        time.sleep(max(1.0, args.every - (time.monotonic() - started)))


if __name__ == "__main__":
    sys.exit(main())
