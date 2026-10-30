#!/usr/bin/env python3
"""Static memory-contract checker for the Acorn BBC Master 128 port (platforms/bbcmaster/)."""

from __future__ import annotations

import argparse
import re
import struct
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_BUILD_DIR = ROOT / "build" / "bbcmaster"
STORAGE_SRC = Path(__file__).resolve().parent / "hal" / "storage.s"
OVERLAY_STORAGE_SRC = Path(__file__).resolve().parent / "overlay_storage.s"

MOS_WORKSPACE_BASE = 0x0800
MOS_WORKSPACE_END = 0x0DFF
LOW_RESIDENT_START = 0x0E00
LOW_HELPERS_LIMIT = 0x3000
RESIDENT_LIMIT = 0x8000

PLAY_SLOT_BASE = 0x8000
PLAY_SLOT_LIMIT = 0xA400
TIER_POOL_BASE = 0xA400
TIER_POOL_END = 0xA7FF
OVERLAY_BASE = 0xA800
OVERLAY_LIMIT = 0xC000
MOS_ROM_BASE = 0xC000
MOS_ROM_END = 0xFDFF

AUXDATA_VIRT_BASE = 0x6000
AUXDATA_VIRT_LIMIT = 0x7700
HUFFDATA_BASE = 0x8000
HUFFDATA_LIMIT = 0x9000

SWR_CACHE_CAPS = {
    "ovl.ui": 10 * 256,
    "ovl.town": 22 * 256,
    "ovl.modal": 13 * 256,
    "ovl.spell": 21 * 256,
    "ovl.items": 21 * 256,
    "ovl.gen": 21 * 256,
}

REQUIRED_LOW_SYMBOLS = (
    "entry_bootstrap",
    "save_zp",
    "restore_zp",
    "zp_save_buf",
    "EnterMos",
    "ExitMos",
    "mmu_safe_huff_read_ptr0",
    "mmu_safe_huff_read_ptr1",
    "mmu_safe_map_read_ptr0",
    "mmu_safe_map_read_ptr1",
    "mmu_safe_map_write_ptr0",
    "mmu_safe_map_write_ptr1",
    "mmu_safe_map_read_block",
    "beeb_swr_copy_to_window",
    "beeb_font_init",
    "screen_init",
    "beeb_wrch_noop",
    "beeb_write_cell",
    "beeb_read_cell",
    "screen_clear",
    "screen_clear_row",
    "beeb_flush_row_buf",
    "bsd_stage_shadow_row",
    "beeb_overlay_try_cache",
    "beeb_require_play",
    "beeb_call_osfile",
    "beeb_call_osfind",
    "beeb_call_osgbpb",
    "beeb_dfs_load_to_bank",
    "hal_asset_load_prg_header",
    "hal_asset_load_title",
    "hal_storage_probe_media",
    "hal_storage_open",
    "hal_storage_chrin",
    "hal_storage_chrout",
    "hal_storage_close",
    "beeb_brk_handler",
    "hal_platform_init_early",
    "low_helpers_end",
)

OVERLAY_FILES = (
    "ovl.start",
    "ovl.town",
    "ovl.death",
    "ovl.modal",
    "ovl.help",
    "ovl.ui",
    "ovl.items",
    "ovl.spell",
    "ovl.chest",
    "ovl.gen",
    "ovl.storage",
    "ovl.title",
)

TIER_FILES = (
    "monster.db.1",
    "monster.db.2",
    "monster.db.3",
    "monster.db.4",
)

LABEL_RE = re.compile(r"^\.label\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\$([0-9A-Fa-f]+)\b")


def parse_sym_file(sym_path: Path) -> dict[str, int]:
    symbols: dict[str, int] = {}
    for line in sym_path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = LABEL_RE.match(line.strip())
        if match:
            symbols[match.group(1)] = int(match.group(2), 16)
    return symbols


def prg_span(prg_path: Path) -> tuple[int, int]:
    data = prg_path.read_bytes()
    if len(data) < 3:
        raise ValueError(f"{prg_path.name}: PRG too short ({len(data)} bytes)")
    start = struct.unpack_from("<H", data, 0)[0]
    end_excl = start + (len(data) - 2)
    return start, end_excl


