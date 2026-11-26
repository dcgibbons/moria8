#!/usr/bin/env python3
"""Package Moria8 CP/M 2.2 Z80 release media (.zip, Kaypro II .dsk, Kaypro 4 .dsk, C128 .d71).

Outputs:
  1. build/moria8-cpm.zip          RunCPM / generic CP/M 2.2 bundle
                                   (MORIA8.COM, MORIA8.DAT, LICENSE, SOURCE-OFFER, README.TXT)
  2. build/moria8-cpm-kaypro2.dsk  204,800 B Kaypro II SS/DD CP/M 2.2 disk image (`kpii`)
                                   (MORIA8.COM, MORIA8.DAT, LICENSE.TXT, SRCOFFR.TXT)
  3. build/moria8-cpm-kaypro4.dsk  409,600 B Kaypro 4 DS/DD CP/M 2.2 disk image (`kpiv`)
                                   (MORIA8.COM, MORIA8.DAT, LICENSE.TXT, SRCOFFR.TXT)
  4. build/moria8-cpm-c128.d71     349,696 B C128 CP/M Plus 1571 disk image via cformat/ctools
                                   (MORIA8.COM, MORIA8.DAT, LICENSE.TXT, SRCOFFR.TXT)

Standard library only (plus ctools/cformat subprocesses for .d71).
Contains zero external host paths.
"""
from __future__ import annotations

import sys

sys.dont_write_bytecode = True

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

REPO_ROOT = Path(__file__).resolve().parents[1]
TOOLS_DIR = REPO_ROOT / "tools"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))
import version_info  # noqa: E402
DEFAULT_BUILD_DIR = REPO_ROOT / "build" / "cpm"
DEFAULT_OUT_DIR = REPO_ROOT / "build"
DEFAULT_VERSION_FILE = REPO_ROOT / "version.json"
DEFAULT_LICENSE_FILE = REPO_ROOT / "data" / "LICENSE"
DEFAULT_SOURCE_OFFER_FILE = REPO_ROOT / "data" / "SOURCE-OFFER"
DEFAULT_CTOOLS = REPO_ROOT / "tools" / "ctools" / "ctools"
DEFAULT_CFORMAT = REPO_ROOT / "tools" / "ctools" / "cformat"

CPM_RECORD_SIZE = 128


@dataclass(frozen=True)
class KayproGeometry:
    """CP/M 2.2 diskdef geometry for Kaypro disk images (`kpii` / `kpiv`)."""

    label: str
    tracks: int
    sectors_per_track: int
    sector_size: int
    boot_tracks: int
    block_size: int
    dsm: int
    drm: int
    reserved_dir_blocks: int
    exm: int
    min_free_blocks: int

    @property
    def track_bytes(self) -> int:
        return self.sectors_per_track * self.sector_size

    @property
    def image_size(self) -> int:
        return self.tracks * self.track_bytes

    @property
    def data_offset(self) -> int:
        return self.boot_tracks * self.track_bytes

    @property
    def recs_per_block(self) -> int:
        return self.block_size // CPM_RECORD_SIZE

    @property
    def total_blocks(self) -> int:
        return self.dsm + 1

    @property
    def dir_entries(self) -> int:
        return self.drm + 1

    @property
    def dir_entry_size(self) -> int:
        return 32

    @property
    def max_recs_per_entry(self) -> int:
        return 16 * self.recs_per_block


# Kaypro II SS/DD CP/M 2.2 (`kpii`) exact DPB / diskdefs geometry
KAYPRO2_GEOM = KayproGeometry(
    label="Kaypro II",
    tracks=40,
    sectors_per_track=10,
    sector_size=512,
    boot_tracks=1,
    block_size=1024,            # BSH=3, BLM=7
    dsm=194,                    # 195 blocks (0..194)
    drm=63,                     # 64 dir entries (0..63)
    reserved_dir_blocks=2,      # blocks 0..1 reserved for 2,048 B dir
    exm=0,                      # 16 x u8 block ptrs = 16 KB = 1 extent/entry
    min_free_blocks=60,
)

# Kaypro 4 DS/DD CP/M 2.2 (`kpiv`) exact DPB / diskdefs geometry
KAYPRO4_GEOM = KayproGeometry(
    label="Kaypro 4",
    tracks=80,
    sectors_per_track=10,
    sector_size=512,
    boot_tracks=1,
    block_size=2048,            # BSH=4, BLM=15
    dsm=196,                    # 197 blocks (0..196)
    drm=63,                     # 64 dir entries (0..63)
    reserved_dir_blocks=2,      # blocks 0..1: 2,048 B dir + 2,048 B unused 0xE5
    exm=1,                      # 16 x u8 block ptrs = 32 KB = 2 extents/entry
    min_free_blocks=120,
)

KP2_IMAGE_SIZE = KAYPRO2_GEOM.image_size      # 204,800 B
KP2_DATA_OFFSET = KAYPRO2_GEOM.data_offset    # 5,120 B
KP2_BLOCK_SIZE = KAYPRO2_GEOM.block_size      # 1,024 B
KP2_TOTAL_BLOCKS = KAYPRO2_GEOM.total_blocks  # 195
KP2_MIN_FREE_BLOCKS = KAYPRO2_GEOM.min_free_blocks

