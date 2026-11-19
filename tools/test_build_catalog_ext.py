#!/usr/bin/env python3
"""Unit tests for Phase 5 extended monster catalog generation & disk/PackBits helpers."""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "tools"))
import build_catalog as bc  # noqa: E402
import catalog_disk as cd  # noqa: E402
import extract_vms_creatures as evc  # noqa: E402


def simulate_6502_packbits_unpack(stream: bytes) -> bytes:
    """Exact instruction-level model of the 6502 PackBits unpacker documented in build_catalog.py."""
    src_idx = 0
    dst = bytearray()

    def next_src_byte() -> int:
        nonlocal src_idx
        b = stream[src_idx]
        src_idx += 1
        return b

    while True:
        a = next_src_byte()
        # cmp #$80
        if a == 0x80:  # beq !pb_done+
            break
        if a >= 0x80:  # bcs !pb_run+ (C = 1)
            # eor #$ff ; adc #1 (with C = 1 -> +2)
            a = ((a ^ 0xFF) + 1 + 1) & 0xFF
            x = a
            val = next_src_byte()
            while True:
                dst.append(val)
                x = (x - 1) & 0xFF
                if x == 0:
                    break
        else:
            x = a
            while True:
                dst.append(next_src_byte())
                x = (x - 1) & 0xFF
                if x & 0x80:  # bpl !pb_lit- (loops until X wraps 0 -> $FF)
                    break
    return bytes(dst)