def validate_build(build_dir: Path) -> list[str]:
    errors: list[str] = []
    sym_path = build_dir / "main.sym"
    if not sym_path.exists():
        return [f"missing symbol file {sym_path}"]

    symbols = parse_sym_file(sym_path)

    for sym in REQUIRED_LOW_SYMBOLS:
        if sym not in symbols:
            errors.append(f"missing required low-resident symbol {sym}")
            continue
        addr = symbols[sym]
        limit = LOW_HELPERS_LIMIT if sym == "low_helpers_end" else LOW_HELPERS_LIMIT - 1
        if not (LOW_RESIDENT_START <= addr <= limit):
            errors.append(f"{sym} at ${addr:04X} violates < $3000 low-RAM contract")

    if symbols.get("entry_bootstrap") != LOW_RESIDENT_START:
        errors.append(
            f"entry_bootstrap at ${symbols.get('entry_bootstrap', 0):04X} != ${LOW_RESIDENT_START:04X}"
        )

    if "program_end" not in symbols:
        errors.append("missing symbol program_end")
    else:
        prog_end = symbols["program_end"]
        if not (LOW_RESIDENT_START <= prog_end <= RESIDENT_LIMIT):
            errors.append(f"program_end at ${prog_end:04X} exceeds $8000 Main RAM limit")

    # Check symbol overlap with protected windows ($0800-$0DFF MOS workspace, $A400-$A7FF tier pool, $C000-$FDFF MOS ROM)
    allowed_tier_pool = {"PLATFORM_TIER_NAME_POOL_BASE", "PLATFORM_TIER_NAME_POOL_END", "tier_name_pool"}
    for sym, addr in symbols.items():
        if MOS_WORKSPACE_BASE <= addr <= MOS_WORKSPACE_END:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps untouched MOS/DFS workspace ($0800-$0DFF)"
            )
        elif TIER_POOL_BASE <= addr <= TIER_POOL_END and sym not in allowed_tier_pool:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps tier-name pool ($A400-$A7FF)"
            )
        elif MOS_ROM_BASE <= addr <= MOS_ROM_END:
            errors.append(
                f"symbol {sym} at ${addr:04X} overlaps MOS 3.20 ROM ($C000-$FDFF)"
            )

    # Check moria8.res.prg ($0E00-$7FFF)
    res_prg = build_dir / "moria8.res.prg"
    if not res_prg.exists():
        errors.append("missing moria8.res.prg")
    else:
        start, end_excl = prg_span(res_prg)
        if start != LOW_RESIDENT_START:
            errors.append(f"moria8.res.prg load address ${start:04X} != ${LOW_RESIDENT_START:04X}")
        if end_excl > RESIDENT_LIMIT:
            errors.append(f"moria8.res.prg end ${end_excl:04X} exceeds ${RESIDENT_LIMIT:04X}")

    # Check beeb.play ($8000-$A3FF, starts with "M8P")
    play_prg = build_dir / "beeb.play"
    if not play_prg.exists():
        errors.append("missing beeb.play")
    else:
        start, end_excl = prg_span(play_prg)
        if start != PLAY_SLOT_BASE:
            errors.append(f"beeb.play load address ${start:04X} != ${PLAY_SLOT_BASE:04X}")
        if end_excl > PLAY_SLOT_LIMIT:
            errors.append(f"beeb.play end ${end_excl:04X} exceeds ${PLAY_SLOT_LIMIT:04X}")
        raw = play_prg.read_bytes()[2:5]
        if raw != b"M8P":
            errors.append(f"beeb.play missing 'M8P' signature (got {raw!r})")

    # Check beeb.auxdata ($6000-$76FF)
    aux_prg = build_dir / "beeb.auxdata"
    if not aux_prg.exists():
        errors.append("missing beeb.auxdata")
    else:
        start, end_excl = prg_span(aux_prg)
        if start != AUXDATA_VIRT_BASE:
            errors.append(f"beeb.auxdata load address ${start:04X} != ${AUXDATA_VIRT_BASE:04X}")
        if end_excl > AUXDATA_VIRT_LIMIT:
            errors.append(f"beeb.auxdata end ${end_excl:04X} exceeds ${AUXDATA_VIRT_LIMIT:04X}")

    # Check beeb.huffdata ($8000-$8FFF in 4 KB ANDY)
    huff_prg = build_dir / "beeb.huffdata"
    if not huff_prg.exists():
        errors.append("missing beeb.huffdata")
    else:
        start, end_excl = prg_span(huff_prg)
        if start != HUFFDATA_BASE:
            errors.append(f"beeb.huffdata load address ${start:04X} != ${HUFFDATA_BASE:04X}")
        if end_excl > HUFFDATA_LIMIT:
            errors.append(f"beeb.huffdata end ${end_excl:04X} exceeds 4 KB ANDY limit (${HUFFDATA_LIMIT:04X})")

    # Check overlays and monster tiers ($A800-$BFFF) and Sideways RAM cache caps
    sizes: dict[str, int] = {}
    if aux_prg.exists():
        aux_start, aux_end = prg_span(aux_prg)
        sizes["beeb.auxdata"] = aux_end - aux_start
    for name in OVERLAY_FILES + TIER_FILES:
        p = build_dir / name
        if not p.exists():
            errors.append(f"missing {name}")
            continue
        start, end_excl = prg_span(p)
        if start != OVERLAY_BASE:
            errors.append(f"{name} load address ${start:04X} != ${OVERLAY_BASE:04X}")
        if end_excl > OVERLAY_LIMIT:
            errors.append(f"{name} end ${end_excl:04X} exceeds ${OVERLAY_LIMIT:04X}")
        size = end_excl - start
        sizes[name] = size
        if name in SWR_CACHE_CAPS and size > SWR_CACHE_CAPS[name]:
            errors.append(f"{name} size {size} B exceeds Sideways RAM cache cap {SWR_CACHE_CAPS[name]} B")

    # Verify aggregate Sideways RAM bank page sums (<= 64 pages = 16,384 B per 16 KB bank)
    bank6_items = ("beeb.auxdata", "ovl.town", "ovl.modal")
    if all(k in sizes for k in bank6_items):
        bank6_pages = sum((sizes[k] + 255) // 256 for k in bank6_items)
        if bank6_pages > 64:
            errors.append(f"Sideways Bank 6 aggregate pages ({bank6_pages}) exceed 64-page (16 KB) bank limit")

    bank7_items = ("ovl.spell", "ovl.items", "ovl.gen")
    if all(k in sizes for k in bank7_items):
        bank7_pages = sum((sizes[k] + 255) // 256 for k in bank7_items)
        if bank7_pages > 64:
            errors.append(f"Sideways Bank 7 aggregate pages ({bank7_pages}) exceed 64-page (16 KB) bank limit")

    # Check title.prg ($8000) and boot.prg ($1900, <= 512 B)
    title_prg = build_dir / "title.prg"
    if not title_prg.exists():
        errors.append("missing title.prg")
    else:
        start, end_excl = prg_span(title_prg)
        if start != 0x8000:
            errors.append(f"title.prg load address ${start:04X} != $8000")

    boot_prg = build_dir / "boot.prg"
    if not boot_prg.exists():
        errors.append("missing boot.prg")
    else:
        start, end_excl = prg_span(boot_prg)
        if start != 0x1900 or (end_excl - start) > 512:
            errors.append(f"boot.prg span ${start:04X}-${end_excl:04X} must start at $1900 and fit <= 512 B")

    return errors


def loader_disk_names(storage: Path = STORAGE_SRC,
                      overlay_storage: Path = OVERLAY_STORAGE_SRC) -> dict[str, str]:
    """What -> DFS name for every file the game loads from the disk: each
    monster tier, and each overlay the boot pack does not preload into
    Sideways RAM (beeb_ovl_cache_bank $00). Names come from the .byte data of
    the loader's own table in hal/storage.s."""
    names = {}
    for match in re.finditer(r"^hal_storage_(tier_\d|overlay_\w+?)_name:\s*\n\s*\.byte\s+([^/\n]+)",
                             storage.read_text(), re.M):
        names[match.group(1)] = "".join(chr(int(b, 16)) for b in re.findall(r"\$([0-9a-fA-F]{2})", match.group(2)))
    text = overlay_storage.read_text()
    order = re.search(r"// Order: (.+?)\n// =+", text, re.S)
    if order is None:
        raise ValueError("overlay_storage.s: the '// Order:' comment listing the overlay classes is missing")
    order = order.group(1)
    classes = [c.lower() for c in re.findall(r"([A-Z]+)\(\d+\)", order)]
    banks = re.search(r"^beeb_ovl_cache_bank:\s*\n((?:\s*\.byte[^\n]*\n)+)", text, re.M)
    if banks is None:
        raise ValueError("overlay_storage.s: the beeb_ovl_cache_bank .byte table is missing")
    banks = banks.group(1)
    cached = [b.strip() != "$00" for b in re.sub(r"\s*\.byte\s*", ",", banks).strip(",").split(",")]
    if len(classes) != len(cached):
        raise ValueError(f"overlay_storage.s: {len(classes)} overlay classes, {len(cached)} cache entries")
    for cls, is_cached in zip(classes, cached):
        key = next((k for k in names if k.startswith(f"overlay_{cls}")), None)
        if key is None:
            raise ValueError(f"hal/storage.s has no filename for overlay {cls.upper()}")
        if is_cached:
            del names[key]
    if sum(k.startswith("tier_") for k in names) != 4:
        raise ValueError("hal/storage.s: expected the four monster tier filenames")
    return names


def ssd_catalog(ssd: bytes) -> set[str]:
    """Names in the default ($) directory of an Acorn DFS single-sided
    image's catalogue, the one the loader reads."""
    return {ssd[8 + i * 8:15 + i * 8].decode("latin-1").rstrip()
            for i in range(ssd[0x105] // 8)
            if ssd[15 + i * 8] & 0x7F == ord("$")}   # bit 7: locked


def validate_disk(ssd: bytes, wanted: dict[str, str]) -> list[str]:
    """Every file the loader reads from DFS by name (loader_disk_names: the
    monster tiers and the overlays the boot pack does not preload) is on the
    disk, in the default directory."""
    catalog = ssd_catalog(ssd)
    return [f"{what} loads {name} from the disk, which does not have it"
            for what, name in sorted(wanted.items()) if name not in catalog]


def write_synthetic_prg(path: Path, start: int, length: int, prefix: bytes = b"") -> None:
    body = prefix + (b"\xea" * max(0, length - len(prefix)))
    path.write_bytes(struct.pack("<H", start) + body)


def run_selftest() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        bdir = Path(tmp)
        sym_lines = [
            f".label {name}=${LOW_RESIDENT_START + i * 0x10:04x}"
            for i, name in enumerate(REQUIRED_LOW_SYMBOLS)
        ]
        sym_lines.append(".label program_end=$7b00")
        base_sym_text = "\n".join(sym_lines) + "\n"
        (bdir / "main.sym").write_text(base_sym_text, encoding="utf-8")

        write_synthetic_prg(bdir / "moria8.res.prg", LOW_RESIDENT_START, 0x6D00)
        write_synthetic_prg(bdir / "beeb.play", PLAY_SLOT_BASE, 0x2000, prefix=b"M8P")
        write_synthetic_prg(bdir / "beeb.auxdata", AUXDATA_VIRT_BASE, 0x1500)
        write_synthetic_prg(bdir / "beeb.huffdata", HUFFDATA_BASE, 0x0D94)
        write_synthetic_prg(bdir / "title.prg", 0x8000, 620)
        write_synthetic_prg(bdir / "boot.prg", 0x1900, 320)
        for name in OVERLAY_FILES + TIER_FILES:
            write_synthetic_prg(bdir / name, OVERLAY_BASE, 0x0400)

        errs = validate_build(bdir)
        if errs:
            print(f"FAIL: valid synthetic build rejected: {errs}", file=sys.stderr)
            return 1

        # Negative test 1: low helper at or above $3000 must fail
        (bdir / "main.sym").write_text(
            base_sym_text.replace("EnterMos=$0e40", "EnterMos=$3000"), encoding="utf-8"
        )
        if not validate_build(bdir):
            print("FAIL: failed to catch EnterMos >= $3000", file=sys.stderr)
            return 1

        # Negative test 2: program_end exceeding $8000 must fail
        (bdir / "main.sym").write_text(
            base_sym_text.replace("program_end=$7b00", "program_end=$8001"), encoding="utf-8"
        )
        if not validate_build(bdir):
            print("FAIL: failed to catch program_end > $8000", file=sys.stderr)
            return 1

        # Negative test 3: symbol in MOS workspace ($0800-$0DFF) must fail
        (bdir / "main.sym").write_text(
            base_sym_text + ".label bad_mos_sym=$0900\n", encoding="utf-8"
        )
        if not validate_build(bdir):
            print("FAIL: failed to catch symbol in $0800-$0DFF", file=sys.stderr)
            return 1

        # Negative test 4: symbol in tier-name pool ($A400-$A7FF) must fail
        (bdir / "main.sym").write_text(
            base_sym_text + ".label bad_tier_sym=$a500\n", encoding="utf-8"
        )
        if not validate_build(bdir):
            print("FAIL: failed to catch symbol in $A400-$A7FF", file=sys.stderr)
            return 1

        # Negative test 5: beeb.huffdata exceeding 4 KB ANDY ($9000) must fail
        (bdir / "main.sym").write_text(base_sym_text, encoding="utf-8")
        write_synthetic_prg(bdir / "beeb.huffdata", HUFFDATA_BASE, 0x1001)
        if not validate_build(bdir):
            print("FAIL: failed to catch beeb.huffdata > $9000", file=sys.stderr)
            return 1

        # The disk: every file the loader takes from DFS is on it.
        sys.path.insert(0, str(ROOT / "tools"))
        from make_ssd import DfsFileSpec, build_ssd_image
        wanted = loader_disk_names()
        if wanted.get("tier_1") != "MONDB1" or "overlay_town" in wanted:
            print(f"FAIL: loader names misread: {wanted}", file=sys.stderr)
            return 1
        def spec(n: str, d: str = "$", lk: bool = False) -> DfsFileSpec:
            return DfsFileSpec(name=n, directory=d, locked=lk, load_addr=0, exec_addr=0, data=b"x")

        full = build_ssd_image([spec(n, lk=(n == "MONDB1")) for n in wanted.values()])
        if validate_disk(full, wanted):
            print("FAIL: a disk with every loaded file rejected", file=sys.stderr)
            return 1
        short = build_ssd_image([spec(n) for n in wanted.values() if n != "MONDB1"])
        if not validate_disk(short, wanted):
            print("FAIL: failed to catch MONDB1 missing from the disk", file=sys.stderr)
            return 1
        elsewhere = build_ssd_image([spec(n, "A" if n == "MONDB1" else "$") for n in wanted.values()])
        if not validate_disk(elsewhere, wanted):
            print("FAIL: failed to catch MONDB1 outside the default directory", file=sys.stderr)
            return 1

    print("BBC Master 128 memory contract self-test: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--selftest", action="store_true", help="Run synthetic pass/fail self-tests.")
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD_DIR)
    parser.add_argument("--disk", type=Path, help="check this .ssd holds every file the game loads from DFS")
    args = parser.parse_args()

    if args.selftest:
        return run_selftest()

    if args.disk:
        errors = validate_disk(args.disk.read_bytes(), loader_disk_names())
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        print(f"BBC Master 128 disk check {'FAILED' if errors else 'passed'}: {args.disk.name}")
        return 1 if errors else 0

    errors = validate_build(args.build_dir)
    if errors:
        print("BBC Master 128 memory contract check FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        return 1

    print("BBC Master 128 memory contract check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
