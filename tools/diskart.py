#!/usr/bin/env python3
"""diskart.py -- Patch PETSCII directory art into a d64 disk image.

Replaces the first 5 placeholder directory entries (created by c1541
as dummy PRG files) with zero-block DEL entries whose filenames use
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

ART = [
    HLINE,
    bytes([0x20,0x20, 0x44,0x55,0x4E,0x47,0x45,0x4F,0x4E,0x53,
           0x20,0x20, 0x4F,0x46, 0x20,0x20]),              # "  DUNGEONS  OF  "
    bytes([0x20,0x20,0x20,0x20,0x20,
           0x4D,0x4F,0x52,0x49,0x41,
           0x20,0x20,0x20,0x20,0x20,0x20]),                 # "     MORIA      "
    bytes([0x20, 0x43,0x36,0x34,0x2F,0x43,0x31,0x32,0x38,
           0x20,0x20, 0x56,0x31,0x2E,0x30, 0x20]),          # " C64/C128  V1.0 "
    HLINE,
]


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <d64-file>")
        sys.exit(1)

    with open(sys.argv[1], "r+b") as f:
        data = bytearray(f.read())

    for i, name in enumerate(ART):
        off = DIR_OFF + i * 32

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
