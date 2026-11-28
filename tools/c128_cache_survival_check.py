#!/usr/bin/env python3
"""Verify C128 cache survival smoke checks from VICE monitor dumps.

Replaces in-image C128_TEST_CACHE_SURVIVAL snapshot/verification routines by
reading the KickAss .vs symbol table and the x128 monitor log produced by
platforms/commodore/c128/run_tests128.sh (run_cache_survival_smoke).
"""

import re
import sys
from pathlib import Path

PROBE_SPAN_LEN = 8
C128_DISARM_OVERLAY_ID = 8

# Bank 1 cache probe regions (platforms/commodore/c128/memory128.s, C128M-007).
BANK1_PROBES = (
    ("bank1_catalog_fields", 0x7E60),
    ("bank1_catalog_names", 0xA000),
    ("bank1_overlay_town", 0xB000),
    ("bank1_overlay_death", 0xC000),
    ("bank1_overlay_dungeon", 0xE000),
    ("bank1_overlay_disarm", 0x9D00),
)

REQUIRED_SYMBOLS = (
    "title_enter_menu",
    "hal_platform_character_sheet_begin",
    "main_loop",
    "c128_cache_enabled",
    "c128_cache_tiers_ready",
    "c128_cache_overlays_ready",
    "c128_cache_failed",
    "c128_cache_tier_bits",
    "c128_cache_overlay_bits",
    "c128_cache_overlay_bits_hi",
    "mmu_common_irq",
    "current_overlay",
    "overlay_load_disk",
    "runtime_load_failed",
    "runtime_common_data_end",
)

STOP_RE = re.compile(
    r"^#\d+\s+\(Stop\s+on\s+exec\s+(?:[A-Za-z0-9_]+:)?([0-9a-fA-F]{4})\b",
    re.IGNORECASE,
)
MEM_RE = re.compile(r"^>[A-Za-z0-9_]+:([0-9a-fA-F]{4})\s+(.+)$")
REG_RE = re.compile(
    r"^\.;([0-9a-fA-F]{4})\s+(?:[0-9a-fA-F]{2}\s+)+([01.\-]{8})(?:\s|$)"
)
HEX_BYTE_RE = re.compile(r"^[0-9a-fA-F]{2}$")


def parse_vs(vs_path: Path) -> dict[str, int]:
    """Parse KickAssembler VICE symbol definitions into {symbol: addr}."""
    symbols: dict[str, int] = {}
    for line in vs_path.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "al" and parts[1].startswith("C:"):
            symbols[parts[2].lstrip(".")] = int(parts[1][2:], 16)
    return symbols


def parse_mem_bytes(rest: str) -> list[int]:
    """Extract hex data bytes from a VICE `m` row before its ASCII column."""
    if "   " in rest:
        rest = rest.split("   ", 1)[0]
    out: list[int] = []
    for tok in rest.split():
        if HEX_BYTE_RE.match(tok):
            out.append(int(tok, 16))
        else:
            break
    return out


class StopSegment:
    """Captured monitor outputs following one `Stop on exec` event."""

    def __init__(self, stop_addr: int) -> None:
        self.stop_addr = stop_addr
        self.mem: dict[int, int] = {}
        self.regs: list[tuple[int, str]] = []


def parse_monitor_log(text: str) -> list[StopSegment]:
    """Split a VICE monitor log into ordered stop segments with mem/reg dumps."""
    segments: list[StopSegment] = []
    current: StopSegment | None = None
    for raw in text.splitlines():
        line = raw.strip()
        m_stop = STOP_RE.match(line)
        if m_stop:
            current = StopSegment(int(m_stop.group(1), 16))
            segments.append(current)
            continue
        if current is None:
            continue
        m_mem = MEM_RE.match(line)
        if m_mem:
            base = int(m_mem.group(1), 16)
            for idx, val in enumerate(parse_mem_bytes(m_mem.group(2))):
                current.mem[base + idx] = val
            continue
        m_reg = REG_RE.match(line)
        if m_reg:
            current.regs.append((int(m_reg.group(1), 16), m_reg.group(2)))
    return segments


def _read_span(mem: dict[int, int], base: int, length: int, label: str) -> list[int]:
    missing = [f"${base + i:04x}" for i in range(length) if (base + i) not in mem]
    if missing:
        raise ValueError(f"missing dumped bytes for {label}: {', '.join(missing)}")
    return [mem[base + i] for i in range(length)]


