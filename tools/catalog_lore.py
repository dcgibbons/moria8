"""The generated monster catalog (platforms/shared/catalog), read for the
runtime harnesses' catalog checks: constants, field bytes and names."""

from __future__ import annotations

from pathlib import Path

CATALOG_DIR = Path(__file__).resolve().parents[1] / "platforms" / "shared" / "catalog"


def const(name: str) -> int:
    """A .const from catalog_index.s."""
    for line in (CATALOG_DIR / "catalog_index.s").read_text().splitlines():
        if line.startswith(f".const {name} = "):
            return int(line.split("=")[1])
    raise KeyError(name)


def name(cid: int) -> list[int]:
    """Creature ``cid``'s name in screen codes, from catalog_names.s's comments."""
    for line in (CATALOG_DIR / "catalog_names.s").read_text().splitlines():
        if line.startswith(f"catn_{cid}:"):
            return [ord(ch) - 0x60 if "a" <= ch <= "z" else ord(ch) for ch in line.split("// ", 1)[1].rstrip()]
    raise KeyError(cid)


def field(label: str, filename: str = "catalog_fields.s") -> list[int]:
    """The .byte values after ``label`` in a generated catalog file, to the next label."""
    out: list[int] = []
    found = False
    for line in (CATALOG_DIR / filename).read_text().splitlines():
        text = line.split("//")[0].strip()
        if not found:
            if not text.startswith(f"{label}:"):
                continue
            found = True
            text = text[len(label) + 1:].strip()
        elif not text.startswith(".byte"):
            break
        if text:
            out += [int(v.strip().lstrip("$"), 16) for v in text[5:].split(",")]
    if not found:
        raise KeyError(label)
    return out