KP4_TRACKS = KAYPRO4_GEOM.tracks
KP4_SECTORS_PER_TRACK = KAYPRO4_GEOM.sectors_per_track
KP4_SECTOR_SIZE = KAYPRO4_GEOM.sector_size
KP4_TRACK_BYTES = KAYPRO4_GEOM.track_bytes    # 5,120 B
KP4_IMAGE_SIZE = KAYPRO4_GEOM.image_size      # 409,600 B
KP4_BOOT_TRACKS = KAYPRO4_GEOM.boot_tracks
KP4_DATA_OFFSET = KAYPRO4_GEOM.data_offset    # 5,120 B (Track 0 zeroed)
KP4_BLOCK_SIZE = KAYPRO4_GEOM.block_size      # 2,048 B
KP4_RECS_PER_BLOCK = KAYPRO4_GEOM.recs_per_block
KP4_DSM = KAYPRO4_GEOM.dsm
KP4_TOTAL_BLOCKS = KAYPRO4_GEOM.total_blocks  # 197
KP4_DRM = KAYPRO4_GEOM.drm
KP4_DIR_ENTRIES = KAYPRO4_GEOM.dir_entries    # 64
KP4_DIR_ENTRY_SIZE = KAYPRO4_GEOM.dir_entry_size
KP4_RESERVED_DIR_BLOCKS = KAYPRO4_GEOM.reserved_dir_blocks
KP4_EXM = KAYPRO4_GEOM.exm
KP4_MAX_RECS_PER_ENTRY = KAYPRO4_GEOM.max_recs_per_entry
KP4_MIN_FREE_BLOCKS = KAYPRO4_GEOM.min_free_blocks

C128_D71_IMAGE_SIZE = 349696
ZIP_FIXED_TIMESTAMP = (2026, 1, 1, 0, 0, 0)


def pad_to_record(data: bytes, pad_byte: int = 0x00) -> bytes:
    """Pad data up to an exact 128-byte CP/M record boundary."""
    rem = len(data) % CPM_RECORD_SIZE
    if rem == 0:
        return data
    return data + bytes([pad_byte]) * (CPM_RECORD_SIZE - rem)


def to_crlf(raw: bytes) -> bytes:
    """Normalize line endings to CRLF for CP/M text files."""
    normalized = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    if normalized and not normalized.endswith(b"\n"):
        normalized += b"\n"
    return normalized.replace(b"\n", b"\r\n")


def to_cpm_text(raw: bytes, pad_128: bool = True) -> bytes:
    """Convert text to CRLF, append CP/M EOF (0x1A), and optionally zero-pad to 128 B."""
    out = to_crlf(raw) + b"\x1a"
    return pad_to_record(out, 0x00) if pad_128 else out


def format_readme_txt(version: str) -> bytes:
    """Generate CRLF README.TXT describing CP/M runtime requirements and usage."""
    text = f"""MORIA8 FOR CP/M 2.2 (Z80) - v{version}
======================================

SYSTEM REQUIREMENTS
- Z80 CPU running CP/M 2.2 or CP/M Plus (CP/M 3)
- At least 52 KB TPA (BDOS base 0xD100 or higher)
- 80x24 ADM-3A terminal (default) or VT100/ANSI terminal (/V color, /M mono)
- Two files required on the launch drive: MORIA8.COM and MORIA8.DAT

FILES IN THIS RELEASE
- MORIA8.COM     Resident CP/M 2.2 Z80 game executable
- MORIA8.DAT     Random-access overlay and catalog container ('M8CP' v1)
- LICENSE(.TXT)  GNU General Public License v3 notice
- SOURCE-OFFER / SRCOFFR.TXT  Written source code offer

RUNNING MORIA8
1. Place MORIA8.COM and MORIA8.DAT in the same drive/user area.
2. Launch (ADM-3A / Kaypro / C128 CP/M default):
     A>MORIA8
   For VT100/ANSI color terminals (RunCPM, cpm_runner, modern serial):
     A>MORIA8 /V
   For VT100/ANSI monochrome terminals (suppresses ANSI SGR colors):
     A>MORIA8 /M
   Press 'M' on the title screen to cycle [ADM-3A] -> [Color] -> [Mono].

CONTROLS & SAVE DRIVES
- Press '?' in game for command help, 'A' on title or 'L' in help for License/Source.
- Save files (SAVE0.SAV-SAVE3.SAV) and hall-of-heroes records (HISCORE.DAT) default to the
  active drive and support CP/M drives A: through P:.

SUPPORTED PLATFORMS
- RunCPM (POSIX/Windows) - unpack moria8-cpm.zip into drive A/0 and run MORIA8 /V.
- Kaypro II (SS/DD 200 KB) - mount moria8-cpm-kaypro2.dsk (70+ KB free).
- Kaypro 4 (DS/DD 400 KB) - mount moria8-cpm-kaypro4.dsk.
- Commodore 128 CP/M Plus (1571 DS/DD) - mount moria8-cpm-c128.d71.
"""
    return to_crlf(text.encode("ascii"))


