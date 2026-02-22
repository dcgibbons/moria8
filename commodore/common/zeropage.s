// zeropage.s — Zero page variable declarations
// Uses BASIC's freed space $02–$8F (~140 bytes)
//
// Two zones:
//   SAFE      — Never touched by KERNAL routines. Use freely.
//   VOLATILE  — Clobbered by KERNAL I/O (LOAD/SAVE/OPEN/CLOSE/CLRCHN).
//               Must be caller-saved in data_loader.s and save.s before
//               any KERNAL file I/O call.
//
// References:
//   $00       — 6510 data direction register (DO NOT USE)
//   $01       — 6510 port register (memory banking — used by memory.s)
//   $02–$08   — Free (unused by BASIC or KERNAL on C64)
//   $09–$0A   — Free
//   $0B–$0C   — Free
//   $0D–$12   — Free
//   $13       — Free
//   $14–$15   — KERNAL: used by OPEN (VOLATILE)
//   $16–$21   — Free
//   $22–$25   — KERNAL: used by LOAD/SAVE (VOLATILE)
//   $26–$2A   — KERNAL: used by LOAD/SAVE/serial (VOLATILE)
//   $2B–$2C   — Start of BASIC (safe after BASIC disabled)
//   $2D–$8F   — BASIC working storage (safe after BASIC disabled)
//
// Layout strategy: put the hottest variables (pointers, counters used
// every frame) in the lowest addresses. Group by module.

// ============================================================
// SAFE ZONE — never touched by KERNAL
// ============================================================

// --- General purpose / temporaries ($02–$0C) ---
.label zp_temp0        = $02   // General temp byte
.label zp_temp1        = $03   // General temp byte
.label zp_temp2        = $04   // General temp byte
.label zp_temp3        = $05   // General temp byte
.label zp_ptr0         = $06   // General pointer (lo/hi)
.label zp_ptr0_hi      = $07
.label zp_ptr1         = $08   // General pointer (lo/hi)
.label zp_ptr1_hi      = $09
.label zp_ptr2         = $0a   // General pointer (lo/hi)
.label zp_ptr2_hi      = $0b
.label zp_temp4        = $0c   // General temp byte

// --- Config ($0d–$0e) ---
.label zp_machine_type = $0d   // $00 = C64, $80 = C128
.label zp_column_mode  = $0e   // $00 = 40-col, $80 = 80-col

// --- Screen ($0f–$12) ---
.label zp_screen_lo    = $0f   // Current screen write pointer (lo)
.label zp_screen_hi    = $10   // Current screen write pointer (hi)
.label zp_color_lo     = $11   // Current color RAM pointer (lo)
.label zp_color_hi     = $12   // Current color RAM pointer (hi)

// --- Cursor / UI ($13, $16–$19) ---
.label zp_cursor_col   = $13   // Current cursor column (0–39)
.label zp_cursor_row   = $16   // Current cursor row (0–24)
.label zp_text_color   = $17   // Current text output color
.label zp_msg_flags    = $18   // Message system flags (bit 0: -more- pending)
.label zp_ui_dirty     = $19   // UI dirty flags (bit 0: status bar, bit 1: map)

// --- RNG state ($1a–$1d) — 32-bit LFSR ---
.label zp_rng_0        = $1a   // RNG byte 0 (LSB)
.label zp_rng_1        = $1b   // RNG byte 1
.label zp_rng_2        = $1c   // RNG byte 2
.label zp_rng_3        = $1d   // RNG byte 3 (MSB)

// --- Math scratch ($1e–$21) ---
.label zp_math_a       = $1e   // Math operand A / result lo
.label zp_math_b       = $1f   // Math operand B / result hi
.label zp_math_tmp0    = $20   // Math temp
.label zp_math_tmp1    = $21   // Math temp

// ============================================================
// VOLATILE ZONE — clobbered by KERNAL I/O
// Caller-save before: OPEN, CLOSE, LOAD, SAVE, CHKIN, CHKOUT,
//                     CLRCHN, TALK, LISTEN, and serial bus ops.
// ============================================================

