#!/usr/bin/env python3
"""Self-contained unit tests for platforms/shared/catalog/monster_catalog_spec.json.

Runs strictly inside the repository with zero external filesystem or network
access:
  python3 -B -m unittest tools/test_monster_catalog_spec.py
"""

from __future__ import annotations

import contextlib
import io
import json
import re
import sys
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

import extract_vms_creatures as evc  # noqa: E402


class TestMonsterCatalogSpec(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.spec_path = evc.DEFAULT_SPEC_OUT
        cls.fields_path = evc.DEFAULT_CATALOG_FIELDS
        cls.index_path = evc.DEFAULT_CATALOG_INDEX
        cls.names_path = evc.DEFAULT_CATALOG_NAMES

        cls.doc = json.loads(cls.spec_path.read_text(encoding="utf-8"))
        cls.creatures = cls.doc["creatures"]
        cls.catalog_fields = evc.parse_catalog_fields_asm(cls.fields_path)
        cls.catalog_names = evc.parse_catalog_names_comments(cls.names_path)

    def test_top_level_schema_and_constants(self) -> None:
        self.assertEqual(self.doc["schema_version"], 1)
        self.assertEqual(self.doc["source"]["upstream"], "VMS Moria 4.8")
        self.assertEqual(self.doc["source"]["upstream_file"], "source/include/values.inc")
        self.assertEqual(self.doc["source"]["pinned_commit"], evc.PINNED_VMS_COMMIT)

        consts = self.doc["constants"]
        self.assertEqual(consts["CREATURE_COUNT"], 279)
        self.assertEqual(consts["TOWN_CREATURE_COUNT"], 8)
        self.assertEqual(consts["MAX_MONS_LEVEL"], 40)
        self.assertEqual(consts["WIN_MON_TOT"], 2)
        self.assertEqual(consts["IGGY_INDEX"], 277)
        self.assertEqual(consts["BALROG_INDEX"], 278)
        self.assertEqual(consts["MAX_ATTACKS"], 4)
        self.assertEqual(consts["MAX_ATTACK_SIDES"], 14)
        self.assertEqual(consts["MAX_ATTACK_ADESC"], 19)
        self.assertEqual(consts["SOA_CORE_FIELDS"], 21)
        self.assertEqual(consts["SOA_EXT_FIELDS"], 8)
        self.assertEqual(consts["SOA_TOTAL_FIELDS"], 29)

    def test_species_count_ordering_and_vms_landmarks(self) -> None:
        self.assertEqual(len(self.creatures), 279)
        indices = [c["index"] for c in self.creatures]
        self.assertEqual(indices, list(range(279)))

        # Every (name, level) pair in VMS c_list is unique (Large Grey Snake is at DL3 #46 and DL4 #57).
        name_level_pairs = [(c["name"], c["level"]) for c in self.creatures]
        self.assertEqual(len(set(name_level_pairs)), 279)

        levels = [c["level"] for c in self.creatures]
        self.assertEqual(levels, sorted(levels))
        self.assertTrue(all(c["level"] == 0 for c in self.creatures[:8]))
        self.assertTrue(all(1 <= c["level"] <= 40 for c in self.creatures[8:277]))

        # Key VMS Moria 4.8 species landmarks distinguishing VMS c_list from Umoria 5.7.15:
        self.assertEqual(self.creatures[231]["name"], "Crystal Ooze")
        self.assertEqual(self.creatures[231]["level"], 31)
        self.assertEqual(self.creatures[231]["speed"], -1)
        self.assertEqual(self.creatures[275]["name"], "Emperor Lich")
        self.assertEqual((self.creatures[275]["hd_count"], self.creatures[275]["hd_sides"]), (190, 8))
        self.assertEqual(self.creatures[276]["name"], "Ancient Multi-Hued Dragon")
        self.assertEqual((self.creatures[276]["hd_count"], self.creatures[276]["hd_sides"]), (260, 8))
        self.assertEqual((self.creatures[276]["hd_num"], self.creatures[276]["hd_sides_scaled"]), (130, 16))
        self.assertEqual(self.creatures[277]["name"], "Evil Iggy")
        self.assertEqual(self.creatures[277]["level"], 50)
        self.assertEqual((self.creatures[277]["hd_count"], self.creatures[277]["hd_sides"]), (300, 8))
        self.assertEqual(self.creatures[278]["name"], "Balrog")
        self.assertEqual(self.creatures[278]["level"], 100)
        self.assertEqual((self.creatures[278]["hd_count"], self.creatures[278]["hd_sides"]), (375, 8))

    def test_field_validity_and_byte_ranges(self) -> None:
        byte_fields = (
            "display",
            "color",
            "speed_byte",
            "mflags",
            "hd_num",
            "hd_sides_scaled",
            "sleep_byte",
            "aaf_byte",
            "xp_lo",
            "xp_hi",
            "spell_chance",
            "spell_flags",
            "spell_flags2",
            "cdefense7",
            "cdefense_byte",
            "treasure",
        )
        for c in self.creatures:
            self.assertTrue(isinstance(c["name"], str) and len(c["name"]) > 0)
            self.assertTrue(isinstance(c["moria8_name"], str) and len(c["moria8_name"]) > 0)
            self.assertTrue(isinstance(c["cchar"], str) and len(c["cchar"]) == 1)
            self.assertGreaterEqual(c["hd_count"], 1)
            self.assertGreaterEqual(c["hd_sides"], 1)
            self.assertEqual(c["hd_count"] * c["hd_sides"], c["hd_num"] * c["hd_sides_scaled"])
            self.assertLess(c["hd_count"] * c["hd_sides"], 65536)
            self.assertTrue(0 <= c["ac"] <= 255)
            self.assertTrue(0 <= c["sleep"] <= 65535)
            self.assertTrue(0 <= c["aaf"] <= 127)
            self.assertTrue(-1 <= c["speed"] <= 3)
            self.assertTrue(0 <= c["mexp"] <= 65535)
            self.assertEqual(c["xp_lo"] | (c["xp_hi"] << 8), c["mexp"])
            self.assertEqual(c["cmove_hex"], f"0x{c['cmove']:08X}")
            self.assertEqual(c["spells_hex"], f"0x{c['spells']:08X}")
            self.assertEqual(c["cdefense_hex"], f"0x{c['cdefense']:04X}")

            for bf in byte_fields:
                self.assertTrue(0 <= c[bf] <= 255, f"#{c['index']} {bf}={c[bf]} out of byte range")
            self.assertTrue(0 <= c["cdefense7"] <= 0x7F)
            self.assertTrue(0 <= c["treasure"] <= 0x7F)

    def test_all_four_attacks_bounds_and_lossless_roundtrip(self) -> None:
        total_slots = 0
        max_sides_seen = 0
        max_adesc_seen = 0
        for c in self.creatures:
            atks = c["attacks"]
            packed = c["packed_attacks"]
            self.assertEqual(len(atks), 4)
            self.assertEqual(len(packed), 4)
            for slot_idx, (a, p) in enumerate(zip(atks, packed)):
                total_slots += 1
                adtype = a["adtype"]
                adesc = a["adesc"]
                dice = a["dice"]
                sides = a["sides"]

                self.assertIn(adtype, evc.VALID_ADTYPES, f"#{c['index']} atk{slot_idx} invalid adtype={adtype}")
                self.assertTrue(0 <= adesc <= 19, f"#{c['index']} atk{slot_idx} adesc={adesc}")
                self.assertTrue(0 <= dice <= 255, f"#{c['index']} atk{slot_idx} dice={dice}")
                self.assertTrue(0 <= sides <= 14, f"#{c['index']} atk{slot_idx} sides={sides} > 14")
                self.assertLessEqual(sides, 15)

                max_sides_seen = max(max_sides_seen, sides)
                max_adesc_seen = max(max_adesc_seen, adesc)

                self.assertEqual(len(p), 3)
                self.assertTrue(all(0 <= b <= 255 for b in p))
                self.assertEqual(tuple(p), evc.pack_attack(adtype, adesc, dice, sides))
                self.assertEqual(evc.unpack_attack(*p), (adtype, adesc, dice, sides))

                if adtype in (0, 99):
                    self.assertEqual((adesc, dice, sides), (0, 0, 0))
                    self.assertEqual(p, [0, 0, 0])

        self.assertEqual(total_slots, 279 * 4)
        self.assertEqual(max_sides_seen, 14)
        self.assertEqual(max_adesc_seen, 19)

        # Exhaustive synthetic check of #360 backwards-compatibility & bit packing across domain:
        for adtype in sorted(evc.VALID_ADTYPES):
            if adtype in (0, 99):
                t, d, sv = evc.pack_attack(adtype, 0, 0, 0)
                self.assertEqual(evc.unpack_attack(t, d, sv), (adtype, 0, 0, 0))
                continue
            for adesc in range(0, 20):
                for sides in range(0, 15):
                    t, d, sv = evc.pack_attack(adtype, adesc, 17, sides)
                    if adesc == 0:
                        self.assertEqual(t, adtype)
                        self.assertEqual(sv, sides)
                    self.assertEqual(evc.unpack_attack(t, d, sv), (adtype, adesc, 17, sides))

    def test_spells_spell_flags2_cmove_and_cdefense_lossless_roundtrip(self) -> None:
        ext_cmove_mask = evc.VMS_CM_PHASE | evc.VMS_CM_EATS_OTHER | evc.VMS_CM_PICKS_UP
        for c in self.creatures:
            # 1. Spells + extended cmove roundtrip through (spell_chance, spell_flags, spell_flags2)
            sc, sf, sf2 = evc.pack_spells_and_cmove_ext(c["spells"], c["cmove"])
            self.assertEqual((sc, sf, sf2), (c["spell_chance"], c["spell_flags"], c["spell_flags2"]))
            unpacked_spells, unpacked_cmove_ext = evc.unpack_spells_and_cmove_ext(
                c["spell_chance"], c["spell_flags"], c["spell_flags2"]
            )
            self.assertEqual(unpacked_spells, c["spells"], f"Spell roundtrip loss on #{c['index']} {c['name']}")
            self.assertEqual(
                unpacked_cmove_ext,
                c["cmove"] & ext_cmove_mask,
                f"Extended cmove roundtrip loss on #{c['index']} {c['name']}",
            )

            # 2. cdefense + CM_INVISIBLE roundtrip
            self.assertEqual(evc.pack_cdefense7(c["cdefense"]), c["cdefense7"])
            unpacked_cdef = evc.unpack_cdefense(c["cdefense7"], c["mflags"], c["speed_byte"])
            self.assertEqual(unpacked_cdef, c["cdefense"], f"cdefense roundtrip loss on #{c['index']} {c['name']}")
            self.assertEqual(c["cm_invisible"], bool(c["cmove"] & evc.VMS_CM_INVISIBLE))
            self.assertEqual(bool(c["cdefense_byte"] & evc.CDEF_CM_INVISIBLE), c["cm_invisible"])
            self.assertEqual(c["cdefense_byte"] & 0x7F, c["cdefense7"])

            # 3. Remaining cmove bit projections
            self.assertEqual(c["speed_byte"] & 0x38, c["cmove"] & evc.VMS_CM_RANDOM_MASK)
            self.assertEqual(bool(c["aaf_byte"] & 0x80), bool(c["cmove"] & evc.VMS_CM_OPEN_DOOR))
            self.assertEqual(bool(c["mflags"] & 0x40), bool(c["cmove"] & evc.VMS_CM_MULTIPLY))
            self.assertEqual(c["treasure"], (c["cmove"] >> 24) & 0x7F)
            self.assertEqual(bool(c["cmove"] & evc.VMS_CM_WIN), c["index"] == 278)

    def test_exact_agreement_with_committed_catalog_asm(self) -> None:
        self.assertEqual(len(self.catalog_fields), 21)
        for key, vals in self.catalog_fields.items():
            self.assertEqual(len(vals), 279, f"{key} length={len(vals)}")

        audit = evc.audit_against_catalog_fields(self.creatures, self.fields_path, self.names_path)
        self.assertEqual(audit["invariant_mismatches"], [])
        self.assertEqual(audit["phase5_repro_mismatches"], [])
        self.assertEqual(self.catalog_names, [c["moria8_name"] for c in self.creatures])

        # Also cross-check catalog_index.s constants, 279/279 playable counts, and cat_undead[35]:
        idx_text = self.index_path.read_text(encoding="utf-8")
        self.assertIn(".const CATALOG_COUNT = 279", idx_text)
        self.assertIn(".const CATALOG_TOWN_COUNT = 8", idx_text)
        self.assertIn(".const CATALOG_WIN_FIRST = 277", idx_text)
        self.assertIn(".const CATALOG_IGGY_ID = 277", idx_text)
        self.assertIn(".const CATALOG_BALROG_ID = 278", idx_text)

        m_raw = re.search(r"cat_level_raw:.*?\n\s*\.byte\s+([^\n]+)", idx_text)
        m_play = re.search(r"cat_level_playable:.*?\n\s*\.byte\s+([^\n]+)", idx_text)
        m_und = re.search(r"cat_undead:.*?\n\s*\.byte\s+([^\n]+)", idx_text)
        self.assertIsNotNone(m_raw)
        self.assertIsNotNone(m_play)
        self.assertIsNotNone(m_und)
        raw_counts = [int(tok.strip()[1:], 16) for tok in m_raw.group(1).split(",")]
        play_counts = [int(tok.strip()[1:], 16) for tok in m_play.group(1).split(",")]
        undead_bytes = [int(tok.strip()[1:], 16) for tok in m_und.group(1).split(",")]
        self.assertEqual(len(raw_counts), 41)
        expected_raw = [
            sum(1 for c in self.creatures[:277] if c["level"] == lvl)
            for lvl in range(41)
        ]
        self.assertEqual(raw_counts, expected_raw)
        self.assertEqual(play_counts, expected_raw)
        self.assertEqual(len(undead_bytes), 35)
        self.assertEqual(len(raw_counts) + len(play_counts) + len(undead_bytes), 117)
        for sp_id, c in enumerate(self.creatures):
            bit_set = bool(undead_bytes[sp_id // 8] & (1 << (sp_id % 8)))
            self.assertEqual(bit_set, bool(c["cdefense"] & evc.VMS_CD_UNDEAD))

    def test_core_monster_and_recall_defs_constants_match_spec(self) -> None:
        monster_s = (REPO_ROOT / "core" / "6502" / "monster.s").read_text(encoding="utf-8")
        recall_defs_s = (REPO_ROOT / "core" / "6502" / "recall_defs.s").read_text(encoding="utf-8")
        consts = {
            m.group(1): (int(m.group(2)[1:], 16) if m.group(2).startswith("$") else int(m.group(2)))
            for m in re.finditer(r"^\.const\s+(\w+)\s*=\s*(\$[0-9A-Fa-f]+|\d+)", monster_s, re.M)
        }
        self.assertEqual(consts["CATALOG_EXT_FIELDS"], 8)
        self.assertEqual(consts["ATK_SIDES_MASK"], 0x0F)
        self.assertEqual(consts["ATK_TYPE_MASK"], 0x7F)
        self.assertEqual(consts["CF_UNDEAD"], 0x02)

        # cr_spell_flags2 bit constants
        self.assertEqual(consts["MSF2_BLINK"], evc.MSF2_BLINK)
        self.assertEqual(consts["MSF2_TELE_SELF"], evc.MSF2_TELE_SELF)
        self.assertEqual(consts["MSF2_SUMMON_UNDEAD"], evc.MSF2_SUMMON_UNDEAD)
        self.assertEqual(consts["MSF2_SLOW"], evc.MSF2_SLOW)
        self.assertEqual(consts["MSF2_DRAIN_MANA"], evc.MSF2_DRAIN_MANA)
        self.assertEqual(consts["CM2_PHASE"], evc.MSF2_CM_PHASE)
        self.assertEqual(consts["CM2_EATS_OTHER"], evc.MSF2_CM_EATS_OTHER)
        self.assertEqual(consts["CM2_PICKS_UP"], evc.MSF2_CM_PICKS_UP)

        # cr_cdefense bit constants (bits 0..6 = cdefense7, bit 7 = CD_INVISIBLE)
        self.assertEqual(consts["CD_FROST"], evc.CDEF7_FROST)
        self.assertEqual(consts["CD_FIRE"], evc.CDEF7_FIRE)
        self.assertEqual(consts["CD_POISON"], evc.CDEF7_POISON)
        self.assertEqual(consts["CD_ACID"], evc.CDEF7_ACID)
        self.assertEqual(consts["CD_LIGHT"], evc.CDEF7_LIGHT)
        self.assertEqual(consts["CD_STONE"], evc.CDEF7_STONE)
        self.assertEqual(consts["CD_NO_SLEEP"], evc.CDEF7_NO_SLEEP)
        self.assertEqual(consts["CD_INVISIBLE"], evc.CDEF_CM_INVISIBLE)

        # All VMS ATK_* (0..24, 99) and ADESC_* (0..19) IDs
        expected_atks = {
            "ATK_NONE": 0, "ATK_NORMAL": 1, "ATK_LOSE_STR": 2, "ATK_CONFUSE": 3,
            "ATK_FEAR": 4, "ATK_FIRE": 5, "ATK_ACID": 6, "ATK_COLD": 7,
            "ATK_LIGHT": 8, "ATK_CORRODE": 9, "ATK_BLIND": 10, "ATK_PARALYZE": 11,
            "ATK_STEAL_GOLD": 12, "ATK_STEAL_ITEM": 13, "ATK_POISON": 14,
            "ATK_LOSE_DEX": 15, "ATK_LOSE_CON": 16, "ATK_LOSE_INT": 17,
            "ATK_LOSE_WIS": 18, "ATK_LOSE_EXP": 19, "ATK_AGGRAVATE": 20,
            "ATK_DISENCHANT": 21, "ATK_EAT_FOOD": 22, "ATK_EAT_LIGHT": 23,
            "ATK_EAT_CHARGES": 24, "ATK_BLANK": 99,
        }
        for k, v in expected_atks.items():
            self.assertEqual(consts[k], v)

        expected_adescs = {
            "ADESC_NONE": 0, "ADESC_HITS": 1, "ADESC_BITES": 2, "ADESC_CLAWS": 3,
            "ADESC_STINGS": 4, "ADESC_TOUCHES": 5, "ADESC_KICKS": 6, "ADESC_GAZES": 7,
            "ADESC_BREATHES": 8, "ADESC_SPITS": 9, "ADESC_WAILS": 10, "ADESC_EMBRACES": 11,
            "ADESC_CRAWLS": 12, "ADESC_SPORES": 13, "ADESC_BEGS": 14, "ADESC_SLIMES": 15,
            "ADESC_CRUSHES": 16, "ADESC_TRAMPLES": 17, "ADESC_DROOLS": 18, "ADESC_INSULTS": 19,
        }
        for k, v in expected_adescs.items():
            self.assertEqual(consts[k], v)

        for label in (
            "cr_atk2_type:", "cr_atk2_dice:", "cr_atk2_sides:",
            "cr_atk3_type:", "cr_atk3_dice:", "cr_atk3_sides:",
            "cr_spell_flags2:", "cr_cdefense:",
        ):
            self.assertIn(label, monster_s)

        for rlabel in (
            "recall_view_atk2_type:", "recall_view_atk2_dice:", "recall_view_atk2_sides:",
            "recall_view_atk3_type:", "recall_view_atk3_dice:", "recall_view_atk3_sides:",
            "recall_view_spell_flags2:", "recall_view_cdefense:",
        ):
            self.assertIn(rlabel, recall_defs_s)

    def test_no_hardcoded_external_paths_and_cli_requires_arg(self) -> None:
        forbidden_substrings = (
            "moria8" + "-upstream",
            "/" + "home/",
            "/" + "tmp",
            "$" + "HOME",
        )
        checked_files = (
            REPO_ROOT / "tools" / "extract_vms_creatures.py",
            self.spec_path,
            Path(__file__).resolve(),
        )
        for path in checked_files:
            content = path.read_text(encoding="utf-8")
            for needle in forbidden_substrings:
                self.assertNotIn(needle, content, f"Forbidden path token {needle!r} found in {path.name}")

        # CLI must fail cleanly when --vms-values is omitted or empty:
        stderr_buf = io.StringIO()
        with contextlib.redirect_stderr(stderr_buf):
            rc = evc.main(["--vms-values", ""])
        self.assertNotEqual(rc, 0)
        with self.assertRaises(SystemExit) as ctx, contextlib.redirect_stderr(stderr_buf):
            evc.main([])
        self.assertNotEqual(ctx.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