def _split_83_name(name: str) -> tuple[bytes, bytes]:
    upper = name.upper()
    if "." in upper:
        stem, ext = upper.split(".", 1)
    else:
        stem, ext = upper, ""
    if not stem or len(stem) > 8 or len(ext) > 3:
        raise ValueError(f"Invalid CP/M 8.3 filename: {name!r}")
    return stem.encode("ascii").ljust(8, b" "), ext.encode("ascii").ljust(3, b" ")


def _build_kaypro_image(geom: KayproGeometry, files: list[tuple[str, bytes]]) -> bytes:
    """Build a Kaypro CP/M 2.2 disk image using ``geom``."""
    buf = bytearray(geom.image_size)
    # Track 0 stays 0x00; reserved directory blocks default to 0xE5.
    dir_start = geom.data_offset
    dir_bytes_total = geom.reserved_dir_blocks * geom.block_size
    buf[dir_start : dir_start + dir_bytes_total] = b"\xe5" * dir_bytes_total

    next_block = geom.reserved_dir_blocks
    dir_idx = 0

    for fname, raw_data in files:
        padded = pad_to_record(raw_data, 0x00)
        total_recs = len(padded) // CPM_RECORD_SIZE
        num_blocks = (len(padded) + geom.block_size - 1) // geom.block_size if padded else 0
        if next_block + num_blocks > geom.total_blocks:
            raise ValueError(
                f"{geom.label} image out of space writing {fname}: need {num_blocks} blocks, "
                f"only {geom.total_blocks - next_block} left"
            )

        file_blocks = list(range(next_block, next_block + num_blocks))
        next_block += num_blocks
        for bi, blk_num in enumerate(file_blocks):
            blk_off = geom.data_offset + blk_num * geom.block_size
            chunk = padded[bi * geom.block_size : (bi + 1) * geom.block_size]
            buf[blk_off : blk_off + len(chunk)] = chunk

        name8, ext3 = _split_83_name(fname)
        if total_recs == 0:
            entries_needed = [(0, 0, [])]
        else:
            entries_needed = []
            rec_cursor = 0
            blk_cursor = 0
            entry_num = 0
            while rec_cursor < total_recs:
                entry_recs = min(geom.max_recs_per_entry, total_recs - rec_cursor)
                entry_blks = (entry_recs + geom.recs_per_block - 1) // geom.recs_per_block
                high_half = 1 if entry_recs > 128 else 0
                ext_val = entry_num * (geom.exm + 1) + high_half
                rc_val = entry_recs - (high_half * 128)
                entries_needed.append(
                    (ext_val, rc_val, file_blocks[blk_cursor : blk_cursor + entry_blks])
                )
                rec_cursor += entry_recs
                blk_cursor += entry_blks
                entry_num += 1

        for ext_val, rc_val, al_blks in entries_needed:
            if dir_idx >= geom.dir_entries:
                raise ValueError(f"{geom.label} directory full (>{geom.dir_entries} entries) at {fname}")
            ent_off = dir_start + dir_idx * geom.dir_entry_size
            entry = bytearray(geom.dir_entry_size)
            entry[0] = 0x00  # User 0
            entry[1:9] = name8
            entry[9:12] = ext3
            entry[12] = ext_val & 0x1F
            entry[13] = 0x00  # S1
            entry[14] = (ext_val >> 5) & 0x3F
            entry[15] = rc_val
            for idx, blk_num in enumerate(al_blks):
                entry[16 + idx] = blk_num
            buf[ent_off : ent_off + geom.dir_entry_size] = entry
            dir_idx += 1

    return bytes(buf)


