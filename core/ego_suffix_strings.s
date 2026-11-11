#importonce
// ego_suffix_strings.s — the weapon ego suffixes (core/ego_items.s
// ego_suffix_lo/hi). Imported by ego_items.s, unless a port defines
// EGO_SUFFIX_STRINGS_EXTERNAL and imports this file where it has room (the
// C128: its $F000 runtime, beside the item descriptions that read them).
// Ego suffix strings (screen codes, null-terminated)
// These are in banked RAM at $F000+ so must be read while KERNAL is banked out.
.label ego_str_none = ego_str_slay_animal + 14   // the terminator of " (Slay Animal)": no suffix
ego_str_slay_animal:  .text " (Slay Animal)" ; .byte 0
.assert "ego_str_none is a terminator", ego_str_none - ego_str_slay_animal, 14
ego_str_slay_evil:    .text " (Slay Evil)" ; .byte 0
ego_str_slay_undead:  .text " (Slay Undead)" ; .byte 0
ego_str_flame:        .text " (Flame)" ; .byte 0
ego_str_frost:        .text " (Frost)" ; .byte 0
ego_str_defender:     .text " (Defender)" ; .byte 0
ego_str_slay_dragon:  .text " (Slay Dragon)" ; .byte 0
#if HAL_PLATFORM_EGO_HOLY_AVENGER_STRING_EXTERNAL
.label ego_str_holy_avenger = ego_str_holy_avenger_common
#else
ego_str_holy_avenger: .text " (Holy Avenger)" ; .byte 0
#endif
