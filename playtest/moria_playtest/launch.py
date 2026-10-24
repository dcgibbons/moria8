"""VICE process launch, worker isolation, and owned-process cleanup (§6.1, §6.7).

Each worker gets its own directory under ``build/playtest/<run>/w<N>/`` holding
a private copy of the shipping disk image and the VICE log. VICE resources are
pinned on the command line so every run uses the same machine configuration;
the resource set is recorded with every result.
"""

from __future__ import annotations

import hashlib
import os
import re
import shutil
import signal
import socket
import subprocess
import time
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

from .vice import ViceMonitor

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
PLAYTEST_OUT = BUILD / "playtest"
C64_DISK = BUILD / "moria8-c64.d64"
C64_PRG = BUILD / "c64" / "moria8.prg"
C64_VS = BUILD / "c64" / "main.vs"


@dataclass(frozen=True)
class Build:
    """A C64 build to play: disk image, main program, and its symbols."""

    disk: Path
    prg: Path
    vs: Path

    @classmethod
    def from_out(cls, out: Path) -> "Build":
        """Layout produced by ``make -C platforms/commodore OUT=<out> ...``."""
        return cls(out / "moria8-c64.d64", out / "c64" / "moria8.prg", out / "c64" / "main.vs")


SHIPPING = Build(C64_DISK, C64_PRG, C64_VS)

# Disk file -> the build output it is written from (platforms/commodore/Makefile,
# the disk64 recipe), relative to the program's directory.
C64_DISK_FILES = {
    "moria8": "boot.prg", "boot64": "boot.prg", "bootart64": "bootart64.prg",
    "moria64": "moria8.prg", "t64": "title",
    **{f"monster.db.{tier}": f"monster.db.{tier}" for tier in range(1, 5)},
    **{f"64.{name}": f"ovl.{name}" for name in
       ("start", "town", "death", "modal", "gen", "help", "ui", "items", "spell", "chest")},
    "64.bank": "64.bank",
}

D64_TRACKS = 35


def d64_offset(track: int, sector: int) -> int:
    """Byte offset of a 1541 sector: 21 sectors on tracks 1-17, 19 on 18-24,
    18 on 25-30, 17 on 31-35."""
    before = sum(21 if t <= 17 else 19 if t <= 24 else 18 if t <= 30 else 17 for t in range(1, track))
    return (before + sector) * 256


def d64_files(image: bytes) -> dict[str, bytes]:
    """The closed PRG files of a 35-track D64 image, by name."""
    def blocks(track: int, sector: int):  # type: ignore[no-untyped-def]
        seen = set()
        while track:
            if not 1 <= track <= D64_TRACKS or (track, sector) in seen:
                raise ValueError(f"bad sector chain at {track}/{sector}")
            seen.add((track, sector))
            block = image[d64_offset(track, sector):d64_offset(track, sector) + 256]
            yield block
            track, sector = block[0], block[1]

    def contents(track: int, sector: int) -> bytes:
        # The last block's sector link is the index of its last used byte.
        return b"".join(block[2:] if block[0] else block[2:block[1] + 1]
                        for block in blocks(track, sector))

    files = {}
    for block in blocks(18, 1):   # the directory: 8 entries of 32 bytes per sector
        for entry in range(0, 256, 32):
            if block[entry + 2] == 0x82:   # closed PRG
                # PETSCII unshifted letters ($41-$5A) are what c1541 lists as lower case.
                name = block[entry + 5:entry + 21].rstrip(b"\xa0").decode("latin-1").lower()
                files[name] = contents(block[entry + 3], block[entry + 4])
    return files


class StaleDisk(RuntimeError):
    """The disk image was not written from the program and symbols beside it."""


def check_disk(build: Build) -> None:
    """Every program file on the disk must equal the build output it is written
    from: ``make test`` rebuilds the program and symbols without the disk, and a
    stale disk then fails every worker at boot."""
    files = d64_files(build.disk.read_bytes())
    stale = sorted(name for name, out in C64_DISK_FILES.items()
                   if files.get(name) != (build.prg.parent / out).read_bytes())
    if stale:
        raise StaleDisk(f"{build.disk} does not match {build.prg.parent} ({', '.join(stale)}); "
                        "rebuild it with `make disk64`")

BASE_PORT = 6600

