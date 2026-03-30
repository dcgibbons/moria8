#!/usr/bin/env python3
"""diskart.py -- Patch PETSCII directory art into a d64 disk image.

Replaces the first placeholder directory entries (created by c1541 as
dummy PRG files) with zero-block DEL entries whose filenames use
PETSCII graphic characters to create a title card in the directory
listing.

Usage: python3 tools/diskart.py <d64-file>
"""

import sys

# D64 track geometry: sectors per track (index 0 unused)
SECTORS_PER_TRACK = [0] + [21]*17 + [19]*7 + [18]*6 + [17]*5


def sector_offset(track, sector):
    """Byte offset in d64 for a given track/sector."""
    off = 0
    for t in range(1, track):
        off += SECTORS_PER_TRACK[t] * 256
    return off + sector * 256


BAM_OFF = sector_offset(18, 0)
DIR_OFF = sector_offset(18, 1)

# PETSCII art filenames (16 bytes each)
# $60 = horizontal bar in unshifted charset
HLINE = bytes([0x60] * 16)

def art_line(text):
    return text.upper().encode("ascii").ljust(16, b" ")


def directory_entry_offset(data, index):
    """Byte offset of directory entry `index`, following the sector chain.

    Returns the legacy base used by this script: two bytes before the
    actual 32-byte entry, so the existing +2/+3/+5 field offsets stay
    aligned across directory sectors.
    """
    track = 18
    sector = 1
    remaining = index

    while remaining >= 8:
        sec_off = sector_offset(track, sector)
        track = data[sec_off]
        sector = data[sec_off + 1]
        if track == 0:
            raise RuntimeError(f"Directory too short for art entry {index}")
        remaining -= 8

    return sector_offset(track, sector) + remaining * 32

ART = [
    HLINE,
    art_line("  dungeons  of  "),
    art_line("     moria      "),
    art_line(" c64/c128  v1.0 "),
    HLINE,
]


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <d64-file>")
        sys.exit(1)

    with open(sys.argv[1], "r+b") as f:
        data = bytearray(f.read())

    for i, name in enumerate(ART):
        off = directory_entry_offset(data, i)

        # Free the data block in BAM (c1541 allocated 1 block per dummy file)
        trk = data[off + 3]
        sec = data[off + 4]
        if trk > 0:
            bam = BAM_OFF + 4 * trk
            data[bam] += 1                              # increment free count
            data[bam + 1 + sec // 8] |= 1 << (sec % 8)  # mark sector free

        # Convert to 0-block DEL entry with PETSCII filename
        data[off + 2] = 0x80                # DEL file type
        data[off + 3] = 0                   # no data track
        data[off + 4] = 0                   # no data sector
        data[off + 5 : off + 21] = name     # 16-byte PETSCII filename
        data[off + 28] = 0                  # 0 blocks lo
        data[off + 29] = 0                  # 0 blocks hi

    with open(sys.argv[1], "wb") as f:
        f.write(data)

    print(f"Directory art: patched {len(ART)} entries in {sys.argv[1]}")


if __name__ == "__main__":
    main()
