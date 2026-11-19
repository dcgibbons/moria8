import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "tools"))

import check_item_catalog_ports as cicp  # noqa: E402


class ItemCatalogPortsTest(cicp.CheckItemCatalogPortsSelfTest):
    def _built_ports(self, build_root: Path = cicp.DEFAULT_BUILD_ROOT) -> list[str]:
        targets = getattr(cicp, "ALL_TARGETS", cicp.CANONICAL_PORTS)
        built = [p for p in targets if cicp.is_port_built(p, build_root)]
        if not built:
            self.skipTest(f"no built ports under {build_root}; run make build first")
        return built

    def test_built_ports_item_catalog_0_360(self) -> None:
        built = self._built_ports()
        rc = cicp.main(["--all-built"])
        self.assertEqual(rc, 0, f"Cross-port 0..360 item catalog check failed across {built}")

    def test_negative_item_cat_mutation_detected(self) -> None:
        port = self._built_ports()[0]
        spec = json.loads(cicp.SPEC_PATH.read_text(encoding="utf-8"))
        bad_icat = bytearray(cicp.read_port_item_cat(port))
        # Corrupt non-gold item records starting at #20 (ITMCAT_HDR_SIZE=32 + 20*4 = 112)
        for off in range(112, min(len(bad_icat), 112 + 100)):
            bad_icat[off] ^= 0x3F
        errs = cicp.verify_port(port, spec=spec, icat_override=bytes(bad_icat), max_errors=1)
        self.assertTrue(errs, f"{port}: corrupt ITEM.CAT records unexpectedly passed")

    def test_skips_when_nothing_is_built(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(unittest.SkipTest):
                self._built_ports(Path(td))


if __name__ == "__main__":
    unittest.main()
