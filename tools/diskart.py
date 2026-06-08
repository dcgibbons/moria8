#!/usr/bin/env python3
"""diskart.py -- Patch PETSCII directory art into a CBM disk image.

Replaces the first placeholder directory entries (created by c1541 as
dummy PRG files) with zero-block DEL entries whose filenames use
PETSCII graphic characters to create a title card in the directory
listing.

Usage: python3 tools/diskart.py <disk-file> <platform>
"""

import json
import sys
from pathlib import Path

SECTORS_1541 = [0] + [21]*17 + [19]*7 + [18]*6 + [17]*5
SECTORS_1571 = SECTORS_1541 + SECTORS_1541[1:]
SECTORS_1581 = [0] + [40] * 80


def detect_geometry(image_size):
    if image_size == 174848:
        return ("d64", SECTORS_1541, 18, 1)
    if image_size == 349696:
        return ("d71", SECTORS_1571, 18, 1)
    if image_size == 819200:
        return ("d81", SECTORS_1581, 40, 3)
    raise ValueError(f"unsupported disk image size {image_size}")


def sector_offset(track, sector, sectors_per_track):
    """Byte offset in a CBM disk image for a given track/sector."""
    off = 0
    for t in range(1, track):
        off += sectors_per_track[t] * 256
    return off + sector * 256


def bam_entry_offset(track, image_kind, sectors_per_track):
    if image_kind == "d81":
        bam_track = 40
        bam_sector = 1 if track <= 40 else 2
        bam_slot = track if track <= 40 else track - 40
        bam_base = sector_offset(bam_track, bam_sector, sectors_per_track)
        return bam_base + 0x10 + 6 * (bam_slot - 1)
    if image_kind == "d64" or track <= 35:
        bam_track = 18
        bam_slot = track
    else:
        bam_track = 53
        bam_slot = track - 35
    bam_base = sector_offset(bam_track, 0, sectors_per_track)
    return bam_base + 4 * bam_slot

HLINE = bytes([0x60] * 16)
VERSION_FILE = Path(__file__).resolve().parents[1] / "version.json"

def art_line(text):
    return text.upper().encode("ascii").ljust(16, b" ")


def centered_art_line(text):
    return art_line(text.center(16))


def load_versions():
    raw = json.loads(VERSION_FILE.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("version.json must be a JSON object")
    versions = {}
    for platform in ("c64", "c128", "plus4"):
        value = raw.get(platform)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"version.json missing string version for {platform}")
        versions[platform] = value.strip()
    return versions


def build_art(platform, version):
    display_version = version if version.lower().startswith("v") else f"v{version}"
    return [
        HLINE,
        centered_art_line("dungeons of"),
        centered_art_line(f"moria {platform}"),
        centered_art_line(display_version),
        HLINE,
    ]


def directory_entry_offset(data, index, dir_track, dir_sector, sectors_per_track):
    """Byte offset of directory entry `index`, following the sector chain.

    Returns the legacy base used by this script: two bytes before the
    actual 32-byte entry, so the existing +2/+3/+5 field offsets stay
    aligned across directory sectors.
    """
    track = dir_track
    sector = dir_sector
    remaining = index

    while remaining >= 8:
        sec_off = sector_offset(track, sector, sectors_per_track)
        track = data[sec_off]
        sector = data[sec_off + 1]
        if track == 0:
            raise RuntimeError(f"Directory too short for art entry {index}")
        remaining -= 8

    return sector_offset(track, sector, sectors_per_track) + remaining * 32

def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <disk-file> <platform>")
        sys.exit(1)

    platform = sys.argv[2].lower()
    if platform not in ("c64", "c128", "plus4"):
        print(f"Unknown platform '{platform}' (expected c64, c128, or plus4)")
        sys.exit(1)

    versions = load_versions()

    with open(sys.argv[1], "r+b") as f:
        data = bytearray(f.read())

    image_kind, sectors_per_track, dir_track, dir_sector = detect_geometry(len(data))
    art = build_art(platform, versions[platform])

    for i, name in enumerate(art):
        off = directory_entry_offset(data, i, dir_track, dir_sector, sectors_per_track)

        # Free the data block in BAM (c1541 allocated 1 block per dummy file)
        trk = data[off + 3]
        sec = data[off + 4]
        if trk > 0:
            bam = bam_entry_offset(trk, image_kind, sectors_per_track)
            data[bam] += 1                              # increment free count
            data[bam + 1 + sec // 8] |= 1 << (sec % 8)  # mark sector free

        # Convert to 0-block DEL entry with PETSCII filename
        data[off + 2] = 0x80                # DEL file type
        data[off + 3] = 0                   # no data track
        data[off + 4] = 0                   # no data sector
        data[off + 5 : off + 21] = name     # 16-byte PETSCII filename
        data[off + 30] = 0                  # 0 blocks lo
        data[off + 31] = 0                  # 0 blocks hi

    with open(sys.argv[1], "wb") as f:
        f.write(data)

    print(f"Directory art: patched {len(art)} entries for {platform} in {sys.argv[1]}")


if __name__ == "__main__":
    main()