def _read_kaypro_image(geom: KayproGeometry, img: bytes) -> tuple[dict[str, bytes], int]:
    """Independent pure-Python Kaypro CP/M 2.2 reader and structural validator."""
    if len(img) != geom.image_size:
        raise ValueError(f"{geom.label} image size {len(img)} != {geom.image_size}")
    if img[: geom.data_offset] != b"\x00" * geom.data_offset:
        raise ValueError(f"{geom.label} Track 0 boot region is not zeroed")

    dir_bytes_used = geom.dir_entries * geom.dir_entry_size
    reserved_dir_bytes = geom.reserved_dir_blocks * geom.block_size
    if reserved_dir_bytes > dir_bytes_used:
        unused_off = geom.data_offset + dir_bytes_used
        unused_len = reserved_dir_bytes - dir_bytes_used
        if img[unused_off : unused_off + unused_len] != b"\xe5" * unused_len:
            raise ValueError(f"{geom.label} reserved directory tail is not 0xE5-initialized")

    used_blocks: set[int] = set()
    extents_by_name: dict[str, list[tuple[int, int, list[int]]]] = {}

    for idx in range(geom.dir_entries):
        ent_off = geom.data_offset + idx * geom.dir_entry_size
        ent = img[ent_off : ent_off + geom.dir_entry_size]
        user = ent[0]
        if user == 0xE5:
            continue
        if user > 15:
            raise ValueError(f"Dir entry {idx}: invalid CP/M user {user:#x}")
        name = bytes(b & 0x7F for b in ent[1:9]).decode("ascii").rstrip(" ")
        ext = bytes(b & 0x7F for b in ent[9:12]).decode("ascii").rstrip(" ")
        fname = f"{name}.{ext}" if ext else name
        ex = ent[12]
        s2 = ent[14]
        rc = ent[15]
        if rc > 128:
            raise ValueError(f"Dir entry {idx} ({fname}): RC {rc} > 128")
        logical_ext = (s2 << 5) | ex
        entry_recs = (logical_ext & geom.exm) * 128 + rc
        entry_idx = logical_ext // (geom.exm + 1)

        al_raw = list(ent[16:32])
        expected_blks = (entry_recs + geom.recs_per_block - 1) // geom.recs_per_block if entry_recs else 0
        al_blks = [b for b in al_raw if b != 0]
        if len(al_blks) != expected_blks or al_raw[:expected_blks] != al_blks:
            raise ValueError(
                f"Dir entry {idx} ({fname}): AL count {len(al_blks)} != expected {expected_blks} for {entry_recs} recs"
            )
        for blk in al_blks:
            if not (geom.reserved_dir_blocks <= blk <= geom.dsm):
                raise ValueError(f"Dir entry {idx} ({fname}): block {blk} out of [{geom.reserved_dir_blocks}..{geom.dsm}]")
            if blk in used_blocks:
                raise ValueError(f"Dir entry {idx} ({fname}): duplicate allocation of block {blk}")
            used_blocks.add(blk)

        extents_by_name.setdefault(fname, []).append((entry_idx, entry_recs, al_blks))

    files: dict[str, bytes] = {}
    for fname, ext_list in extents_by_name.items():
        ext_list.sort(key=lambda item: item[0])
        if [item[0] for item in ext_list] != list(range(len(ext_list))):
            raise ValueError(f"{fname}: non-contiguous extent indices {[item[0] for item in ext_list]}")
        out = bytearray()
        for pos, (_eidx, entry_recs, al_blks) in enumerate(ext_list):
            if pos < len(ext_list) - 1 and entry_recs != geom.max_recs_per_entry:
                raise ValueError(f"{fname}: intermediate extent has {entry_recs} != {geom.max_recs_per_entry} records")
            entry_bytes = bytearray()
            for blk in al_blks:
                off = geom.data_offset + blk * geom.block_size
                entry_bytes.extend(img[off : off + geom.block_size])
            out.extend(entry_bytes[: entry_recs * CPM_RECORD_SIZE])
        files[fname] = bytes(out)

    free_blocks = geom.total_blocks - geom.reserved_dir_blocks - len(used_blocks)
    return files, free_blocks


def build_kaypro2_image(files: list[tuple[str, bytes]]) -> bytes:
    """Build a 204,800 B Kaypro II SS/DD CP/M 2.2 (`kpii`) disk image."""
    return _build_kaypro_image(KAYPRO2_GEOM, files)


def read_kaypro2_image(img: bytes) -> tuple[dict[str, bytes], int]:
    """Independent pure-Python Kaypro II CP/M 2.2 (`kpii`) reader and structural validator."""
    return _read_kaypro_image(KAYPRO2_GEOM, img)


def build_kaypro4_image(files: list[tuple[str, bytes]]) -> bytes:
    """Build a 409,600 B Kaypro 4 DS/DD CP/M 2.2 (`kpiv`) disk image."""
    return _build_kaypro_image(KAYPRO4_GEOM, files)


def read_kaypro4_image(img: bytes) -> tuple[dict[str, bytes], int]:
    """Independent pure-Python Kaypro 4 CP/M 2.2 (`kpiv`) reader and structural validator."""
    return _read_kaypro_image(KAYPRO4_GEOM, img)