.label zp_vol_0        = $14   // KERNAL: OPEN scratch
.label zp_vol_1        = $15   // KERNAL: OPEN scratch
.label zp_vol_2        = $22   // KERNAL: LOAD/SAVE pointer lo
.label zp_vol_3        = $23   // KERNAL: LOAD/SAVE pointer hi
.label zp_vol_4        = $24   // KERNAL: LOAD/SAVE scratch
.label zp_vol_5        = $25   // KERNAL: LOAD/SAVE scratch
.label zp_vol_6        = $26   // KERNAL: serial scratch
.label zp_vol_7        = $27   // KERNAL: serial scratch
.label zp_vol_8        = $28   // KERNAL: serial scratch
.label zp_vol_9        = $29   // KERNAL: serial scratch
.label zp_vol_10       = $2a   // KERNAL: serial scratch

// ============================================================
// SAFE ZONE (continued) — BASIC working storage, free after
// BASIC ROM is banked out. $2B–$8F.
// ============================================================

// --- Player core stats ($2b–$3f) ---
.label zp_player_x     = $2b   // Player map X position (0–79)
.label zp_player_y     = $2c   // Player map Y position (0–47)
.label zp_player_hp_lo = $2d   // Current HP (lo)
.label zp_player_hp_hi = $2e   // Current HP (hi)
.label zp_player_mhp_lo = $2f  // Max HP (lo)
.label zp_player_mhp_hi = $30  // Max HP (hi)
.label zp_player_mp    = $31   // Current mana
.label zp_player_mmp   = $32   // Max mana
.label zp_player_lvl   = $33   // Player level (1–40)
.label zp_player_dlvl  = $34   // Current dungeon level (0 = town)
.label zp_player_ac    = $35   // Armor class
.label zp_player_str   = $36   // STR (current, after modifiers)
.label zp_player_int   = $37   // INT
.label zp_player_wis   = $38   // WIS
.label zp_player_dex   = $39   // DEX
.label zp_player_con   = $3a   // CON
.label zp_player_chr   = $3b   // CHR
.label zp_player_race  = $3c   // Race index (0–7)
.label zp_player_class = $3d   // Class index (0–5)
.label zp_player_food  = $3e   // Hunger counter (lo)
.label zp_player_food_hi = $3f // Hunger counter (hi)

// --- Turn / game state ($40–$4f) ---
.label zp_turn_lo      = $40   // Turn counter (lo)
.label zp_turn_hi      = $41   // Turn counter (hi)
.label zp_regen_counter = $42  // HP regen countdown (turns until next 1 HP heal)
.label zp_game_flags   = $43   // Global flags (bit 0: game over, bit 1: wizard mode)
.label zp_current_tier = $44   // Currently loaded creature/item tier pair
.label zp_speed_tick   = $45   // Speed counter tick for monster AI
.label zp_search_count = $46   // Accumulated search attempts this tile
.label zp_run_dir      = $47   // Running direction ($ff = not running)
.label zp_input_cmd    = $48   // Last parsed command code
.label zp_input_count  = $49   // Numeric prefix for repeat commands
.label zp_hunger_state = $4a   // 0=full, 1=hungry, 2=weak, 3=faint
.label zp_light_radius = $4b   // Current light radius (torch/lamp)
.label zp_depth_feeling = $4c  // Level feeling index
.label zp_mon_count    = $4d   // Active monster count (0–32)
.label zp_item_count   = $4e   // Floor item count (0–32)
.label zp_confuse_melee = $4f  // Monster Confusion scroll: 1 = next melee hit confuses

// --- Status effect timers ($50–$5f) ---
.label zp_eff_poison   = $50   // Poison timer (0 = not poisoned)
.label zp_eff_blind    = $51   // Blindness timer
.label zp_eff_confuse  = $52   // Confusion timer
.label zp_eff_paralyze = $53   // Paralysis timer
.label zp_eff_speed    = $54   // Haste/slow timer (signed: >0 haste, <0 slow)
.label zp_eff_protect  = $55   // Protection timer
.label zp_eff_invis    = $56   // Invisibility timer
.label zp_eff_infra    = $57   // Infravision timer
.label zp_eff_resist   = $58   // Resistance flags (bit-packed)
.label zp_eff_bless    = $59   // Bless timer
.label zp_eff_hero     = $5a   // Heroism timer
.label zp_eff_regen    = $5b   // Extra regeneration timer
.label zp_eff_free_act = $5c   // Free action flag
.label zp_eff_see_inv  = $5d   // See invisible flag
.label zp_eff_word_recall = $5e // Word of recall timer
.label zp_death_source = $5f   // Death cause ($00=alive, $01-FC=monster, $FD-FF=special)