def _read_byte(mem: dict[int, int], addr: int, label: str) -> int:
    if addr not in mem:
        raise ValueError(f"missing dumped byte for {label} (${addr:04x})")
    return mem[addr]


def verify(vs_text_or_path, log_text: str) -> None:
    """Validate every cache-survival assertion against `.vs` symbols and log."""
    if isinstance(vs_text_or_path, Path):
        symbols = parse_vs(vs_text_or_path)
    else:
        symbols = {}
        for line in vs_text_or_path.splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[0] == "al" and parts[1].startswith("C:"):
                symbols[parts[2].lstrip(".")] = int(parts[1][2:], 16)

    missing_syms = [name for name in REQUIRED_SYMBOLS if name not in symbols]
    if missing_syms:
        raise ValueError(f"missing symbols in .vs: {', '.join(missing_syms)}")

    if re.search(r"JAM|Invalid opcode", log_text, re.IGNORECASE):
        raise ValueError("CPU JAM or invalid opcode detected in monitor log")

    segments = parse_monitor_log(log_text)
    if not segments:
        raise ValueError("no monitor stop events found in log")

    addr_title = symbols["title_enter_menu"]
    addr_sheet = symbols["hal_platform_character_sheet_begin"]
    addr_main_loop = symbols["main_loop"]
    addr_disk_load = symbols["overlay_load_disk"]
    addr_load_fail = symbols["runtime_load_failed"]
    addr_stub_ret = symbols["runtime_common_data_end"] + 3

    if any(s.stop_addr == addr_disk_load for s in segments):
        raise ValueError(
            f"tramp_door_pick_roll triggered disk load at ${addr_disk_load:04x}"
        )
    if any(s.stop_addr == addr_load_fail for s in segments):
        raise ValueError(f"hit runtime_load_failed at ${addr_load_fail:04x}")

    title_idxs = [i for i, s in enumerate(segments) if s.stop_addr == addr_title]
    sheet_idxs = [i for i, s in enumerate(segments) if s.stop_addr == addr_sheet]
    main_idxs = [i for i, s in enumerate(segments) if s.stop_addr == addr_main_loop]
    stub_idxs = [i for i, s in enumerate(segments) if s.stop_addr == addr_stub_ret]

    if len(title_idxs) != 1:
        raise ValueError(
            f"expected 1 stop at title_enter_menu (${addr_title:04x}), got {len(title_idxs)}"
        )
    if len(sheet_idxs) != 1:
        raise ValueError(
            f"expected 1 stop at hal_platform_character_sheet_begin (${addr_sheet:04x}), got {len(sheet_idxs)}"
        )
    if len(main_idxs) != 1:
        raise ValueError(
            f"expected 1 stop at main_loop (${addr_main_loop:04x}), got {len(main_idxs)}"
        )
    if len(stub_idxs) != 1:
        raise ValueError(
            f"expected 1 stop at door-pick stub return (${addr_stub_ret:04x}), got {len(stub_idxs)}"
        )

    if not (title_idxs[0] < sheet_idxs[0] < main_idxs[0] < stub_idxs[0]):
        raise ValueError(
            "unexpected execution order: expected title_enter_menu -> "
            "hal_platform_character_sheet_begin -> main_loop -> stub_ret"
        )

    title_seg = segments[title_idxs[0]]
    main_seg = segments[main_idxs[0]]
    stub_seg = segments[stub_idxs[0]]

    # 1. Cache readiness flags at first town entry (catalog mode: no tiers, no STARTUP).
    enabled = _read_byte(
        main_seg.mem, symbols["c128_cache_enabled"], "c128_cache_enabled"
    )
    tiers_ready = _read_byte(
        main_seg.mem, symbols["c128_cache_tiers_ready"], "c128_cache_tiers_ready"
    )
    tier_bits = _read_byte(
        main_seg.mem, symbols["c128_cache_tier_bits"], "c128_cache_tier_bits"
    )
    ovl_ready = _read_byte(
        main_seg.mem,
        symbols["c128_cache_overlays_ready"],
        "c128_cache_overlays_ready",
    )
    ovl_bits = _read_byte(
        main_seg.mem, symbols["c128_cache_overlay_bits"], "c128_cache_overlay_bits"
    )
    ovl_bits_hi = _read_byte(
        main_seg.mem,
        symbols["c128_cache_overlay_bits_hi"],
        "c128_cache_overlay_bits_hi",
    )
    cache_failed = _read_byte(
        main_seg.mem, symbols["c128_cache_failed"], "c128_cache_failed"
    )

    if enabled != 1:
        raise ValueError(f"c128_cache_enabled={enabled:#04x}, expected 0x01")
    if tiers_ready != 0 or tier_bits != 0:
        raise ValueError(
            f"catalog build claimed tiers ready (tiers_ready={tiers_ready:#04x}, tier_bits={tier_bits:#04x})"
        )
    if ovl_ready != 1:
        raise ValueError(f"c128_cache_overlays_ready={ovl_ready:#04x}, expected 0x01")
    if ovl_bits != 0xFE:
        raise ValueError(
            f"c128_cache_overlay_bits={ovl_bits:#04x}, expected 0xfe (all except STARTUP)"
        )
    if ovl_bits_hi != 0x00:
        raise ValueError(
            f"c128_cache_overlay_bits_hi={ovl_bits_hi:#04x}, expected 0x00 (modal-misc uncached)"
        )
    if cache_failed != 0:
        raise ValueError(f"c128_cache_failed={cache_failed:#04x} at town entry")

    # 2. MMU common RAM and Bank 1 cache regions survived chargen + town generation.
    probes = [("mmu_common_helpers", symbols["mmu_common_irq"]), *BANK1_PROBES]
    for label, base in probes:
        before = _read_span(
            title_seg.mem, base, PROBE_SPAN_LEN, f"{label} before chargen"
        )
        after = _read_span(
            main_seg.mem, base, PROBE_SPAN_LEN, f"{label} at town entry"
        )
        if before != after:
            raise ValueError(
                f"{label} (${base:04x}) mutated between tier_init and town entry: "
                f"{before} -> {after}"
            )

    # 3. Disarm overlay trampoline executed from Bank 1 cache and failed hopeless pick cleanly.
    if not stub_seg.regs:
        raise ValueError("missing register dump at door-pick stub return")
    reg_pc, flags = stub_seg.regs[-1]
    if reg_pc != addr_stub_ret:
        raise ValueError(
            f"door-pick register dump PC=${reg_pc:04x}, expected ${addr_stub_ret:04x}"
        )
    if flags[-1] != "0":
        raise ValueError(
            f"tramp_door_pick_roll returned Carry set (NV-BDIZC={flags}), expected hopeless failure (C=0)"
        )

    cur_ovl = _read_byte(main_or_stub_mem := stub_seg.mem, symbols["current_overlay"], "current_overlay")
    post_failed = _read_byte(main_or_stub_mem, symbols["c128_cache_failed"], "c128_cache_failed post door-pick")
    if cur_ovl != C128_DISARM_OVERLAY_ID:
        raise ValueError(
            f"current_overlay={cur_ovl}, expected {C128_DISARM_OVERLAY_ID} (C128_DISARM_OVERLAY_ID)"
        )
    if post_failed != 0:
        raise ValueError(f"c128_cache_failed={post_failed:#04x} after tramp_door_pick_roll")