def atomic_write_bytes(dest: Path, data: bytes) -> None:
    """Write bytes atomically using a temporary sibling file and os.replace."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{dest.name}.", suffix=".tmp", dir=str(dest.parent))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, dest)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def build_zip_bundle(
    dest_zip: Path,
    payloads: list[tuple[str, bytes]],
) -> None:
    """Create and round-trip verify moria8-cpm.zip."""
    dest_zip.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{dest_zip.name}.", suffix=".tmp", dir=str(dest_zip.parent))
    os.close(fd)
    tmp_zip = Path(tmp_name)
    try:
        with zipfile.ZipFile(tmp_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for name, data in payloads:
                zi = zipfile.ZipInfo(filename=name, date_time=ZIP_FIXED_TIMESTAMP)
                zi.compress_type = zipfile.ZIP_DEFLATED
                zi.external_attr = 0o644 << 16
                zf.writestr(zi, data)

        with zipfile.ZipFile(tmp_zip, "r") as zf:
            bad = zf.testzip()
            if bad is not None:
                raise ValueError(f"Zip CRC failure on {bad}")
            names = zf.namelist()
            expected_names = [name for name, _ in payloads]
            if names != expected_names:
                raise ValueError(f"Zip entries {names} != {expected_names}")
            for name, expected_data in payloads:
                got = zf.read(name)
                if got != expected_data:
                    raise ValueError(f"Zip round-trip mismatch on {name} ({len(got)} vs {len(expected_data)})")

        os.chmod(tmp_zip, 0o644)
        os.replace(tmp_zip, dest_zip)
    except Exception:
        tmp_zip.unlink(missing_ok=True)
        raise


def _build_kaypro_disk(
    geom: KayproGeometry,
    dest_dsk: Path,
    files: list[tuple[str, bytes]],
    min_free_blocks: int,
) -> int:
    """Create, write atomically, and independently verify a Kaypro .dsk image."""
    img = _build_kaypro_image(geom, files)
    extracted, free_blocks = _read_kaypro_image(geom, img)
    expected_names = {name for name, _ in files}
    if set(extracted.keys()) != expected_names:
        raise ValueError(f"{geom.label} directory mismatch: {set(extracted.keys())} != {expected_names}")
    for name, raw in files:
        expected_padded = pad_to_record(raw, 0x00)
        if extracted[name] != expected_padded:
            raise ValueError(
                f"{geom.label} round-trip mismatch on {name} ({len(extracted[name])} vs {len(expected_padded)})"
            )
        if extracted[name][: len(raw)] != raw:
            raise ValueError(f"{geom.label} prefix mismatch on {name}")
    if free_blocks < min_free_blocks:
        raise ValueError(f"{geom.label} free blocks {free_blocks} < required {min_free_blocks}")
    atomic_write_bytes(dest_dsk, img)
    return free_blocks


def build_kaypro2_disk(
    dest_dsk: Path,
    files: list[tuple[str, bytes]],
    min_free_blocks: int = KP2_MIN_FREE_BLOCKS,
) -> int:
    """Create, write atomically, and independently verify Kaypro II .dsk image."""
    return _build_kaypro_disk(KAYPRO2_GEOM, dest_dsk, files, min_free_blocks)


def build_kaypro4_disk(
    dest_dsk: Path,
    files: list[tuple[str, bytes]],
    min_free_blocks: int = KP4_MIN_FREE_BLOCKS,
) -> int:
    """Create, write atomically, and independently verify Kaypro 4 .dsk image."""
    return _build_kaypro_disk(KAYPRO4_GEOM, dest_dsk, files, min_free_blocks)


def _resolve_tool(explicit: Path | None, env_var: str, default_path: Path) -> Path:
    if explicit is not None:
        return explicit
    env_val = os.environ.get(env_var, "").strip()
    if env_val:
        return Path(env_val)
    return default_path


def _check_executable(tool_path: Path, label: str) -> str:
    if tool_path.is_file() and os.access(tool_path, os.X_OK):
        return str(tool_path.resolve())
    if len(tool_path.parts) == 1:
        found = shutil.which(str(tool_path))
        if found:
            return found
    raise FileNotFoundError(
        f"{label} binary not found or not executable: {tool_path} (run tools/ensure_ctools.sh)"
    )


def build_c128_d71(
    dest_d71: Path,
    files: list[tuple[str, bytes]],
    ctools_bin: Path,
    cformat_bin: Path,
) -> None:
    """Create and round-trip verify 349,696 B C128 CP/M Plus .d71 image via cformat + ctools."""
    ctools_exe = _check_executable(ctools_bin, "ctools")
    cformat_exe = _check_executable(cformat_bin, "cformat")

    dest_d71.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{dest_d71.name}.", suffix=".tmp", dir=str(dest_d71.parent))
    os.close(fd)
    tmp_d71 = Path(tmp_name)
    # Remove empty placeholder so cformat creates a fresh image cleanly.
    tmp_d71.unlink(missing_ok=True)

    try:
        subprocess.run([cformat_exe, "-2", str(tmp_d71)], check=True, capture_output=True, text=True)
        with tempfile.TemporaryDirectory(prefix="cpm_d71_stage_") as td:
            stage = Path(td)
            staged_paths: list[str] = []
            for fname, raw in files:
                fpath = stage / fname
                fpath.write_bytes(raw)
                staged_paths.append(str(fpath))

            subprocess.run(
                [ctools_exe, str(tmp_d71), "p", *staged_paths],
                check=True,
                capture_output=True,
                text=True,
            )

            d71_size = tmp_d71.stat().st_size
            if d71_size != C128_D71_IMAGE_SIZE:
                raise ValueError(f"C128 .d71 size {d71_size} != {C128_D71_IMAGE_SIZE}")

            extract_dir = stage / "extract"
            extract_dir.mkdir()
            for fname, raw in files:
                subprocess.run(
                    [ctools_exe, str(tmp_d71), "g", fname],
                    cwd=extract_dir,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                cand = extract_dir / fname.lower()
                if not cand.is_file():
                    cand = extract_dir / fname
                if not cand.is_file():
                    raise FileNotFoundError(f"ctools g {fname} produced no output file in {extract_dir}")
                got = cand.read_bytes()
                # ctools pads non-128-aligned writes with 0x1A and extracts 128 B record multiples.
                expected = pad_to_record(raw, 0x1A)
                if got != expected:
                    raise ValueError(
                        f"C128 .d71 round-trip mismatch on {fname} ({len(got)} B vs expected {len(expected)} B)"
                    )

        os.chmod(tmp_d71, 0o644)
        os.replace(tmp_d71, dest_d71)
    except subprocess.CalledProcessError as exc:
        tmp_d71.unlink(missing_ok=True)
        raise RuntimeError(
            f"ctools/cformat failed ({exc.cmd}):\nstdout: {exc.stdout}\nstderr: {exc.stderr}"
        ) from exc
    except Exception:
        tmp_d71.unlink(missing_ok=True)
        raise


def load_release_inputs(
    build_dir: Path,
    version_file: Path,
    license_file: Path,
    source_offer_file: Path,
    *,
    channel: str | None = None,
    build_num: str | None = None,
    suffix: str | None = None,
) -> dict[str, bytes]:
    """Load MORIA8.COM, MORIA8.DAT, LICENSE, SOURCE-OFFER, and resolved CP/M version."""
    com_path = build_dir / "MORIA8.COM"
    dat_path = build_dir / "MORIA8.DAT"
    if not com_path.is_file():
        raise FileNotFoundError(f"Missing {com_path}")
    if not dat_path.is_file():
        raise FileNotFoundError(f"Missing {dat_path}")
    if not license_file.is_file():
        raise FileNotFoundError(f"Missing {license_file}")
    if not source_offer_file.is_file():
        raise FileNotFoundError(f"Missing {source_offer_file}")
    cpm_ver = version_info.resolve_port_version(
        version_file,
        "cpm",
        channel=channel,
        build_num=build_num,
        suffix=suffix,
    ).bare

    com_bytes = com_path.read_bytes()
    dat_bytes = dat_path.read_bytes()
    if len(dat_bytes) % CPM_RECORD_SIZE != 0 or dat_bytes[:4] != b"M8CP":
        raise ValueError(f"Invalid MORIA8.DAT at {dat_path} ({len(dat_bytes)} B)")

    lic_raw = license_file.read_bytes()
    src_raw = source_offer_file.read_bytes()
    return {
        "com": com_bytes,
        "dat": dat_bytes,
        "license_crlf": to_crlf(lic_raw),
        "srcoffr_crlf": to_crlf(src_raw),
        "license_cpm": to_cpm_text(lic_raw, pad_128=True),
        "srcoffr_cpm": to_cpm_text(src_raw, pad_128=True),
        "readme_crlf": format_readme_txt(cpm_ver),
    }


def package_all(
    build_dir: Path,
    zip_path: Path | None,
    kaypro4_path: Path | None,
    c128_d71_path: Path | None,
    ctools_bin: Path,
    cformat_bin: Path,
    version_file: Path = DEFAULT_VERSION_FILE,
    license_file: Path = DEFAULT_LICENSE_FILE,
    source_offer_file: Path = DEFAULT_SOURCE_OFFER_FILE,
    kaypro2_path: Path | None = None,
    channel: str | None = None,
    build_num: str | None = None,
    suffix: str | None = None,
) -> dict[str, str]:
    """Build requested CP/M release packages and return human-readable status lines."""
    inputs = load_release_inputs(
        build_dir,
        version_file,
        license_file,
        source_offer_file,
        channel=channel,
        build_num=build_num,
        suffix=suffix,
    )
    results: dict[str, str] = {}

    if zip_path is not None:
        zip_payloads = [
            ("MORIA8.COM", inputs["com"]),
            ("MORIA8.DAT", inputs["dat"]),
            ("LICENSE", inputs["license_crlf"]),
            ("SOURCE-OFFER", inputs["srcoffr_crlf"]),
            ("README.TXT", inputs["readme_crlf"]),
        ]
        build_zip_bundle(zip_path, zip_payloads)
        results["zip"] = f"{zip_path} ({zip_path.stat().st_size} B, {len(zip_payloads)} files)"

    disk_files = [
        ("MORIA8.COM", inputs["com"]),
        ("MORIA8.DAT", inputs["dat"]),
        ("LICENSE.TXT", inputs["license_cpm"]),
        ("SRCOFFR.TXT", inputs["srcoffr_cpm"]),
    ]

    if kaypro2_path is not None:
        free_blocks2 = build_kaypro2_disk(kaypro2_path, disk_files)
        results["kaypro2"] = (
            f"{kaypro2_path} ({kaypro2_path.stat().st_size} B, "
            f"{free_blocks2}/{KP2_TOTAL_BLOCKS} free blocks = {free_blocks2 * KP2_BLOCK_SIZE} B)"
        )

    if kaypro4_path is not None:
        free_blocks = build_kaypro4_disk(kaypro4_path, disk_files)
        results["kaypro4"] = (
            f"{kaypro4_path} ({kaypro4_path.stat().st_size} B, "
            f"{free_blocks}/{KP4_TOTAL_BLOCKS} free blocks = {free_blocks * KP4_BLOCK_SIZE} B)"
        )

    if c128_d71_path is not None:
        build_c128_d71(c128_d71_path, disk_files, ctools_bin, cformat_bin)
        results["c128_d71"] = f"{c128_d71_path} ({c128_d71_path.stat().st_size} B, 4 files verified)"

    return results


class _MakeCpmDiskSelfTest(unittest.TestCase):
    def test_text_conversion_and_padding(self) -> None:
        self.assertEqual(to_crlf(b"A\nB\r\nC\rD"), b"A\r\nB\r\nC\r\nD\r\n")
        cpm = to_cpm_text(b"LINE1\nLINE2\n", pad_128=True)
        self.assertEqual(len(cpm), 128)
        self.assertTrue(cpm.startswith(b"LINE1\r\nLINE2\r\n\x1a"))
        self.assertEqual(cpm[15:], b"\x00" * (128 - 15))
        readme = format_readme_txt("2.0.0")
        self.assertIn(b"MORIA8 FOR CP/M 2.2 (Z80) - v2.0.0\r\n", readme)
        self.assertNotIn(b"\n", readme.replace(b"\r\n", b""))
        rc_readme = format_readme_txt("2.1.0-rc1")
        self.assertIn(b"MORIA8 FOR CP/M 2.2 (Z80) - v2.1.0-rc1\r\n", rc_readme)

    def test_kaypro4_geometry_multi_extent_and_corruption_detection(self) -> None:
        com = bytes((i * 17 + 3) & 0xFF for i in range(21641))
        dat = b"M8CP" + bytes((i * 29 + 1) & 0xFF for i in range(100224 - 4))
        lic = to_cpm_text(b"MORIA8 LICENSE NOTICE\nLINE 2\n")
        src = to_cpm_text(b"MORIA8 SOURCE OFFER\nLINE 2\n")
        files = [
            ("MORIA8.COM", com),
            ("MORIA8.DAT", dat),
            ("LICENSE.TXT", lic),
            ("SRCOFFR.TXT", src),
        ]
        img = build_kaypro4_image(files)
        self.assertEqual(len(img), KP4_IMAGE_SIZE)
        self.assertEqual(img[:KP4_DATA_OFFSET], b"\x00" * KP4_DATA_OFFSET)
        extracted, free_blocks = read_kaypro4_image(img)
        self.assertGreaterEqual(free_blocks, KP4_MIN_FREE_BLOCKS)
        self.assertEqual(extracted["MORIA8.COM"], pad_to_record(com, 0x00))
        self.assertEqual(extracted["MORIA8.DAT"], dat)
        self.assertEqual(extracted["LICENSE.TXT"], lic)
        self.assertEqual(extracted["SRCOFFR.TXT"], src)

        # Corrupt Track 0 -> rejected
        bad_t0 = bytearray(img)
        bad_t0[0] = 0xAA
        with self.assertRaises(ValueError):
            read_kaypro4_image(bytes(bad_t0))

        # Corrupt duplicate block pointer -> rejected
        bad_dup = bytearray(img)
        bad_dup[KP4_DATA_OFFSET + 32 + 16] = bad_dup[KP4_DATA_OFFSET + 16]
        with self.assertRaises(ValueError):
            read_kaypro4_image(bytes(bad_dup))

    def test_kaypro2_geometry_multi_extent_and_corruption_detection(self) -> None:
        com = bytes((i * 19 + 5) & 0xFF for i in range(21641))
        dat = b"M8CP" + bytes((i * 31 + 7) & 0xFF for i in range(100224 - 4))
        lic = to_cpm_text(b"MORIA8 LICENSE NOTICE\nLINE 2\n")
        src = to_cpm_text(b"MORIA8 SOURCE OFFER\nLINE 2\n")
        files = [
            ("MORIA8.COM", com),
            ("MORIA8.DAT", dat),
            ("LICENSE.TXT", lic),
            ("SRCOFFR.TXT", src),
        ]
        img = build_kaypro2_image(files)
        self.assertEqual(len(img), KP2_IMAGE_SIZE)
        self.assertEqual(img[:KP2_DATA_OFFSET], b"\x00" * KP2_DATA_OFFSET)
        extracted, free_blocks = read_kaypro2_image(img)
        self.assertGreaterEqual(free_blocks, KP2_MIN_FREE_BLOCKS)
        self.assertEqual(extracted["MORIA8.COM"], pad_to_record(com, 0x00))
        self.assertEqual(extracted["MORIA8.DAT"], dat)
        self.assertEqual(extracted["LICENSE.TXT"], lic)
        self.assertEqual(extracted["SRCOFFR.TXT"], src)

        bad_t0 = bytearray(img)
        bad_t0[0] = 0xAA
        with self.assertRaises(ValueError):
            read_kaypro2_image(bytes(bad_t0))

        bad_dup = bytearray(img)
        bad_dup[KP2_DATA_OFFSET + 32 + 16] = bad_dup[KP2_DATA_OFFSET + 16]
        with self.assertRaises(ValueError):
            read_kaypro2_image(bytes(bad_dup))

    def test_package_all_end_to_end(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            bdir = root / "build_cpm"
            bdir.mkdir()
            com = bytes((i * 7 + 1) & 0xFF for i in range(21641))
            dat = b"M8CP" + b"\x01\x19" + bytes((i * 11) & 0xFF for i in range(100224 - 6))
            (bdir / "MORIA8.COM").write_bytes(com)
            (bdir / "MORIA8.DAT").write_bytes(dat)
            lic_file = root / "LICENSE"
            src_file = root / "SOURCE-OFFER"
            ver_file = root / "version.json"
            lic_file.write_bytes(DEFAULT_LICENSE_FILE.read_bytes())
            src_file.write_bytes(DEFAULT_SOURCE_OFFER_FILE.read_bytes())
            ver_file.write_text('{"cpm": "2.0.0"}\n', encoding="utf-8")

            zip_out = root / "out" / "moria8-cpm.zip"
            kp2_out = root / "out" / "moria8-cpm-kaypro2.dsk"
            dsk_out = root / "out" / "moria8-cpm-kaypro4.dsk"
            d71_out = (
                (root / "out" / "moria8-cpm-c128.d71")
                if (DEFAULT_CTOOLS.is_file() and DEFAULT_CFORMAT.is_file())
                else None
            )
            res = package_all(
                build_dir=bdir,
                zip_path=zip_out,
                kaypro2_path=kp2_out,
                kaypro4_path=dsk_out,
                c128_d71_path=d71_out,
                ctools_bin=DEFAULT_CTOOLS,
                cformat_bin=DEFAULT_CFORMAT,
                version_file=ver_file,
                license_file=lic_file,
                source_offer_file=src_file,
                channel="release",
                build_num="",
                suffix="",
            )
            self.assertIn("zip", res)
            self.assertIn("kaypro2", res)
            self.assertIn("kaypro4", res)
            self.assertEqual(zip_out.stat().st_mode & 0o777, 0o644)
            self.assertEqual(kp2_out.stat().st_mode & 0o777, 0o644)
            self.assertEqual(dsk_out.stat().st_mode & 0o777, 0o644)
            with zipfile.ZipFile(zip_out, "r") as zf:
                self.assertEqual(
                    zf.namelist(),
                    ["MORIA8.COM", "MORIA8.DAT", "LICENSE", "SOURCE-OFFER", "README.TXT"],
                )
                self.assertEqual(zf.read("MORIA8.COM"), com)
                self.assertEqual(zf.read("MORIA8.DAT"), dat)
                self.assertIn(b"\r\n", zf.read("LICENSE"))
                self.assertIn(b"\r\n", zf.read("SOURCE-OFFER"))
            if d71_out is not None:
                self.assertIn("c128_d71", res)
                self.assertEqual(d71_out.stat().st_size, C128_D71_IMAGE_SIZE)
                self.assertEqual(d71_out.stat().st_mode & 0o777, 0o644)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR, help="CP/M build dir (default: build/cpm)")
    parser.add_argument("--zip", type=Path, default=None, help="Output path for moria8-cpm.zip")
    parser.add_argument("--kaypro2", type=Path, default=None, help="Output path for moria8-cpm-kaypro2.dsk")
    parser.add_argument("--kaypro4", type=Path, default=None, help="Output path for moria8-cpm-kaypro4.dsk")
    parser.add_argument("--c128-d71", type=Path, default=None, help="Output path for moria8-cpm-c128.d71")
    parser.add_argument("--ctools", type=Path, default=None, help="Path to ctools executable")
    parser.add_argument("--cformat", type=Path, default=None, help="Path to cformat executable")
    parser.add_argument("--selftest", action="store_true", help="Run unit self-tests")
    args = parser.parse_args(argv)

    if args.selftest:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(_MakeCpmDiskSelfTest)
        return 0 if unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful() else 1

    ctools_bin = _resolve_tool(args.ctools, "CTOOLS", DEFAULT_CTOOLS)
    cformat_bin = _resolve_tool(args.cformat, "CFORMAT", DEFAULT_CFORMAT)

    zip_path = args.zip
    kaypro2_path = args.kaypro2
    kaypro4_path = args.kaypro4
    c128_d71_path = args.c128_d71
    if zip_path is None and kaypro2_path is None and kaypro4_path is None and c128_d71_path is None:
        zip_path = DEFAULT_OUT_DIR / "moria8-cpm.zip"
        kaypro2_path = DEFAULT_OUT_DIR / "moria8-cpm-kaypro2.dsk"
        kaypro4_path = DEFAULT_OUT_DIR / "moria8-cpm-kaypro4.dsk"
        c128_d71_path = DEFAULT_OUT_DIR / "moria8-cpm-c128.d71"

    results = package_all(
        build_dir=args.build_dir,
        zip_path=zip_path,
        kaypro2_path=kaypro2_path,
        kaypro4_path=kaypro4_path,
        c128_d71_path=c128_d71_path,
        ctools_bin=ctools_bin,
        cformat_bin=cformat_bin,
    )
    for key, line in results.items():
        print(f"make_cpm_disk [{key}]: {line}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