// --- Viewport / map rendering ($60–$6b) ---
.label zp_view_x       = $60   // Viewport top-left X in map coords
.label zp_view_y       = $61   // Viewport top-left Y in map coords
.label zp_view_w       = $62   // Viewport width (38 for 40-col)
.label zp_view_h       = $63   // Viewport height (19)
.label zp_map_ptr_lo   = $64   // Map data pointer (lo)
.label zp_map_ptr_hi   = $65   // Map data pointer (hi)
.label zp_render_x     = $66   // Current render column
.label zp_render_y     = $67   // Current render row
.label zp_tile_tmp     = $68   // Temp for tile decoding
.label zp_dirty_lo     = $69   // Dirty tile list pointer (lo)
.label zp_dirty_hi     = $6a   // Dirty tile list pointer (hi)
.label zp_dirty_count  = $6b   // Number of dirty tiles

// --- Sound ($6c–$6f) ---
.label zp_snd_effect   = $6c   // Current sound effect ID ($ff = none)
.label zp_snd_timer    = $6d   // Sound duration counter
.label zp_snd_phase    = $6e   // Sound envelope phase
.label zp_snd_spare    = $6f   // Spare

// --- Monster AI scratch ($70–$7f) ---
.label zp_mon_idx      = $70   // Current monster index being processed
.label zp_mon_x        = $71   // Current monster X position
.label zp_mon_y        = $72   // Current monster Y position
.label zp_mon_type     = $73   // Current monster type index
.label zp_mon_hp_lo    = $74   // Current monster HP (lo)
.label zp_mon_hp_hi    = $75   // Current monster HP (hi)
.label zp_mon_flags    = $76   // Current monster status flags
.label zp_mon_speed    = $77   // Current monster speed counter
.label zp_mon_target_x = $78   // AI target X
.label zp_mon_target_y = $79   // AI target Y
.label zp_mon_dist     = $7a   // Distance to player
.label zp_mon_scratch0 = $7b   // AI scratch
.label zp_mon_scratch1 = $7c   // AI scratch
.label zp_mon_scratch2 = $7d   // AI scratch
.label zp_mon_scratch3 = $7e   // AI scratch
.label zp_mon_scratch4 = $7f   // AI scratch

// --- Combat / LOS scratch ($80–$87) ---
.label zp_combat_tohit = $80   // To-hit roll accumulator
.label zp_combat_dmg   = $81   // Damage accumulator
.label zp_combat_blows = $82   // Number of blows this round
.label zp_combat_atk   = $83   // Attack index (0–3)
.label zp_los_dx       = $84   // LOS delta X
.label zp_los_dy       = $85   // LOS delta Y
.label zp_los_err      = $86   // LOS Bresenham error
.label zp_los_step     = $87   // LOS step counter

// --- Inventory / item scratch ($88–$8f) ---
.label zp_inv_slot     = $88   // Current inventory slot being examined
.label zp_inv_type     = $89   // Item type of current slot
.label zp_inv_flags    = $8a   // Item flags of current slot
.label zp_inv_qty      = $8b   // Item quantity
.label zp_store_idx    = $8c   // Current store index (0–5)
.label zp_store_slot   = $8d   // Current store inventory slot
.label zp_pseudo_id_timer = $8e // Pseudo-ID turn countdown
.label zp_spare_8f     = $8f   // Spare

// ============================================================
// Compile-time validation
// ============================================================
.assert "ZP safe zone start", zp_temp0, $02
.assert "ZP last label", zp_spare_8f, $8f
.assert "ZP RNG is 4 contiguous bytes", zp_rng_3 - zp_rng_0, 3
.assert "ZP player pos contiguous", zp_player_y - zp_player_x, 1