def make_synthetic_d64_with_files(files: list[tuple[str, bytes]]) -> bytes:
    """Create a minimal valid 35-track 1541 D64 image in memory (no external c1541 needed)."""
    total_sectors = sum(cd.SECTORS_PER_TRACK[1:])
    image = bytearray(total_sectors * 256)

    # Allocate data sectors sequentially on tracks 1..17, 19..35 (skipping directory track 18).
    free_ts = [
        (t, s)
        for t in range(1, 36)
        if t != 18
        for s in range(cd.SECTORS_PER_TRACK[t])
    ]
    alloc_cursor = 0
    dir_entries: list[tuple[str, int, int, int]] = []

    for fname, data in files:
        assert len(data) > 0
        chunks = [data[i : i + 254] for i in range(0, len(data), 254)]
        allocated = free_ts[alloc_cursor : alloc_cursor + len(chunks)]
        assert len(allocated) == len(chunks), "Synthetic D64 full"
        alloc_cursor += len(chunks)

        for idx, ((t, s), chunk) in enumerate(zip(allocated, chunks)):
            off = cd.sector_offset(t, s)
            if idx + 1 < len(allocated):
                nt, ns = allocated[idx + 1]
                image[off] = nt
                image[off + 1] = ns
                image[off + 2 : off + 2 + len(chunk)] = chunk
            else:
                image[off] = 0
                image[off + 1] = len(chunk) + 1  # 1541 last-byte index (1 + payload len)
                image[off + 2 : off + 2 + len(chunk)] = chunk

        first_t, first_s = allocated[0]
        dir_entries.append((fname.upper(), first_t, first_s, len(chunks)))

    # Populate directory starting at track 18, sector 1 (8 entries per sector).
    dir_sectors = -(-max(1, len(dir_entries)) // 8)
    for dsec_idx in range(dir_sectors):
        sec_num = 1 + dsec_idx * 3
        off = cd.sector_offset(18, sec_num)
        if dsec_idx + 1 < dir_sectors:
            image[off] = 18
            image[off + 1] = 1 + (dsec_idx + 1) * 3
        else:
            image[off] = 0
            image[off + 1] = 0xFF
        batch = dir_entries[dsec_idx * 8 : (dsec_idx + 1) * 8]
        for e_idx, (uname, ft, fs, blks) in enumerate(batch):
            eoff = off + e_idx * 32
            image[eoff + 2] = 0x82  # closed PRG
            image[eoff + 3] = ft
            image[eoff + 4] = fs
            padded_name = uname.encode("latin-1")[:16].ljust(16, b"\xa0")
            image[eoff + 5 : eoff + 21] = padded_name
            image[eoff + 30] = blks & 0xFF
            image[eoff + 31] = (blks >> 8) & 0xFF

    return bytes(image)


class TestBuildCatalogExt(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.spec_doc = bc.load_spec()
        cls.creatures = cls.spec_doc["creatures"]
        cls.shared_dir = REPO_ROOT / "platforms" / "shared" / "catalog"

    def test_no_hardcoded_external_paths_rule9(self) -> None:
        for script_name in ("build_catalog.py", "catalog_disk.py"):
            src = (REPO_ROOT / "tools" / script_name).read_text(encoding="utf-8")
            for forbidden in ("/home/", "/Users/", "/tmp/", "moria8-upstream", "$HOME", "~/"):
                self.assertNotIn(forbidden, src, f"Rule 9 violation ({forbidden!r}) in {script_name}")

    def test_committed_catalog_ext_fields_asm_and_cdefense_bit7(self) -> None:
        ext_asm_path = self.shared_dir / "catalog_ext_fields.s"
        self.assertTrue(ext_asm_path.is_file())
        committed_text = ext_asm_path.read_text(encoding="utf-8")
        self.assertEqual(committed_text, bc.format_ext_fields_asm(self.creatures))

        arrays = cd.byte_arrays(committed_text)
        total_bytes = 0
        for label in bc.EXT_FIELD_LABELS:
            self.assertIn(label, arrays)
            self.assertEqual(len(arrays[label]), 279)
            total_bytes += len(arrays[label])
        self.assertEqual(total_bytes, 2232)

        # Verify cat_cdefense carries cdefense7 | ($80 if cm_invisible else 0) on every species.
        invisible_count = 0
        for idx, c in enumerate(self.creatures):
            expected = c["cdefense7"] | (0x80 if c["cm_invisible"] else 0)
            self.assertEqual(arrays["cat_cdefense"][idx], expected)
            if c["cm_invisible"]:
                invisible_count += 1
                self.assertTrue(arrays["cat_cdefense"][idx] & 0x80)
            else:
                self.assertFalse(arrays["cat_cdefense"][idx] & 0x80)
        self.assertEqual(invisible_count, 22)

    def test_committed_catalog_fields_and_index_phase5_parity(self) -> None:
        # Verify committed catalog_fields.s & catalog_index.s hold full 279/279 Phase 5 VMS parity.
        audit = evc.audit_against_catalog_fields(self.creatures)
        self.assertEqual(audit["invariant_mismatches"], [])
        self.assertEqual(audit["phase5_repro_mismatches"], [])
        idx_arrays = cd.byte_arrays((self.shared_dir / "catalog_index.s").read_text(encoding="utf-8"))
        self.assertEqual(idx_arrays["cat_level_playable"], idx_arrays["cat_level_raw"])
        self.assertEqual(idx_arrays["cat_undead"], bc.undead_bitmap(self.creatures))
        self.assertEqual(
            len(idx_arrays["cat_level_raw"]) + len(idx_arrays["cat_level_playable"]) + len(idx_arrays["cat_undead"]),
            117,
        )

    def test_ext_soa_and_row_major_binary_modes(self) -> None:
        soa_raw = bc.ext_soa_bytes(self.creatures)
        soa_prg = bc.ext_soa_bytes(self.creatures, prg_addr=0xA000)
        rows_raw = bc.ext_row_major_bytes(self.creatures)
        rows_prg = bc.ext_row_major_bytes(self.creatures, prg_addr=0xE000)

        self.assertEqual(len(soa_raw), 2232)
        self.assertEqual(len(soa_prg), 2234)
        self.assertEqual(soa_prg[:2], b"\x00\xa0")
        self.assertEqual(soa_prg[2:], soa_raw)

        self.assertEqual(len(rows_raw), 2232)
        self.assertEqual(len(rows_prg), 2234)
        self.assertEqual(rows_prg[:2], b"\x00\xe0")
        self.assertEqual(rows_prg[2:], rows_raw)

        # Transpose check: SoA[col * 279 + id] == RowMajor[id * 8 + col] for all 279 x 8 entries.
        for sp_id in range(279):
            for col in range(8):
                self.assertEqual(
                    soa_raw[col * 279 + sp_id],
                    rows_raw[sp_id * 8 + col],
                    f"Mismatch at species {sp_id}, col {col}",
                )

    def test_1541_9sector_monster_ext_and_catalog_disk_ext_index(self) -> None:
        ext_1541 = bc.ext_1541_sector_bytes(self.creatures, load_addr=0xE000)
        self.assertEqual(len(ext_1541), 9 * 254)
        self.assertEqual(ext_1541, cd.ext_sector_bytes(0xE000))
        self.assertEqual(ext_1541[:2], b"\x00\xe0")

        rows_raw = bc.ext_row_major_bytes(self.creatures)
        # Verify 31 x 8 B = 248 B per sector, 4 B padding, 0 cross-sector straddles across all 279 species.
        for sp_id in range(279):
            sec = sp_id // 31
            rem = sp_id % 31
            in_sec_off = 2 + rem * 8
            self.assertLessEqual(in_sec_off + 8, 254, f"Species {sp_id} straddles 1541 sector")
            slice_1541 = ext_1541[sec * 254 + in_sec_off : sec * 254 + in_sec_off + 8]
            self.assertEqual(slice_1541, rows_raw[sp_id * 8 : (sp_id + 1) * 8])

        # Test catalog_disk.py records --ext, ext-index, and fix on a synthetic D64 image.
        with tempfile.TemporaryDirectory() as tmp:
            tdir = Path(tmp)
            cd.write_records(tdir, 0xCE00, include_ext=True)
            unfixed_idx = (tdir / "monster.idx").read_bytes()
            # 2B load + 117B index + 112B (56x2) cat1..4 + 18B (9x2) ext = 249 B (<= 254 B, 1 sector)
            self.assertEqual(len(unfixed_idx), 249)
            self.assertLessEqual(len(unfixed_idx), 254)

            d64_files = [
                (name, (tdir / name).read_bytes())
                for name in [*cd.FILES, cd.EXT_FILE, cd.INDEX_FILE]
            ]
            d64_path = tdir / "test_ext.d64"
            d64_path.write_bytes(make_synthetic_d64_with_files(d64_files))

            idx_out = tdir / "idx_from_d64.prg"
            cd.write_index(d64_path, idx_out, 0xCE00, include_ext=True)
            idx_data = idx_out.read_bytes()
            self.assertEqual(len(idx_data), 249)
            self.assertEqual(idx_data[:2], b"\x00\xce")

            cat_tracks = list(idx_data[2 + 117 : 2 + 117 + 56])
            cat_secs = list(idx_data[2 + 117 + 56 : 2 + 117 + 112])
            ext_tracks = list(idx_data[2 + 117 + 112 : 2 + 117 + 112 + 9])
            ext_secs = list(idx_data[2 + 117 + 112 + 9 : 2 + 117 + 112 + 18])
            self.assertTrue(all(t > 0 for t in cat_tracks))
            self.assertTrue(all(t > 0 for t in ext_tracks))
            self.assertEqual(len(ext_secs), 9)

            # Verify fix_index updates the 249-byte MONSTER.IDX in place cleanly.
            cd.fix_index(d64_path)
            fixed_img = d64_path.read_bytes()
            idx_ts = cd.chain(fixed_img, *cd.directory(fixed_img)[cd.INDEX_FILE])
            self.assertEqual(len(idx_ts), 1)
            idx_sec_off = cd.sector_offset(*idx_ts[0])
            self.assertEqual(fixed_img[idx_sec_off + 2 : idx_sec_off + 2 + 249], idx_data)

    def test_phase5_57byte_records_and_atari_140_sectors(self) -> None:
        legacy_recs = bc.fixed_records(self.creatures, phase5=False)
        self.assertEqual(len(legacy_recs), 279)
        self.assertTrue(all(len(r) == 49 for r in legacy_recs))

        # Committed catalog_fields.s is now Phase 5, so cd.records(phase5=False) builds
        # 49 B Phase 5 core records (2B id + 21B Phase 5 core + 26B name).
        committed_core_recs = cd.records(phase5=False)
        self.assertEqual(len(committed_core_recs), 279)
        self.assertTrue(all(len(r) == 49 for r in committed_core_recs))

        p5_recs = bc.fixed_records(self.creatures, phase5=True)
        self.assertEqual(p5_recs, cd.records(phase5=True))
        self.assertEqual(len(p5_recs), 279)
        self.assertTrue(all(len(r) == 57 for r in p5_recs))
        self.assertEqual(sum(len(r) for r in p5_recs), 15903)

        # Verify 16-bit ID [lo, hi], 21 Phase 5 core fields, 8 Phase 5 ext fields, and NUL-terminated name.
        for n, rec in enumerate(p5_recs):
            self.assertEqual(rec[0] | (rec[1] << 8), n)
            self.assertEqual(committed_core_recs[n][:23], rec[:23])
            self.assertEqual(committed_core_recs[n][23:], rec[2 + 29 :])
            ext_slice = list(rec[2 + 21 : 2 + 29])
            self.assertEqual(ext_slice, bc.phase5_ext_row(self.creatures[n]))
            self.assertEqual(rec[-1], 0)

        atari_p5 = bc.atari_monster_cat_bytes(self.creatures, phase5=True)
        self.assertEqual(atari_p5, cd.atari_records(phase5=True))
        # 139 full 125 B DOS 2.5 sectors (2 * 57 = 114 B + 11 B pad) + 1 tail sector of 57 B = 140 sectors
        self.assertEqual(len(atari_p5), 139 * 125 + 57)
        for sp_id in range(279):
            sec = sp_id // 2
            off = sec * 125 + (sp_id % 2) * 57
            self.assertEqual(atari_p5[off : off + 57], p5_recs[sp_id])

    def test_packbits_roundtrip_6502_unpack_and_measured_sizes(self) -> None:
        # Edge-case synthetic vectors (empty, 0x80 literal byte, 128/129 literal & run boundaries).
        vectors = [
            b"",
            b"\x80",
            b"\x80" * 2,
            b"\x80" * 3,
            b"\x80" * 128,
            b"\x80" * 129,
            b"\x00" * 300,
            bytes(i & 0xFF for i in range(300)),
            b"X" + b"A" * 2 + b"Y" + b"B" * 3 + b"Z" + b"\x80" * 5,
            b"M" * 129 + b"Q",
        ]
        for vec in vectors:
            enc = bc.packbits_encode(vec)
            self.assertEqual(enc[-1], 0x80)
            self.assertEqual(bc.packbits_decode(enc), vec)
            self.assertEqual(simulate_6502_packbits_unpack(enc), vec)

        # Reject malformed streams.
        with self.assertRaises(ValueError):
            bc.packbits_decode(b"\x00\x41")  # missing $80 EOF
        with self.assertRaises(ValueError):
            bc.packbits_decode(b"\x80\x00")  # trailing byte after $80 EOF

        # Real catalog payloads (standalone from committed repo sources, zero build/ dependency).
        fields_arrays = cd.byte_arrays((self.shared_dir / "catalog_fields.s").read_text(encoding="utf-8"))
        a2_catalog_raw = bytes(
            b for k in bc.CORE_FIELD_KEYS for b in fields_arrays[f"cat_{k}"]
        )
        self.assertEqual(len(a2_catalog_raw), 5859)
        a2_catext_raw = bc.ext_row_major_bytes(self.creatures)
        self.assertEqual(len(a2_catext_raw), 2232)
        atari_car_p5_raw = b"".join(bc.fixed_records(self.creatures, phase5=True))
        self.assertEqual(len(atari_car_p5_raw), 15903)

        a2_cat_enc = bc.packbits_encode(a2_catalog_raw)
        a2_ext_enc = bc.packbits_encode(a2_catext_raw)
        atari_p5_enc = bc.packbits_encode(atari_car_p5_raw)

        self.assertEqual(bc.packbits_decode(a2_cat_enc), a2_catalog_raw)
        self.assertEqual(simulate_6502_packbits_unpack(a2_cat_enc), a2_catalog_raw)
        self.assertEqual(bc.packbits_decode(a2_ext_enc), a2_catext_raw)
        self.assertEqual(simulate_6502_packbits_unpack(a2_ext_enc), a2_catext_raw)
        self.assertEqual(bc.packbits_decode(atari_p5_enc), atari_car_p5_raw)
        self.assertEqual(simulate_6502_packbits_unpack(atari_p5_enc), atari_car_p5_raw)

        self.assertLess(len(a2_cat_enc), 4750)
        self.assertLess(len(a2_ext_enc), 1300)
        self.assertLess(len(atari_p5_enc), 12000)

    def test_phase5_asm_wave54_flip_and_cli_subcommands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tdir = Path(tmp)
            # Test CLI subcommands via main([...]).
            self.assertEqual(bc.main(["ext-soa", "--out", str(tdir / "128.cex"), "--prg-addr", "0xE000"]), 0)
            self.assertEqual((tdir / "128.cex").stat().st_size, 2234)

            self.assertEqual(bc.main(["ext-rows", "--out", str(tdir / "A2.CATEXT")]), 0)
            self.assertEqual((tdir / "A2.CATEXT").stat().st_size, 2232)

            self.assertEqual(bc.main(["packbits", "--in", str(tdir / "A2.CATEXT"), "--out", str(tdir / "A2.CATEXT.pb")]), 0)
            self.assertEqual(bc.main(["packbits", "--decode", "--in", str(tdir / "A2.CATEXT.pb"), "--out", str(tdir / "A2.CATEXT.dec")]), 0)
            self.assertEqual((tdir / "A2.CATEXT.dec").read_bytes(), (tdir / "A2.CATEXT").read_bytes())

            self.assertEqual(bc.main(["ext-1541", "--out", str(tdir / "monster.ext")]), 0)
            self.assertEqual((tdir / "monster.ext").stat().st_size, 2286)

            self.assertEqual(
                bc.main(["records", "--phase5-records", "--atari-sectors", "--out", str(tdir / "MONSTER.CAT")]),
                0,
            )
            self.assertEqual((tdir / "MONSTER.CAT").stat().st_size, 17432)

            # Test Wave 5.4 phase5-asm into temp directory (leaves repo catalog_fields.s untouched).
            p5_asm_dir = tdir / "p5_asm"
            self.assertEqual(bc.main(["phase5-asm", "--out-dir", str(p5_asm_dir)]), 0)
            p5_fields = evc.parse_catalog_fields_asm(p5_asm_dir / "catalog_fields.s")
            self.assertEqual(len(p5_fields), 21)
            for idx, c in enumerate(self.creatures):
                self.assertEqual(
                    [p5_fields["cr_atk0_type"][idx], p5_fields["cr_atk0_dice"][idx], p5_fields["cr_atk0_sides"][idx]],
                    c["packed_attacks"][0],
                )
                self.assertEqual(
                    [p5_fields["cr_atk1_type"][idx], p5_fields["cr_atk1_dice"][idx], p5_fields["cr_atk1_sides"][idx]],
                    c["packed_attacks"][1],
                )
            p5_index_arrays = cd.byte_arrays((p5_asm_dir / "catalog_index.s").read_text(encoding="utf-8"))
            self.assertIn("cat_undead", p5_index_arrays)
            self.assertEqual(len(p5_index_arrays["cat_undead"]), 35)
            self.assertEqual(p5_index_arrays["cat_level_raw"], p5_index_arrays["cat_level_playable"])

    def test_catalog_fetch_split_u1_bp_and_optional_ext_assembly(self) -> None:
        cf_text = (REPO_ROOT / "platforms/commodore/common/catalog_fetch.s").read_text(encoding="utf-8")
        icr_text = (REPO_ROOT / "platforms/commodore/common/item_catalog_records.s").read_text(encoding="utf-8")

        # Must share icr_send_u1_bp / icr_drive_ok and never concatenate U1 + B-P in one CHKOUT.
        self.assertIn("jsr icr_send_u1_bp", cf_text)
        self.assertIn("jsr icr_drive_ok", icr_text)
        self.assertNotIn("cfr_u1:", cf_text)
        self.assertNotIn("cfr_bp:", cf_text)
        self.assertIn("#if CATALOG_EXT_DISK_ENABLED", cf_text)
        self.assertIn("catalog_fetch_ext:", cf_text)

        # If KickAss.jar is installed locally, verify #define CATALOG_EXT_DISK_ENABLED + CATALOG_REU assembles cleanly.
        kickass_jar = REPO_ROOT / "tools" / "kickass" / "KickAss.jar"
        java_wrapper = REPO_ROOT / "tools" / "kickass_java.sh"
        if kickass_jar.is_file() and java_wrapper.is_file() and shutil.which("java"):
            with tempfile.TemporaryDirectory() as tmp:
                tdir = Path(tmp)
                harness_s = tdir / "test_ext_compile.s"
                harness_s.write_text(
                    "\n".join(
                        [
                            ".const CATALOG_HIDDEN_BASE = $d400",
                            ".const CATALOG_HIDDEN_END = $d4ff",
                            "#define CATALOG_REU",
                            "#define CATALOG_EXT_DISK_ENABLED",
                            ".const BANK_ALL_RAM = $34",
                            ".const REU_STATUS = $df00",
                            ".const REU_COMMAND = $df01",
                            ".const REU_C64LO = $df02",
                            ".const REU_C64HI = $df03",
                            ".const REU_REULO = $df04",
                            ".const REU_REUHI = $df05",
                            ".const REU_BANK = $df06",
                            ".const REU_LENLO = $df07",
                            ".const REU_LENHI = $df08",
                            ".const REU_CONTROL = $df0a",
                            ".const REU_CMD_FETCH = $91",
                            ".label zp_temp0 = $10",
                            ".label zp_temp1 = $11",
                            ".label zp_temp2 = $12",
                            ".label zp_temp3 = $13",
                            ".macro CatalogMap() { }",
                            ".macro CatalogUnmap() { }",
                            ".macro CatalogKernalIn() { }",
                            ".macro CatalogKernalOut() { }",
                            "* = $0810",
                            "cat_id_lo: .byte 0",
                            "cat_id_hi: .byte 0",
                            "item_cat_off_lo: .byte 0",
                            "item_cat_off_hi: .byte 0",
                            "reu_present: .byte 0",
                            "program_device: .byte 8",
                            "alr_len: .byte 0",
                            "alr_name_lo: .byte 0",
                            "alr_name_hi: .byte 0",
                            "alr_left: .byte 0",
                            "vis_room_revealed: .byte 0",
                            "status_cache_valid: .byte 0",
                            "nf_digit_buf: .fill 5, 0",
                            "numeric_format_u8: rts",
                            "asset_load_ask_for_disk: rts",
                            "hal_storage_setnam: rts",
                            "hal_storage_setlfs: rts",
                            "hal_storage_open: rts",
                            "hal_storage_close: rts",
                            "hal_storage_chkin: rts",
                            "hal_storage_chkout: rts",
                            "hal_storage_chrin: rts",
                            "hal_storage_chrout: rts",
                            "hal_storage_clrchn: rts",
                            "hal_storage_readst: rts",
                            '#import "catalog_fetch.s"',
                            '#define ITEM_CATALOG_REU',
                            '.const ITEM_CAT_REU_BANK = 1',
                            '.const ITEM_CAT_REU_BASE = $0000',
                            '#import "item_catalog_records.s"',
                            '.assert "Extended CatalogHidden size is 247 bytes", CATALOG_IDX_SIZE, 247',
                        ]
                    )
                    + "\n",
                    encoding="utf-8",
                )
                res = subprocess.run(
                    [
                        str(java_wrapper),
                        "-jar",
                        str(kickass_jar),
                        str(harness_s),
                        "-libdir",
                        str(REPO_ROOT / "platforms/commodore/common"),
                        "-o",
                        str(tdir / "out.prg"),
                    ],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(res.returncode, 0, res.stdout + "\n" + res.stderr)


if __name__ == "__main__":
    unittest.main()
