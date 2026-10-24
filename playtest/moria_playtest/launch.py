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
