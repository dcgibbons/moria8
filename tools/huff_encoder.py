#!/usr/bin/env python3
"""
Huffman encoder for C64 Moria string compression.

Reads a text file with one string per line (ASCII mixed case), builds a
Huffman tree, and emits a Kick Assembler .s file with compressed data
and tree tables for the 6502 decoder.

Lines starting with '#' are comments (ignored).
Blank lines are ignored.
Lines starting with '@LABEL' define named string constants:
  @MAT_HITS  HITS YOU.  →  .const HSTR_MAT_HITS = <index>

Usage:
  python3 tools/huff_encoder.py data/huffman_strings.txt -o huffman_data.s
"""

import sys
import heapq
import argparse
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CHECK_INPUT = REPO_ROOT / 'data' / 'huffman_strings.txt'
DEFAULT_CHECK_OUTPUT = REPO_ROOT / 'core' / '6502' / 'huffman_data.s'


def ascii_to_screencode(ch):
    """Convert ASCII character to C64 screen code (screencode_mixed)."""
    c = ord(ch)
    if ch == ' ':
        return 0x20
    if 'A' <= ch <= 'Z':
        return c - 0x40 + 0x40  # A=$41, B=$42, ... Z=$5A (uppercase)
    if 'a' <= ch <= 'z':
        return c - 0x60  # a=$01, b=$02, ... z=$1A (lowercase)
    if '0' <= ch <= '9':
        return c - 0x30 + 0x30  # 0-9 map to $30-$39
    if ch == '.':
        return 0x2E
    if ch == ',':
        return 0x2C
    if ch == '!':
        return 0x21
    if ch == '?':
        return 0x3F
    if ch == '\'':
        return 0x27
    if ch == '-':
        return 0x2D
    if ch == ':':
        return 0x3A
    if ch == ';':
        return 0x3B
    if ch == '(':
        return 0x28
    if ch == ')':
        return 0x29
    if ch == '/':
        return 0x2F
    if ch == '=':
        return 0x3D
    if ch == '>':
        return 0x3E
    raise ValueError(f"Unsupported character: '{ch}' (0x{c:02x})")


class HuffNode:
    """Node in the Huffman tree."""
    def __init__(self, char=None, freq=0, left=None, right=None):
        self.char = char  # None for internal nodes, screencode for leaves
        self.freq = freq
        self.left = left
        self.right = right

    def __lt__(self, other):
        return self.freq < other.freq


def build_tree(freq):
    """Build Huffman tree from frequency dict. Returns root node."""
    heap = [HuffNode(char=ch, freq=f) for ch, f in freq.items()]
    heapq.heapify(heap)
    while len(heap) > 1:
        left = heapq.heappop(heap)
        right = heapq.heappop(heap)
        parent = HuffNode(freq=left.freq + right.freq, left=left, right=right)
        heapq.heappush(heap, parent)
    return heap[0]


def build_codes(root):
    """Walk tree and return dict mapping screencode -> bit string."""
    codes = {}
    def walk(node, prefix):
        if node.char is not None:
            codes[node.char] = prefix if prefix else '0'
            return
        walk(node.left, prefix + '0')
        walk(node.right, prefix + '1')
    walk(root, '')
    return codes


def flatten_tree(root):
    """
    Flatten tree to parallel arrays for 6502 decoder.
    Internal nodes numbered 0..N-1. Children encoded as:
      $00-$7E = internal node index
      $80+    = leaf (value & $7F = screencode)
    Returns (left_table, right_table) as lists of ints.
    """
    left_table = []
    right_table = []
    # Assign internal node indices via BFS
    node_ids = {}
    queue = [root]
    idx = 0
    while queue:
        node = queue.pop(0)
        if node.char is not None:
            continue  # leaf, skip
        node_ids[id(node)] = idx
        idx += 1
        if node.left.char is None:
            queue.append(node.left)
        if node.right.char is None:
            queue.append(node.right)

    # Build tables
    queue2 = [root]
    while queue2:
        node = queue2.pop(0)
        if node.char is not None:
            continue
        # Encode left child
        if node.left.char is not None:
            left_table.append(0x80 | node.left.char)
        else:
            left_table.append(node_ids[id(node.left)])
            queue2.append(node.left)
        # Encode right child
        if node.right.char is not None:
            right_table.append(0x80 | node.right.char)
        else:
            right_table.append(node_ids[id(node.right)])
            queue2.append(node.right)

    return left_table, right_table


