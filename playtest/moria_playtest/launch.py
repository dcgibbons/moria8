"""VICE process launch, worker isolation, and owned-process cleanup (§6.1, §6.7).

Each worker gets its own directory under ``build/playtest/<run>/w<N>/`` holding
a private copy of the shipping disk image and the VICE log. VICE resources are
pinned on the command line so every run uses the same machine configuration;
the resource set is recorded with every result.
"""

from __future__ import annotations

import ctypes
import hashlib
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

from .ports import C64, PORTS, Port
from .vice import ViceMonitor

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
PLAYTEST_OUT = BUILD / "playtest"
C64_DISK = BUILD / "moria8-c64.d64"
C64_PRG = BUILD / "c64" / "moria8.prg"
C64_VS = BUILD / "c64" / "main.vs"


@dataclass(frozen=True)
class Build:
    """A build to play: disk image, main program, its symbols, and its port."""

    disk: Path
    prg: Path
    vs: Path
    port: str = C64.name

    @property
    def target(self) -> Port:
        return PORTS[self.port]

    @classmethod
    def from_out(cls, out: Path, port: Port = C64) -> "Build":
        """Layout produced by ``make -C platforms/commodore OUT=<out> ...``."""
        return cls(out / port.disk, out / port.out / port.program, out / port.out / port.symbols, port.name)

    @classmethod
    def shipping(cls, port: Port = C64) -> "Build":
        return cls.from_out(BUILD, port)


SHIPPING = Build(C64_DISK, C64_PRG, C64_VS)

# Disk file -> the build output it is written from (platforms/commodore/Makefile,
# the disk64 recipe), relative to the program's directory.
C64_DISK_FILES = C64.disk_files

D64_TRACKS = 35
D64_SIZE = 174848   # 683 sectors; a D71 is two of these, tracks 36-70 on side 2


def d64_offset(track: int, sector: int) -> int:
    """Byte offset of a 1541 sector: 21 sectors on tracks 1-17, 19 on 18-24,
    18 on 25-30, 17 on 31-35; a 1571's tracks 36-70 repeat them on side 2."""
    side, track = divmod(track - 1, D64_TRACKS)
    before = sum(21 if t <= 17 else 19 if t <= 24 else 18 if t <= 30 else 17 for t in range(1, track + 1))
    return side * D64_SIZE + (before + sector) * 256


def d64_files(image: bytes) -> dict[str, bytes]:
    """The closed PRG files of a 35-track D64 or 70-track D71 image, by name."""
    tracks = D64_TRACKS * (len(image) // D64_SIZE)

    def blocks(track: int, sector: int):  # type: ignore[no-untyped-def]
        seen = set()
        while track:
            if not 1 <= track <= tracks or (track, sector) in seen:
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
    stale disk then fails every worker at boot. A disk this module cannot read
    (ProDOS) must at least be newer than its program."""
    if build.disk.is_dir():   # the X16's -fsroot: the build output itself
        return
    if not build.target.disk_files:
        if build.disk.stat().st_mtime < build.prg.stat().st_mtime:
            raise StaleDisk(f"{build.disk} is older than {build.prg}; "
                            f"rebuild it with `make {build.target.disk_target}`")
        return
    files = d64_files(build.disk.read_bytes())
    stale = sorted(name for name, out in build.target.disk_files.items()
                   if files.get(name) != (build.prg.parent / out).read_bytes())
    if stale:
        raise StaleDisk(f"{build.disk} does not match {build.prg.parent} ({', '.join(stale)}); "
                        f"rebuild it with `make {build.target.disk_target}`")

BASE_PORT = 6600

VICE_RESOURCE_ARGS = C64.resource_args
ROM_ENV = C64.rom_env


def rom_args(env: dict[str, str] | None = None, port: Port = C64) -> list[str]:
    """VICE arguments for the ROM images the environment names."""
    env = os.environ if env is None else env
    missing = [var for var in port.required_roms if not env.get(var, "")]
    if missing:
        raise FileNotFoundError(f"{port.name} plays under named ROM images: set {', '.join(missing)}")
    args: list[str] = []
    for var, option in port.rom_env:
        path = env.get(var, "")
        if not path:
            continue
        if not Path(path).exists():   # an image, or MAME's ROM directory
            raise FileNotFoundError(f"{var}={path}: no such ROM image")
        args += [option, str(Path(path).resolve())]
    return args


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
    target: Port = C64
    proc: subprocess.Popen[bytes] | None = None
    monitor: ViceMonitor | None = None
    args: list[str] = field(default_factory=list)
    log_path: Path | None = None

    def start(self, *, autostart: bool = True, connect_timeout: float = 30.0,
              response_timeout: float = 60.0) -> ViceMonitor:
        exe = find_vice(self.emulator)
        config = str(write_vice_config(exe, self.workdir))
        self.args = [exe, *(config if a == "VICE_CONFIG" else a for a in self.target.resource_args),
                     *rom_args(port=self.target),
                     "-binarymonitor", "-binarymonitoraddress", f"127.0.0.1:{self.port}"]
        if autostart:
            self.args += ["-autostart", str(self.disk)]
        else:
            self.args += ["-8", str(self.disk)]
        self.log_path = self.workdir / "vice.log"
        log = self.log_path.open("ab")
        self.proc = subprocess.Popen(
            self.args, cwd=self.workdir, stdin=subprocess.DEVNULL, stdout=log,
            stderr=subprocess.STDOUT, start_new_session=True, preexec_fn=parent_death_hook())
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
    if disk_template.is_dir():   # the X16 boots from a directory (-fsroot)
        shutil.copytree(disk_template, disk, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns("*.sym", "*.vs", "mame"))
    else:
        shutil.copyfile(disk_template, disk)
    return workdir, disk


PR_SET_PDEATHSIG = 1
# Looked up here, not in the forked child, where only async-signal-safe work belongs.
_PRCTL = ctypes.CDLL(None, use_errno=True).prctl if sys.platform.startswith("linux") else None


def die_with_parent() -> None:
    """In the emulator child (Linux): SIGKILL when the thread that started it
    exits for any reason. Its own session keeps it from our signals, so a
    harness that died without stop() left emulators running for hours."""
    _PRCTL(PR_SET_PDEATHSIG, signal.SIGKILL)


def parent_death_hook():
    """preexec_fn for an emulator child, or None. Linux sends the signal when
    the forking *thread* exits, so a child started from a pool thread (m0.py)
    would die with that thread: only the main thread arms it."""
    if _PRCTL is None or threading.current_thread() is not threading.main_thread():
        return None
    return die_with_parent


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
        "disk_sha256": sha256(build.disk if build.disk.is_file() else build.prg),
        "program_sha256": sha256(build.prg),
        "symbols_sha256": sha256(build.vs),
    }