# Pinned machine configuration (§6.1). REU is mandatory: without it every
# overlay switch and tier crossing reloads from the 1541.
VICE_RESOURCE_ARGS = (
    # +saveres is required: without it VICE tries to save resources through
    # GTK on exit and aborts when no display connection is available.
    # VICE_CONFIG stands for a per-worker config naming the installed VICE
    # version: an empty one (/dev/null) made VICE pop up "No version tag
    # found in config file" on the desktop for every instance.
    "-default", "-config", "VICE_CONFIG", "+saveres",
    "-console", "+sound", "-sounddev", "dummy",
    "-warp", "-pal", "-seed", "1",
    "-reu", "-reusize", "512",
    "-drive8type", "1541", "-drive8truedrive",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


@lru_cache(maxsize=None)
def vice_version(exe: str) -> str:
    """The installed VICE's version, as its config files must name it."""
    out = subprocess.run([exe, "--version"], capture_output=True, text=True, timeout=30).stdout
    match = re.search(r"VICE (\d+(?:\.\d+)+)", out)
    return match.group(1) if match else ""


def write_vice_config(exe: str, workdir: Path) -> Path:
    """An otherwise empty VICE config carrying the version tag VICE expects."""
    path = workdir / "vicerc"
    path.write_text(f"[Version]\nConfigVersion={vice_version(exe)}\n")
    return path


def find_vice(name: str = "x64sc") -> str:
    path = shutil.which(name)
    if path is None:
        raise FileNotFoundError(f"{name} not found in PATH")
    return path


def port_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


@dataclass
class ViceProcess:
    """One owned VICE process and its monitor connection."""

    worker: int
    workdir: Path
    disk: Path
    port: int
    emulator: str = "x64sc"
    proc: subprocess.Popen[bytes] | None = None
    monitor: ViceMonitor | None = None
    args: list[str] = field(default_factory=list)
    log_path: Path | None = None

    def start(self, *, autostart: bool = True, connect_timeout: float = 30.0,
              response_timeout: float = 60.0) -> ViceMonitor:
        exe = find_vice(self.emulator)
        config = str(write_vice_config(exe, self.workdir))
        self.args = [exe, *(config if a == "VICE_CONFIG" else a for a in VICE_RESOURCE_ARGS),
                     "-binarymonitor", "-binarymonitoraddress", f"127.0.0.1:{self.port}"]
        if autostart:
            self.args += ["-autostart", str(self.disk)]
        else:
            self.args += ["-8", str(self.disk)]
        self.log_path = self.workdir / "vice.log"
        log = self.log_path.open("ab")
        self.proc = subprocess.Popen(
            self.args, cwd=self.workdir, stdin=subprocess.DEVNULL, stdout=log,
            stderr=subprocess.STDOUT, start_new_session=True)
        log.close()
        self.monitor = ViceMonitor(port=self.port, response_timeout=response_timeout)
        try:
            self.monitor.connect(time.monotonic() + connect_timeout)
        except Exception:
            self.kill()
            raise
        return self.monitor

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def kill(self, grace: float = 2.0) -> None:
        """Terminate this worker's own process group only (never killall)."""
        if self.monitor is not None:
            self.monitor.close()
            self.monitor = None
        proc, self.proc = self.proc, None
        if proc is None or proc.poll() is not None:
            return
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
        try:
            proc.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=grace)


def prepare_worker(run_dir: Path, worker: int, disk_template: Path = C64_DISK) -> tuple[Path, Path]:
    """Create the worker directory and its private disk copy."""
    workdir = run_dir / f"w{worker}"
    workdir.mkdir(parents=True, exist_ok=True)
    disk = workdir / disk_template.name
    shutil.copyfile(disk_template, disk)
    return workdir, disk


def allocate_port(worker: int, attempts: int = 20) -> int:
    """Fixed per-worker port range with retries on a busy port."""
    for offset in range(attempts):
        port = BASE_PORT + worker * attempts + offset
        if port_free(port):
            return port
    raise RuntimeError(f"no free monitor port for worker {worker}")


def build_identity(build: Build = SHIPPING) -> dict[str, str]:
    return {
        "disk": str(build.disk.relative_to(ROOT)) if build.disk.is_relative_to(ROOT) else str(build.disk),
        "disk_sha256": sha256(build.disk),
        "program_sha256": sha256(build.prg),
        "symbols_sha256": sha256(build.vs),
    }