def _selftest() -> None:
    vs_text = "\n".join(
        [
            "al C:3530 .title_enter_menu",
            "al C:2d7d .hal_platform_character_sheet_begin",
            "al C:c248 .main_loop",
            "al C:89e3 .c128_cache_enabled",
            "al C:89e4 .c128_cache_tiers_ready",
            "al C:89e5 .c128_cache_overlays_ready",
            "al C:89e6 .c128_cache_failed",
            "al C:89e7 .c128_cache_tier_bits",
            "al C:89e8 .c128_cache_overlay_bits",
            "al C:89e9 .c128_cache_overlay_bits_hi",
            "al C:0c06 .mmu_common_irq",
            "al C:89ef .current_overlay",
            "al C:75a8 .overlay_load_disk",
            "al C:35c4 .runtime_load_failed",
            "al C:0fd6 .runtime_common_data_end",
        ]
    )

    def fmt_span(base: int, vals: list[int]) -> str:
        hex_vals = " ".join(f"{b:02x}" for b in vals)
        return f">C:{base:04x}  {hex_vals}   ........"

    probe_data = {
        0x0C06: [0xD8, 0x48, 0x8A, 0x48, 0x98, 0x48, 0xA5, 0x01],
        0x7E60: [0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80],
        0xA000: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x11, 0x22],
        0xB000: [0x4C, 0x00, 0xE0, 0x60, 0xA9, 0x01, 0x8D, 0x00],
        0xC000: [0x20, 0x10, 0xC0, 0x60, 0xAD, 0x00, 0x20, 0x60],
        0xE000: [0xA9, 0x00, 0x85, 0x10, 0x60, 0xEA, 0xEA, 0xEA],
        0x9D00: [0xA5, 0x55, 0x38, 0xED, 0x20, 0x61, 0x90, 0x02],
    }

    def build_log(
        *,
        extra_sheet: bool = False,
        omit_sheet: bool = False,
        ovl_bits: int = 0xFE,
        ovl_bits_hi: int = 0x00,
        tier_bits: int = 0x00,
        mutate_probe: int | None = None,
        disk_load: bool = False,
        carry_set: bool = False,
        cur_ovl: int = 8,
        cache_failed_post: int = 0,
    ) -> str:
        lines = [
            "#1 (Stop on  exec 3530)",
            fmt_span(0x0C06, probe_data[0x0C06]),
            *[fmt_span(addr, probe_data[addr]) for _, addr in BANK1_PROBES],
            "#2 (Stop on  exec 1400)",
        ]
        if not omit_sheet:
            lines.append("#3 (Stop on  exec 2d7d)")
        if extra_sheet:
            lines.append("#4 (Stop on  exec 2d7d)")
        lines.append("#5 (Stop on  exec c248)")
        lines.append(fmt_span(0x89E3, [0x01, 0x00, 0x01, 0x00, tier_bits, ovl_bits, ovl_bits_hi]))
        for addr in [0x0C06, *[a for _, a in BANK1_PROBES]]:
            vals = list(probe_data[addr])
            if mutate_probe == addr:
                vals[3] ^= 0xFF
            lines.append(fmt_span(addr, vals))
        if disk_load:
            lines.append("#6 (Stop on  exec 75a8)")
        flags = "00100101" if carry_set else "00100100"
        lines.extend(
            [
                "#7 (Stop on  exec 0fd9)",
                f".;0fd9 00 08 ff f5 2f 35 {flags}",
                fmt_span(0x89EF, [cur_ovl]),
                fmt_span(0x89E6, [cache_failed_post]),
            ]
        )
        return "\n".join(lines)

    # Positive case must pass.
    verify(vs_text, build_log())

    # Negative cases must all fail with clear errors.
    bad_cases = [
        ("duplicate summary sheet", dict(extra_sheet=True)),
        ("missing summary sheet", dict(omit_sheet=True)),
        ("wrong overlay bits", dict(ovl_bits=0xFC)),
        ("unexpected modal-misc cache bit", dict(ovl_bits_hi=0x01)),
        ("non-catalog tier bits", dict(tier_bits=0x0F)),
        ("mutated common helper", dict(mutate_probe=0x0C06)),
        ("mutated catalog fields", dict(mutate_probe=0x7E60)),
        ("mutated catalog names", dict(mutate_probe=0xA000)),
        ("mutated town overlay cache", dict(mutate_probe=0xB000)),
        ("mutated death overlay cache", dict(mutate_probe=0xC000)),
        ("mutated dungeon overlay cache", dict(mutate_probe=0xE000)),
        ("mutated disarm overlay cache", dict(mutate_probe=0x9D00)),
        ("fell back to disk load", dict(disk_load=True)),
        ("door pick returned carry set", dict(carry_set=True)),
        ("wrong current_overlay", dict(cur_ovl=2)),
        ("cache failed post door-pick", dict(cache_failed_post=1)),
    ]
    for name, kwargs in bad_cases:
        try:
            verify(vs_text, build_log(**kwargs))
        except ValueError:
            continue
        raise AssertionError(f"selftest expected failure for: {name}")


def main() -> int:
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        _selftest()
        print("PASS (c128_cache_survival_check selftest)")
        return 0
    if len(sys.argv) != 3:
        print(
            "usage: c128_cache_survival_check.py <main.vs> <mon_log> | --selftest",
            file=sys.stderr,
        )
        return 2
    try:
        verify(Path(sys.argv[1]), Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace"))
    except ValueError as exc:
        print(str(exc))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