def compress_string(screencodes, codes):
    """Compress a list of screencodes (including trailing null) to bytes."""
    bits = ''
    for sc in screencodes:
        bits += codes[sc]
    # Null terminator
    bits += codes[0x00]
    # Pad to byte boundary
    while len(bits) % 8 != 0:
        bits += '0'
    # Convert to bytes
    result = []
    for i in range(0, len(bits), 8):
        result.append(int(bits[i:i+8], 2))
    return result, len(bits)


def encode_strings_file(input_path, source_label=None):
    """Encode input_path and return (rendered_s_text, stats_dict)."""
    if source_label is None:
        source_label = str(input_path)

    # Read and parse strings (support comments, blank lines, @LABEL)
    with open(input_path, encoding='utf-8') as f:
        raw_lines = [line.rstrip('\n') for line in f]

    display_lines = []   # Original text for comments in output
    strings = []         # List of screencode lists
    labels = {}          # index -> label name

    for raw in raw_lines:
        line = raw.rstrip('\n\r')  # Only strip line endings, preserve spaces
        check = line.strip()
        if not check or check.startswith('#'):
            continue
        # Check for @LABEL prefix
        trimmed = line.lstrip()
        if trimmed.startswith('@'):
            # Single space separates label from text; remaining spaces are part of string
            space_pos = trimmed.index(' ')
            label = trimmed[1:space_pos]
            text = trimmed[space_pos+1:]  # Preserve leading/trailing spaces in text
        else:
            label = None
            text = trimmed  # Anonymous strings: strip leading whitespace only

        # Handle trailing space marker: " ~" at end → trailing space
        if text.endswith(' ~'):
            text = text[:-1]  # Remove ~, keep the space

        idx = len(strings)
        screencodes = [ascii_to_screencode(ch) for ch in text]
        strings.append(screencodes)
        display_lines.append(text)
        if label:
            labels[idx] = label

    # Build frequency table (include null terminator for each string)
    freq = Counter()
    for sc_list in strings:
        for sc in sc_list:
            freq[sc] += 1
        freq[0x00] += 1  # null terminator

    # Build tree and codes
    root = build_tree(freq)
    codes = build_codes(root)
    left_table, right_table = flatten_tree(root)

    # Compress all strings
    compressed = []
    total_uncompressed = 0
    total_compressed = 0
    for sc_list in strings:
        data, bits = compress_string(sc_list, codes)
        compressed.append(data)
        total_uncompressed += len(sc_list) + 1  # +1 for null
        total_compressed += len(data)

    # Calculate offsets (byte-aligned per string)
    offsets = []
    offset = 0
    for data in compressed:
        offsets.append(offset)
        offset += len(data)

    tree_size = len(left_table) + len(right_table)
    index_size = len(strings) * 2
    ratio = total_compressed / total_uncompressed * 100

    # Count insults (anonymous strings before first labeled string)
    first_labeled = None
    for i in range(len(strings)):
        if i in labels:
            first_labeled = i
            break
    insult_count = first_labeled if first_labeled is not None else len(strings)

    # Emit assembly output
    out_lines = []
    out_lines.append(f'// huffman_data.s — Generated by huff_encoder.py')
    out_lines.append(f'// Source: {source_label}')
    out_lines.append(f'// {len(strings)} strings, {total_uncompressed} bytes uncompressed')
    out_lines.append(f'// {total_compressed} bytes compressed ({ratio:.1f}%)')
    out_lines.append(f'// Tree: {tree_size} bytes, Index: {index_size} bytes')
    out_lines.append(f'// Total data: {total_compressed + tree_size + index_size} bytes')
    out_lines.append(f'')
    out_lines.append(f'.const HUFF_STR_COUNT = {len(strings)}')
    out_lines.append(f'.const HSTR_INSULT_COUNT = {insult_count}')
    out_lines.append(f'')

    # Named string constants
    if labels:
        out_lines.append(f'// Named string constants')
        for idx in sorted(labels.keys()):
            out_lines.append(f'.const HSTR_{labels[idx]} = {idx}')
        out_lines.append(f'')

    # Tree tables
    out_lines.append(f'// Huffman tree: {len(left_table)} internal nodes')
    out_lines.append(f'// Children: $00-$7E = node index, $80+ = leaf (& $7F = screencode)')
    out_lines.append(f'huff_tree_left:')
    row = '    .byte '
    row += ', '.join(f'${b:02x}' for b in left_table)
    out_lines.append(row)
    out_lines.append(f'huff_tree_right:')
    row = '    .byte '
    row += ', '.join(f'${b:02x}' for b in right_table)
    out_lines.append(row)
    out_lines.append(f'')

    # String index (16-bit offsets)
    # A port that defines HUFFMAN_INDEX_EXTERNAL places the index in a
    # segment of its own (:HuffmanIndexSegment()), then returns to
    # :HuffmanDataSegment() for the strings (2026-11-08).
    out_lines.append(f'// String index: 16-bit byte offsets into huff_str_data')
    out_lines.append(f'#if HUFFMAN_INDEX_EXTERNAL')
    out_lines.append(f':HuffmanIndexSegment()')
    out_lines.append(f'#endif')
    out_lines.append(f'huff_str_index:')
    for i, off in enumerate(offsets):
        label_tag = f' @{labels[i]}' if i in labels else ''
        out_lines.append(f'    .word ${off:04x}  // [{i}]{label_tag} "{display_lines[i][:30]}"')
    out_lines.append(f'huff_str_index_end:')
    out_lines.append(f'#if HUFFMAN_INDEX_EXTERNAL')
    out_lines.append(f':HuffmanDataSegment()')
    out_lines.append(f'#endif')
    out_lines.append(f'')

    # Compressed data
    out_lines.append(f'// Compressed string data ({total_compressed} bytes)')
    out_lines.append(f'huff_str_data:')
    for i, data in enumerate(compressed):
        orig_len = len(strings[i]) + 1
        out_lines.append(f'    // [{i}] "{display_lines[i]}" ({orig_len}→{len(data)} bytes)')
        row = '    .byte '
        row += ', '.join(f'${b:02x}' for b in data)
        out_lines.append(row)

    # Code table as comments
    out_lines.append(f'')
    out_lines.append(f'// Huffman code table:')
    for sc in sorted(codes.keys()):
        if sc == 0x00:
            name = 'NULL'
        elif sc == 0x20:
            name = 'SPACE'
        elif 0x01 <= sc <= 0x1a:
            name = chr(sc + 0x60)  # lowercase a-z
        elif 0x41 <= sc <= 0x5a:
            name = chr(sc)  # uppercase A-Z
        else:
            name = f'${sc:02x}'
        out_lines.append(f'//   {name:6s} = {codes[sc]:>12s} ({len(codes[sc])} bits, freq={freq[sc]})')

    out_lines.append('')
    stats = {
        'string_count': len(strings),
        'total_uncompressed': total_uncompressed,
        'total_compressed': total_compressed,
        'ratio': ratio,
        'tree_size': tree_size,
        'index_size': index_size,
    }
    return '\n'.join(out_lines), stats


