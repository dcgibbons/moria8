#!/usr/bin/env python3
"""Cross-port 0..360 item catalog Name, Category, Hot-Table & Cold-Record verifier.

Verifies every built Moria8 port's (c64, plus4, c128, apple2, cx16, atari8,
bbcmaster) compiled hot tables and 'ITM2' ITEM.CAT payload against
item_catalog_spec.json across all 361 item IDs (0..360), 55 egos, and 174
flavours without emulating CPU instructions or port banking registers.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tools"))

import build_item_catalog as bic  # noqa: E402
import item_ids as IID  # noqa: E402

SPEC_PATH = REPO_ROOT / "platforms/shared/item_catalog/item_catalog_spec.json"
DEFAULT_BUILD_ROOT = REPO_ROOT / "build"

CANONICAL_PORTS = ("c64", "plus4", "c128", "apple2", "cx16", "atari8", "bbcmaster")

PORT_HOT_PRGS: dict[str, tuple[str, ...]] = {
    "c64": ("moria8.prg", "64.bank"),
    "plus4": ("moria4.prg", "4.bank"),
    "c128": ("128.play.prg", "128.item.prg", "moria128.prg", "128.bank.prg"),
    "apple2": ("a2.auxdata", "moria8a2.prg", "a2.play"),
    "cx16": ("CX16.AUXDATA", "MORIA8.PRG"),
    "atari8": ("MORIA8.RES", "ATARI.BNK"),
    "bbcmaster": ("beeb.auxdata", "beeb.play", "moria8.res.prg"),
}

PORT_ICAT_PATH: dict[str, tuple[str, bool]] = {
    "c64": ("item.cat", True),
    "plus4": ("item.cat", True),
    "c128": ("item.cat", True),
    "apple2": ("bin/ITEM.CAT", False),
    "cx16": ("ITEM.CAT", True),
    "atari8": ("ITEM.CAT", False),
    "bbcmaster": ("bin/ITEM.CAT", False),
}

SYM_RE = re.compile(r"^\.label\s+([A-Za-z_][A-Za-z0-9_]*)=\$([0-9a-fA-F]+)")
VS_RE = re.compile(r"^al\s+C:([0-9a-fA-F]+)\s+\.([A-Za-z_][A-Za-z0-9_]*)$")


def is_port_built(port: str, build_root: Path = DEFAULT_BUILD_ROOT) -> bool:
    bd = build_root / port
    icat_rel, _ = PORT_ICAT_PATH[port]
    return (
        bd.is_dir()
        and ((bd / "main.sym").is_file() or (bd / "main.vs").is_file())
        and (bd / PORT_HOT_PRGS[port][0]).is_file()
        and (bd / icat_rel).is_file()
    )


def _load_prg(path: Path) -> tuple[int, bytes]:
    raw = path.read_bytes()
    if len(raw) < 2:
        raise ValueError(f"PRG too short: {path}")
    return raw[0] | (raw[1] << 8), raw[2:]


def read_port_item_cat(port: str, build_root: Path = DEFAULT_BUILD_ROOT) -> bytes:
    icat_rel, has_prg_hdr = PORT_ICAT_PATH[port]
    path = build_root / port / icat_rel
    return _load_prg(path)[1] if has_prg_hdr else path.read_bytes()


def _parse_symbols(bd: Path) -> dict[str, int]:
    syms: dict[str, int] = {}
    if (bd / "main.sym").is_file():
        for line in (bd / "main.sym").read_text(encoding="utf-8").splitlines():
            m = SYM_RE.match(line)
            if m and m.group(1) not in syms:
                syms[m.group(1)] = int(m.group(2), 16)
    if (bd / "main.vs").is_file():
        for line in (bd / "main.vs").read_text(encoding="utf-8").splitlines():
            m = VS_RE.match(line)
            if m and m.group(2) not in syms:
                syms[m.group(2)] = int(m.group(1), 16)
    return syms


def _read_sym_slice(segments: list[tuple[int, bytes]], addr: int, size: int) -> bytes | None:
    for base, body in segments:
        if base <= addr and addr + size <= base + len(body):
            off = addr - base
            return body[off : off + size]
    return None


def verify_port(
    port: str,
    build_root: Path = DEFAULT_BUILD_ROOT,
    spec: dict | None = None,
    icat_override: bytes | None = None,
    max_errors: int = 20,
) -> list[str]:
    if spec is None:
        spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    bd = build_root / port
    errors: list[str] = []

    def fail(msg: str) -> bool:
        errors.append(f"{port}: {msg}")
        return len(errors) >= max_errors

    try:
        icat_blob = icat_override if icat_override is not None else read_port_item_cat(port, build_root)
        dec = bic.decode_item_cat(icat_blob)
    except Exception as exc:
        return [f"{port}: ITEM.CAT decode failed: {exc}"]

    items = spec["items"]
    if len(dec["items"]) != len(items):
        return [f"{port}: ITEM.CAT item count {len(dec['items'])} != {len(items)}"]

    cold_keys = (
        "id", "name", "cost", "is_depth_variant", "weight", "dice", "sides",
        "flags", "p1", "tohit", "todam", "toac", "vms_level", "missile_type",
    )
    for exp, got in zip(items, dec["items"]):
        for k in cold_keys:
            if got[k] != exp[k] and fail(f"item #{exp['id']} {k}: {got[k]!r} != {exp[k]!r}"):
                return errors
    for exp, got in zip(spec["egos"], dec["egos"]):
        for k in ("id", "name", "cost_delta", "flags", "p1", "tohit", "todam", "toac"):
            if got[k] != exp[k] and fail(f"ego #{exp['id']} {k}: {got[k]!r} != {exp[k]!r}"):
                return errors
    for exp, got in zip(spec["flavours"], dec["flavours"]):
        if got["name"] != exp["name"] and fail(f"flavour #{exp['id']}: {got['name']!r} != {exp['name']!r}"):
            return errors

    syms = _parse_symbols(bd)
    segments = [_load_prg(bd / fn) for fn in PORT_HOT_PRGS[port] if (bd / fn).is_file()]
    extra_ac = [it for it in items if it["base_ac"] >= 15]
    expected_tables = {
        "it_category": bytes(it["cat"] for it in items),
        "it_color_ac": bytes(((it["color"] & 0x0F) << 4) | min(it["base_ac"], 15) for it in items),
        "it_ac_extra_id_lo": bytes(it["id"] & 0xFF for it in extra_ac),
        "it_ac_extra_id_hi": bytes(it["id"] >> 8 for it in extra_ac),
        "it_ac_extra_val": bytes(it["base_ac"] for it in extra_ac),
        "it_unknown_idx": bytes(it["unknown_idx"] for it in items),
        "flavour_colors": bytes(fl["color"] for fl in spec["flavours"]),
    }
    for label, exp_bytes in expected_tables.items():
        if label not in syms:
            if fail(f"missing symbol {label} in {bd}"):
                return errors
            continue
        got_bytes = _read_sym_slice(segments, syms[label], len(exp_bytes))
        if got_bytes is None:
            if fail(f"symbol {label}=${syms[label]:04x} not covered by {PORT_HOT_PRGS[port]}"):
                return errors
            continue
        if got_bytes != exp_bytes:
            idx = next(i for i, (a, b) in enumerate(zip(got_bytes, exp_bytes)) if a != b)
            if fail(f"{label}[{idx}]: 0x{got_bytes[idx]:02x} != 0x{exp_bytes[idx]:02x}"):
                return errors

    return errors


class CheckItemCatalogPortsSelfTest(unittest.TestCase):
    def test_spec_and_synthetic_port_roundtrip(self) -> None:
        spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        self.assertEqual(len(spec["items"]), IID.ITEM_TYPE_COUNT)
        blob, _ = bic.build_item_cat(spec)
        items = spec["items"]
        extra_ac = [it for it in items if it["base_ac"] >= 15]
        hot_chunks = [
            ("it_category", bytes(it["cat"] for it in items)),
            ("it_color_ac", bytes(((it["color"] & 0x0F) << 4) | min(it["base_ac"], 15) for it in items)),
            ("it_ac_extra_id_lo", bytes(it["id"] & 0xFF for it in extra_ac)),
            ("it_ac_extra_id_hi", bytes(it["id"] >> 8 for it in extra_ac)),
            ("it_ac_extra_val", bytes(it["base_ac"] for it in extra_ac)),
            ("it_unknown_idx", bytes(it["unknown_idx"] for it in items)),
            ("flavour_colors", bytes(fl["color"] for fl in spec["flavours"])),
        ]
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            bd = root / "c64"
            bd.mkdir()
            sym_lines = []
            payload = bytearray()
            base = 0x4000
            for name, chunk in hot_chunks:
                sym_lines.append(f".label {name}=${base + len(payload):04x}")
                payload.extend(chunk)
            (bd / "main.sym").write_text("\n".join(sym_lines) + "\n", encoding="utf-8")
            (bd / "moria8.prg").write_bytes(b"\x00\x40" + bytes(payload))
            (bd / "item.cat").write_bytes(b"\x00\xe0" + blob)
            self.assertEqual(verify_port("c64", build_root=root, spec=spec), [])
            bad_prg = bytearray((bd / "moria8.prg").read_bytes())
            bad_prg[2 + 10] ^= 0xFF
            (bd / "moria8.prg").write_bytes(bytes(bad_prg))
            self.assertIn("it_category[10]", verify_port("c64", build_root=root, spec=spec)[0])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify 0..360 item names, categories, and tables across ports.")
    parser.add_argument("--selftest", action="store_true", help="Run offline unit self-tests")
    parser.add_argument("--port", action="append", choices=CANONICAL_PORTS, help="Specific port(s) to verify")
    parser.add_argument("--if-built", action="append", choices=CANONICAL_PORTS, help="Additional port(s) to verify if built")
    parser.add_argument("--all-built", action="store_true", help="Verify every port whose build/<port> artifacts exist")
    parser.add_argument("--build-root", type=Path, default=DEFAULT_BUILD_ROOT, help="Build root directory (default: build/)")
    args = parser.parse_args(argv)

    if args.selftest:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(CheckItemCatalogPortsSelfTest)
        return 0 if unittest.TextTestRunner(verbosity=1).run(suite).wasSuccessful() else 1

    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    ports: list[str] = list(args.port or [])
    for p in args.if_built or ():
        if p not in ports and is_port_built(p, args.build_root):
            ports.append(p)
    if args.all_built:
        for p in CANONICAL_PORTS:
            if p not in ports and is_port_built(p, args.build_root):
                ports.append(p)
    if not ports and not args.all_built and not args.if_built:
        ports = list(CANONICAL_PORTS)
    if not ports:
        print("check_item_catalog_ports: no built ports found to check", file=sys.stderr)
        return 1

    all_errors: list[str] = []
    for p in ports:
        errs = verify_port(p, build_root=args.build_root, spec=spec)
        if errs:
            all_errors.extend(errs)
        else:
            print(f"PASS check_item_catalog_ports [{p}]: all {len(spec['items'])} items (0..{len(spec['items']) - 1}) name + category + cold/hot tables verified")
    if all_errors:
        for e in all_errors[:40]:
            print(f"FAIL: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
