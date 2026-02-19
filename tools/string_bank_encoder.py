#!/usr/bin/env python3
"""
String bank encoder for C64 Moria — generates PRG-format string bank files.

Builds the Huffman tree from the SAME corpus as the main game encoder
(data/huffman_strings.txt), then encodes a separate set of bank strings
into a PRG file that loads at $E000.

PRG format:
  Bytes 0-1: Load address ($00, $E0) — standard C64 PRG header
  Byte 2:   String count (1 byte)
  Bytes 3-4: Offset from byte 2 to compressed data start (16-bit LE)
  Index table: count x 2 bytes — 16-bit LE offsets from compressed data
               start to each string
  Compressed data: Huffman-encoded bitstreams, null-terminated

Usage:
  python3 tools/string_bank_encoder.py data/huffman_strings.txt data/recall_strings.txt out/bank.recall

  Arg 1: main corpus (for building the Huffman tree — same as main game)
  Arg 2: strings to encode into the bank
  Arg 3: output PRG file
"""

import sys
import os

# Add tools directory to path so we can import from huff_encoder
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from huff_encoder import (
    ascii_to_screencode,
    build_tree,
    build_codes,
    compress_string,
)
from collections import Counter


def parse_corpus(path):
    """
    Parse a string file (comments, blank lines, @LABEL support).
    Returns list of screencode lists — identical parsing to huff_encoder.py.
    """
    with open(path) as f:
        raw_lines = [line.rstrip('\n') for line in f]

    strings = []
    for raw in raw_lines:
        line = raw.rstrip('\n\r')
        check = line.strip()
        if not check or check.startswith('#'):
            continue
        trimmed = line.lstrip()
        if trimmed.startswith('@'):
            space_pos = trimmed.index(' ')
            text = trimmed[space_pos + 1:]
        else:
            text = trimmed

        # Handle trailing space marker: " ~" at end -> trailing space
        if text.endswith(' ~'):
            text = text[:-1]  # Remove ~, keep the space

        screencodes = [ascii_to_screencode(ch) for ch in text]
        strings.append(screencodes)

    return strings


def parse_bank_strings(path):
    """
    Parse the bank string file. Same format as corpus.
    Returns (strings, display_lines, labels) where:
      strings: list of screencode lists
      display_lines: original text for diagnostics
      labels: dict of index -> label name
    """
    with open(path) as f:
        raw_lines = [line.rstrip('\n') for line in f]

    strings = []
    display_lines = []
    labels = {}

    for raw in raw_lines:
        line = raw.rstrip('\n\r')
        check = line.strip()
        if not check or check.startswith('#'):
            continue
        trimmed = line.lstrip()
        if trimmed.startswith('@'):
            space_pos = trimmed.index(' ')
            label = trimmed[1:space_pos]
            text = trimmed[space_pos + 1:]
        else:
            label = None
            text = trimmed

        # Handle trailing space marker: " ~" at end -> trailing space
        if text.endswith(' ~'):
            text = text[:-1]

        idx = len(strings)
        screencodes = [ascii_to_screencode(ch) for ch in text]
        strings.append(screencodes)
        display_lines.append(text)
        if label:
            labels[idx] = label

    return strings, display_lines, labels


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <corpus.txt> <bank_strings.txt> <output.prg>",
              file=sys.stderr)
        sys.exit(1)

    corpus_path = sys.argv[1]
    bank_path = sys.argv[2]
    output_path = sys.argv[3]

    # --- Build Huffman tree from the main corpus (same as huff_encoder.py) ---
    corpus_strings = parse_corpus(corpus_path)

    freq = Counter()
    for sc_list in corpus_strings:
        for sc in sc_list:
            freq[sc] += 1
        freq[0x00] += 1  # null terminator

    root = build_tree(freq)
    codes = build_codes(root)

    # --- Parse the bank strings to encode ---
    bank_strings, display_lines, labels = parse_bank_strings(bank_path)

    if len(bank_strings) > 255:
        print(f"Error: bank has {len(bank_strings)} strings, max is 255",
              file=sys.stderr)
        sys.exit(1)

    # Verify all characters in bank strings exist in the Huffman tree
    for i, sc_list in enumerate(bank_strings):
        for sc in sc_list:
            if sc not in codes:
                print(f"Error: string [{i}] \"{display_lines[i]}\" contains "
                      f"screencode ${sc:02x} not in Huffman tree",
                      file=sys.stderr)
                sys.exit(1)

    # --- Compress all bank strings ---
    compressed = []
    total_uncompressed = 0
    total_compressed = 0
    for sc_list in bank_strings:
        data, bits = compress_string(sc_list, codes)
        compressed.append(data)
        total_uncompressed += len(sc_list) + 1  # +1 for null
        total_compressed += len(data)

    # --- Calculate offsets from compressed data start to each string ---
    offsets = []
    offset = 0
    for data in compressed:
        offsets.append(offset)
        offset += len(data)

    # --- Build PRG file ---
    prg = bytearray()

    # PRG header: load address $E000
    prg.append(0x00)  # low byte
    prg.append(0xE0)  # high byte

    # Byte 2: string count
    string_count = len(bank_strings)
    prg.append(string_count)

    # Bytes 3-4: offset from byte 2 to compressed data start (16-bit LE)
    # From byte 2, the layout is:
    #   1 byte (string count) + 2 bytes (this offset) + count*2 bytes (index table)
    # So offset = 1 + 2 + count*2 = 3 + count*2
    data_offset = 3 + string_count * 2
    prg.append(data_offset & 0xFF)
    prg.append((data_offset >> 8) & 0xFF)

    # Index table: count x 2 bytes, 16-bit LE offsets from compressed data start
    for off in offsets:
        prg.append(off & 0xFF)
        prg.append((off >> 8) & 0xFF)

    # Compressed data
    for data in compressed:
        prg.extend(data)

    # --- Write output ---
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(prg)

    # --- Summary ---
    payload_size = len(prg) - 2  # exclude PRG header
    index_size = string_count * 2
    header_size = 3  # count byte + 2-byte offset
    ratio = total_compressed / total_uncompressed * 100 if total_uncompressed else 0

    print(f"String bank: {string_count} strings")
    print(f"  Uncompressed: {total_uncompressed} bytes")
    print(f"  Compressed:   {total_compressed} bytes ({ratio:.1f}%)")
    print(f"  Header:       {header_size} bytes")
    print(f"  Index table:  {index_size} bytes")
    print(f"  PRG payload:  {payload_size} bytes (loads to $E000-${0xE000 + payload_size - 1:04X})")
    print(f"  PRG file:     {len(prg)} bytes (incl. 2-byte load address)")
    print(f"Written to {output_path}")

    # Print per-string details if verbose
    for i, data in enumerate(compressed):
        label_tag = f" @{labels[i]}" if i in labels else ""
        orig_len = len(bank_strings[i]) + 1
        print(f"  [{i:3d}]{label_tag} \"{display_lines[i][:40]}\" "
              f"({orig_len}->{len(data)} bytes, offset ${offsets[i]:04x})")


if __name__ == '__main__':
    main()
