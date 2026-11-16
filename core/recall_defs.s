#importonce
// recall_defs.s — Recall constants and resident catalog recall view buffer.
.encoding "screencode_mixed"

#if HAL_PLATFORM_MONSTER_CATALOG
.const RECALL_COUNT     = 279
.const RECALL_DATA_SIZE = RECALL_COUNT * 4

// Resident recall view snapshot populated by catalog_recall_match_and_fill
// so ui_recall_display needs no cross-bank catalog/recall calls.
recall_view_display:      .byte 0
recall_view_color:        .byte 0
recall_view_mflags:       .byte 0
recall_view_level:        .byte 0
recall_view_hd_num:       .byte 0
recall_view_hd_sides:     .byte 0
recall_view_ac:           .byte 0
recall_view_atk0_type:    .byte 0
recall_view_atk0_dice:    .byte 0
recall_view_atk0_sides:   .byte 0
recall_view_atk1_type:    .byte 0
recall_view_atk1_dice:    .byte 0
recall_view_atk1_sides:   .byte 0
recall_view_spell_chance: .byte 0
recall_view_spell_flags:  .byte 0

// Phase 5 extended recall view bytes populated by catalog_recall_match_and_fill
// from cat_ext_record[0..7] (in exact EXT_FIELD_LABELS order).
recall_view_atk2_type:    .byte 0
recall_view_atk2_dice:    .byte 0
recall_view_atk2_sides:   .byte 0
recall_view_atk3_type:    .byte 0
recall_view_atk3_dice:    .byte 0
recall_view_atk3_sides:   .byte 0
recall_view_spell_flags2: .byte 0
recall_view_cdefense:     .byte 0

recall_view_kills:        .byte 0
recall_view_deaths:       .byte 0
recall_view_attacks:      .byte 0
recall_view_spells:       .byte 0
.assert "Recall view record fields are contiguous", recall_view_spell_flags - recall_view_display, 14
.assert "Extended recall view record fields are contiguous", recall_view_cdefense - recall_view_atk2_type, 7
.assert "rcl_atk_off slot 2 matches recall_view_atk2", recall_view_atk2_type - recall_view_atk0_type, 8
.assert "rcl_atk_off slot 3 matches recall_view_atk3", recall_view_atk3_type - recall_view_atk0_type, 11
#else
.const RECALL_DATA_SIZE = MAX_CREATURES * 4
#endif

.const RECALL_FIELD_KILLS   = 0
.const RECALL_FIELD_DEATHS  = 1
.const RECALL_FIELD_ATTACKS = 2
.const RECALL_FIELD_SPELLS  = 3

// Pre-shifted 15-bit 3-letter uppercase pack: bits 15..11, 10..6, 5..1.
.function rclPack3(s) {
    .return (((s.charAt(0) & $1f) << 11) | ((s.charAt(1) & $1f) << 6) | ((s.charAt(2) & $1f) << 1))
}

// On 80-column targets (C128, Apple IIe, BBC Master, CX16), all ui_recall
// read-only tables live inside ui_recall.s's overlay (0 B in Default).
// On 40-column targets (C64, Plus/4, Atari 8-bit), DeathOverlay is capped at
// $EF00 (C64 REU Bank 0) / $EE00 (Atari 130XE Slot 2) while Default has
// 1.5–2.1 KB free, so the read-only string/tag tables park here on 40-col.
#if HAL_LAYOUT_WIZARD_40COL_MENU
rcl_lbls:
    .byte 2  ; .text "LV "
    .byte 10 ; .text "AC "
    .byte 18 ; .text "HP "
    .byte 2  ; .text "Atk: "
    .byte 2  ; .text "Spl: "
    .byte 2  ; .text "Hurt: "
    .byte 2  ; .text "Traits: "
    .byte 2  ; .text "K: "
    .byte 16 ; .text "D: "

rcl_strs:
rcl_s_title: .text "Recall" ; .byte 0
rcl_s_none:  .text "None" ; .byte 0
rcl_s_yes:   .text "Yes" ; .byte 0
rcl_t_invis: .text "INVIS" ; .byte 0
rcl_t_phase: .text "PHASE" ; .byte 0
rcl_t_noslp: .text "NO-SLP" ; .byte 0
rcl_t_und:   .text "UNDEAD" ; .byte 0
rcl_t_evil:  .text "EVIL" ; .byte 0
.assert "Recall strings fit 1-byte offset", * - rcl_strs <= 255, true

rcl_tag_lo:
    .byte <rclPack3("HIT"), <rclPack3("STR"), <rclPack3("CNF"), <rclPack3("FER")
    .byte <rclPack3("FIR"), <rclPack3("ACD"), <rclPack3("CLD"), <rclPack3("LTG")
    .byte <rclPack3("COR"), <rclPack3("BLD"), <rclPack3("PAR"), <rclPack3("GLD")
    .byte <rclPack3("ITM"), <rclPack3("PSN"), <rclPack3("DEX"), <rclPack3("CON")
    .byte <rclPack3("INT"), <rclPack3("WIS"), <rclPack3("EXP"), <rclPack3("SHR")
    .byte <rclPack3("DIS"), <rclPack3("FOD"), <rclPack3("LIT"), <rclPack3("CHG")
    .byte <rclPack3("STN")
rcl_tag_hi:
    .byte >rclPack3("HIT"), >rclPack3("STR"), >rclPack3("CNF"), >rclPack3("FER")
    .byte >rclPack3("FIR"), >rclPack3("ACD"), >rclPack3("CLD"), >rclPack3("LTG")
    .byte >rclPack3("COR"), >rclPack3("BLD"), >rclPack3("PAR"), >rclPack3("GLD")
    .byte >rclPack3("ITM"), >rclPack3("PSN"), >rclPack3("DEX"), >rclPack3("CON")
    .byte >rclPack3("INT"), >rclPack3("WIS"), >rclPack3("EXP"), >rclPack3("SHR")
    .byte >rclPack3("DIS"), >rclPack3("FOD"), >rclPack3("LIT"), >rclPack3("CHG")
    .byte >rclPack3("STN")
#endif
