#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path


SCENARIO_DEVICES = {
    "media_drive8_attach_read_write": (8,),
    "media_drive9_attach_read_write": (9,),
    "media_drive10_11_device_probe": (10, 11),
}


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=10.0,
    )


def c1541(args: argparse.Namespace, *parts: str) -> subprocess.CompletedProcess[str]:
    return run([args.c1541, *parts])


def fail(message: str, output: str = "") -> int:
    print(f"FAIL: {message}")
    if output:
        print(output[-2000:])
    return 2


def probe_device(args: argparse.Namespace, work_dir: Path, device: int) -> int:
    disk_path = work_dir / f"{args.platform}-{args.scenario}-drive{device}.d64"
    marker_path = work_dir / f"probe-drive{device}.bin"
    readback_path = work_dir / f"readback-drive{device}.bin"
    disk_name = f"m8{args.platform}{device}"[:16]
    file_name = f"probe{device}"
    marker = f"{args.platform}:{args.scenario}:drive{device}\n".encode("ascii")

    marker_path.write_bytes(marker)
    completed = c1541(args, "-format", f"{disk_name},m8", "d64", str(disk_path))
    if completed.returncode != 0:
        return fail(f"{args.scenario} drive {device} format failed", completed.stdout)

    completed = c1541(
        args,
        "-attach",
        str(disk_path),
        "-write",
        str(marker_path),
        f"{file_name},seq",
    )
    if completed.returncode != 0:
        return fail(f"{args.scenario} drive {device} write failed", completed.stdout)

    completed = c1541(args, "-attach", str(disk_path), "-list")
    if completed.returncode != 0:
        return fail(f"{args.scenario} drive {device} listing failed", completed.stdout)
    if file_name not in completed.stdout.lower():
        return fail(f"{args.scenario} drive {device} listing did not include {file_name}", completed.stdout)

    completed = c1541(
        args,
        "-attach",
        str(disk_path),
        "-read",
        f"{file_name},s",
        str(readback_path),
    )
    if completed.returncode != 0:
        return fail(f"{args.scenario} drive {device} read failed", completed.stdout)
    if readback_path.read_bytes() != marker:
        return fail(f"{args.scenario} drive {device} readback mismatch")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Shared disk media attach/read/write sanity probes")
    parser.add_argument("--scenario", required=True, choices=tuple(SCENARIO_DEVICES))
    parser.add_argument("--platform", required=True, choices=("c64", "c128", "plus4"))
    parser.add_argument("--c1541", default="c1541")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix=f"moria8-{args.scenario}-") as tmp:
        work_dir = Path(tmp)
        for device in SCENARIO_DEVICES[args.scenario]:
            rc = probe_device(args, work_dir, device)
            if rc != 0:
                return rc

    print(f"PASS: {args.scenario} {args.platform}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