def main(argv=None):
    parser = argparse.ArgumentParser(description='Huffman encoder for C64 Moria')
    parser.add_argument('input', nargs='?', help='Input text file (one string per line)')
    parser.add_argument('-o', '--output', default=None,
                        help='Output assembly file (default: huffman_data.s, or core/6502/huffman_data.s with --check)')
    parser.add_argument('--check', action='store_true',
                        help='Verify output assembly file matches input text without writing')
    args = parser.parse_args(argv)

    if args.check:
        in_path = Path(args.input) if args.input else DEFAULT_CHECK_INPUT
        out_path = Path(args.output) if args.output else DEFAULT_CHECK_OUTPUT
        try:
            source_label = in_path.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
        except ValueError:
            source_label = str(args.input or in_path)
        expected, stats = encode_strings_file(in_path, source_label=source_label)
        if not out_path.is_file():
            print(f'FAIL huff_encoder --check: missing {out_path}', file=sys.stderr)
            return 1
        actual = out_path.read_text(encoding='utf-8')
        if actual != expected:
            print(
                f'FAIL huff_encoder --check: {out_path} is out of sync with {in_path} '
                f'(run: python3 tools/huff_encoder.py data/huffman_strings.txt -o core/6502/huffman_data.s)',
                file=sys.stderr,
            )
            return 1
        print(
            f'PASS huff_encoder --check: {out_path.name} matches {source_label} '
            f'({stats["string_count"]} strings, {stats["total_compressed"] + stats["tree_size"] + stats["index_size"]} B)'
        )
        return 0

    if not args.input:
        parser.error('the following arguments are required: input (unless --check is used)')
    out_file = args.output or 'huffman_data.s'
    rendered, stats = encode_strings_file(args.input, source_label=args.input)
    with open(out_file, 'w', encoding='utf-8') as f:
        f.write(rendered)

    print(f'Encoded {stats["string_count"]} strings: {stats["total_uncompressed"]} → {stats["total_compressed"]} bytes ({stats["ratio"]:.1f}%)')
    print(f'Tree: {stats["tree_size"]} bytes, Index: {stats["index_size"]} bytes')
    print(f'Total output: {stats["total_compressed"] + stats["tree_size"] + stats["index_size"]} bytes')
    print(f'Written to {out_file}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
