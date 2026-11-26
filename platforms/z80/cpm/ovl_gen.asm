; ovl_gen.asm — Moria8 CP/M Town & Dungeon Generation Overlay (OVL_GEN, DAT slot 3).
;
; Fixed jump vectors at OVL_WINDOW_BASE (0x5600):
;   +0: JP ovl_gen_town     -> builds 66x22 Town inside 198x66 MAP_BASE (0x9D00)
;   +3: JP ovl_gen_dungeon  -> builds 12-stage 198x66 dungeon (DGN-008..DGN-019)
;
; Mandatory OVL_GEN Exit Contract (docs/CPM_MEMORY_CONTRACT.md §2.3):
;   - Temporary scan scratch reuses GEN_SCAN_SCRATCH_BASE (0x8E00, 1,920 B =
;     cpm_char_shadow) inside ovl_gen_dungeon without calling screen_flush.
;   - On both ovl_gen_town and ovl_gen_dungeon exit, calls screen_hard_clear
;     (ESC[0m + ESC[2J + clean shadows with dirty = 0) and sets
;     hal_layout_visibility_force_redraw = 1.
;
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "main_exp.inc"

    ORG  OVL_WINDOW_BASE        ; 0x5600

ovl_start:
    JP   ovl_gen_town
    JP   ovl_gen_dungeon

; ===========================================================================
; Constants & Scratch Layout (GEN_SCAN_SCRATCH_BASE = 0x8E00..0x957F)
; ===========================================================================
OVL_GEN_STORE_W         EQU 10
OVL_GEN_STORE_H         EQU 5

DG_DUN_PANEL_W          EQU 66
DG_DUN_PANEL_H          EQU 22
DG_SLOT_X_STEP          EQU (DG_DUN_PANEL_W / 2)    ; 33
DG_SLOT_Y_STEP          EQU (DG_DUN_PANEL_H / 2)    ; 11
DG_SLOT_X_BASE          EQU (DG_DUN_PANEL_W / 4)    ; 16
DG_SLOT_Y_BASE          EQU (DG_DUN_PANEL_H / 4)    ; 5
DG_SLOT_COLS            EQU 6                       ; 2 * (198 / 66)
DG_SLOT_ROWS            EQU 6                       ; 2 * (66 / 22)
DG_SLOT_COUNT           EQU (DG_SLOT_COLS * DG_SLOT_ROWS) ; 36
DG_SLOT_STRIDE          EQU (DG_SLOT_COLS + 1)      ; 7
DG_DUN_ROOM_ROLLS       EQU 32
DG_STREAMER_DENSITY     EQU 5
DG_STREAMER_MAX_STEPS   EQU 180
DG_DUN_TUNNELING        EQU 15
DG_DUN_DIR_CHANGE       EQU 70
DG_DUN_RANDOM_DIR       EQU 36
DG_DUN_ROOM_DOORS       EQU 24
DG_DUN_TUNNEL_DOORS     EQU 15
DG_TUNNEL_MAX_STEPS     EQU 2000
DG_STAIR_WALL_TRIES     EQU 20
DG_MAX_DOOR_SCAN        EQU 128

DGEN_CORR               EQU FLAG_OCCUPIED                   ; 0x01
DGEN_TUNNEL             EQU FLAG_VISITED                    ; 0x04
DGEN_JUNCTION           EQU (FLAG_OCCUPIED | FLAG_HAS_ITEM) ; 0x03

DG_ROW_LO               EQU GEN_SCAN_SCRATCH_BASE           ; 0x8E00..0x8E41 (66 B)
DG_ROW_HI               EQU (GEN_SCAN_SCRATCH_BASE + 0x0100); 0x8F00..0x8F41 (66 B)
DG_SLOT_SELECTED        EQU (GEN_SCAN_SCRATCH_BASE + 0x0200); 0x9000..0x9023 (36 B)
DG_DOOR_SCAN_X          EQU (GEN_SCAN_SCRATCH_BASE + 0x0240); 0x9040..0x90BF (128 B)
DG_DOOR_SCAN_Y          EQU (GEN_SCAN_SCRATCH_BASE + 0x02C0); 0x90C0..0x913F (128 B)
DG_DOOR_IDX             EQU (GEN_SCAN_SCRATCH_BASE + 0x0340); 0x9140..0x91BF (128 B)
DG_SHR3_TBL             EQU (GEN_SCAN_SCRATCH_BASE + 0x0400); 0x9200..0x92FF (256 B)
DG_SHL5_TBL             EQU (GEN_SCAN_SCRATCH_BASE + 0x0500); 0x9300..0x93FF (256 B)
DG_RNG_MASK             EQU (GEN_SCAN_SCRATCH_BASE + 0x0600); 0x9400..0x94FF (256 B)

    ASSERT (DG_ROW_LO & 0xFF) == 0
    ASSERT (DG_ROW_HI & 0xFF) == 0
    ASSERT HIGH(DG_ROW_HI) == HIGH(DG_ROW_LO) + 1
    ASSERT (DG_SHR3_TBL & 0xFF) == 0
    ASSERT (DG_SHL5_TBL & 0xFF) == 0
    ASSERT (DG_RNG_MASK & 0xFF) == 0
    ASSERT (DG_RNG_MASK + 256) <= (GEN_SCAN_SCRATCH_BASE + GEN_SCAN_SCRATCH_SIZE)

; ===========================================================================
; ovl_gen_town — Build 66x22 Moria8 Town inside 198x66 MAP_BASE.
; Output: CF = 0
; Preserves: IX, IY
; ===========================================================================
ovl_gen_town:
    PUSH IX
    PUSH IY

    XOR  A
    LD   (trap_count), A
    LD   (door_state_count), A
    LD   (room_count), A
    LD   (active_dungeon_count), A
    LD   (zp_mon_count), A
    LD   (abi_mon_count), A
    LD   (zp_item_count), A
    LD   (abi_item_count), A
    LD   (chest_pending_summons), A
    LD   (stairs_up_x), A
    LD   (stairs_up_y), A
    LD   (stairs_dn2_x), A
    LD   (stairs_dn2_y), A
    LD   (level_entry_dir), A
    LD   (vis_room_revealed), A
    LD   A, 0xFF
    LD   (vis_cached_room_idx), A

    LD   HL, fi_item_id
    LD   DE, fi_item_id + 1
    LD   BC, MAX_FLOOR_ITEMS - 1
    LD   (HL), FI_EMPTY
    LDIR

    LD   HL, monster_table
    LD   DE, monster_table + 1
    LD   BC, (MAX_MONSTERS * MONSTER_ENTRY_SIZE) - 1
    LD   (HL), EMPTY_SLOT
    LDIR

    LD   HL, glyph_active
    LD   DE, glyph_active + 1
    LD   BC, MAX_GLYPHS - 1
    LD   (HL), 0
    LDIR

    ; Step 1: Fill entire 198x66 backing map with unseen/unlit wall rock
    LD   A, TILE_WALL_H
    CALL map_clear

    ; Step 2: Carve lit & visited 66x22 Town floor rectangle (rows 0..21, cols 0..65)
    LD   B, 0
.floor_row:
    LD   C, 0
.floor_col:
    LD   A, TILE_FLOOR | TOWN_FLAGS
    CALL map_set_tile
    INC  C
    LD   A, C
    CP   TOWN_MAP_COLS
    JR   C, .floor_col
    INC  B
    LD   A, B
    CP   TOWN_MAP_ROWS
    JR   C, .floor_row

    ; Step 3: Draw Town outer boundary walls (corners + H/V walls)
    LD   B, 0
    LD   C, 0
    LD   A, TILE_CORNER_TL | TOWN_FLAGS
    CALL map_set_tile
    LD   C, TOWN_MAP_COLS - 1
    LD   A, TILE_CORNER_TR | TOWN_FLAGS
    CALL map_set_tile
    LD   C, 1
.top_wall:
    LD   A, TILE_WALL_H | TOWN_FLAGS
    CALL map_set_tile
    INC  C
    LD   A, C
    CP   TOWN_MAP_COLS - 1
    JR   C, .top_wall

    LD   B, TOWN_MAP_ROWS - 1
    LD   C, 0
    LD   A, TILE_CORNER_BL | TOWN_FLAGS
    CALL map_set_tile
    LD   C, TOWN_MAP_COLS - 1
    LD   A, TILE_CORNER_BR | TOWN_FLAGS
    CALL map_set_tile
    LD   C, 1
.bot_wall:
    LD   A, TILE_WALL_H | TOWN_FLAGS
    CALL map_set_tile
    INC  C
    LD   A, C
    CP   TOWN_MAP_COLS - 1
    JR   C, .bot_wall

    LD   B, 1
.side_walls:
    LD   C, 0
    LD   A, TILE_WALL_V | TOWN_FLAGS
    CALL map_set_tile
    LD   C, TOWN_MAP_COLS - 1
    LD   A, TILE_WALL_V | TOWN_FLAGS
    CALL map_set_tile
    INC  B
    LD   A, B
    CP   TOWN_MAP_ROWS - 1
    JR   C, .side_walls

    ; Step 4: Place 8 store buildings (stores 0..6 + Player Home 7)
    LD   D, 0
.store_loop:
    CALL ovl_gen_draw_store
    INC  D
    LD   A, D
    CP   STORE_COUNT
    JR   C, .store_loop

    ; Step 5: Place down staircase '>' and record coordinates
    LD   B, TOWN_STAIRS_Y
    LD   C, TOWN_STAIRS_X
    LD   A, TILE_STAIRS_DN | TOWN_FLAGS
    CALL map_set_tile
    LD   A, TOWN_STAIRS_X
    LD   (stairs_dn_x), A
    LD   A, TOWN_STAIRS_Y
    LD   (stairs_dn_y), A

    ; Step 6: Place player inside Town plaza (31, 18) and sync ABI
    LD   A, TOWN_START_X
    LD   (player_data + PL_MAP_X), A
    LD   (abi_player_x), A
    LD   A, TOWN_START_Y
    LD   (player_data + PL_MAP_Y), A
    LD   (abi_player_y), A
    XOR  A
    LD   (player_data + PL_DLEVEL), A
    LD   (abi_player_dlvl), A
    CALL player_sync_to_abi
    CALL tramp_modal_populate_town

    ; Step 7: Mandatory OVL_GEN exit contract (ESC[0m + ESC[2J + clean shadows)
    JP   ovl_gen_finish_exit

; ---------------------------------------------------------------------------
; ovl_gen_draw_store — Draw store building D (0..7) in Town.
; Preserves: D
; ---------------------------------------------------------------------------
ovl_gen_draw_store:
    PUSH DE
    LD   E, D
    LD   D, 0
    LD   HL, ovl_gen_store_pos_x
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_gen_x0), A
    ADD  A, OVL_GEN_STORE_W - 1
    LD   (ovl_gen_x1), A

    LD   HL, ovl_gen_store_pos_y
    ADD  HL, DE
    LD   A, (HL)
    LD   (ovl_gen_y0), A
    ADD  A, OVL_GEN_STORE_H - 1
    LD   (ovl_gen_y1), A

    ; Top wall
    LD   A, (ovl_gen_y0)
    LD   B, A
    LD   A, (ovl_gen_x0)
    LD   C, A
    LD   A, TILE_CORNER_TL | TOWN_FLAGS
    CALL map_set_tile
    LD   A, (ovl_gen_x1)
    LD   C, A
    LD   A, TILE_CORNER_TR | TOWN_FLAGS
    CALL map_set_tile
    LD   A, (ovl_gen_x0)
    INC  A
    LD   C, A
.st_top:
    LD   A, TILE_WALL_H | TOWN_FLAGS
    CALL map_set_tile
    INC  C
    LD   A, (ovl_gen_x1)
    CP   C
    JR   NZ, .st_top

    ; Bottom wall
    LD   A, (ovl_gen_y1)
    LD   B, A
    LD   A, (ovl_gen_x0)
    LD   C, A
    LD   A, TILE_CORNER_BL | TOWN_FLAGS
    CALL map_set_tile
    LD   A, (ovl_gen_x1)
    LD   C, A
    LD   A, TILE_CORNER_BR | TOWN_FLAGS
    CALL map_set_tile
    LD   A, (ovl_gen_x0)
    INC  A
    LD   C, A
.st_bot:
    LD   A, TILE_WALL_H | TOWN_FLAGS
    CALL map_set_tile
    INC  C
    LD   A, (ovl_gen_x1)
    CP   C
    JR   NZ, .st_bot

    ; Side walls and opaque interior (y0+1 .. y1-1)
    LD   A, (ovl_gen_y0)
    INC  A
    LD   B, A
.st_side_row:
    LD   A, (ovl_gen_x0)
    LD   C, A
    LD   A, TILE_WALL_V | TOWN_FLAGS
    CALL map_set_tile
    LD   A, (ovl_gen_x1)
    LD   C, A
    LD   A, TILE_WALL_V | TOWN_FLAGS
    CALL map_set_tile

    LD   A, (ovl_gen_x0)
    INC  A
    LD   C, A
.st_interior:
    LD   A, TILE_WALL_H
    CALL map_set_tile
    INC  C
    LD   A, (ovl_gen_x1)
    CP   C
    JR   NZ, .st_interior

    INC  B
    LD   A, (ovl_gen_y1)
    CP   B
    JR   NZ, .st_side_row

    ; Store/Home door on south wall
    POP  DE
    PUSH DE
    LD   E, D
    LD   D, 0
    LD   HL, ovl_gen_store_door_y
    ADD  HL, DE
    LD   B, (HL)
    LD   HL, ovl_gen_store_door_x
    ADD  HL, DE
    LD   C, (HL)
    LD   A, TILE_DOOR_OPEN | TOWN_FLAGS
    CALL map_set_tile

    POP  DE
    RET

; ===========================================================================
; ovl_gen_dungeon — Vector +3: 12-stage 198x66 Dungeon Generator.
; Output: CF = 0
; Preserves: IX, IY
; ===========================================================================
ovl_gen_dungeon:
    PUSH IX
    PUSH IY

    ; Keep abi_player_dlvl and player_data + PL_DLEVEL consistent
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .dlvl_to_pl
    LD   A, (player_data + PL_DLEVEL)
    LD   (abi_player_dlvl), A
    JR   .dlvl_ok
.dlvl_to_pl:
    LD   (player_data + PL_DLEVEL), A
.dlvl_ok:

    ; Display centered "GENERATING..." BEFORE GEN_SCAN_SCRATCH reuses cpm_char_shadow
    CALL screen_clear
    LD   B, 12
    LD   C, 33
    LD   E, COL_WHITE
    LD   HL, ovl_gen_str_busy
    CALL screen_put_str
    CALL screen_flush

    ; Stage 1: Reset dungeon/level counters, clear monster/item/glyph state,
    ;          initialize GEN_SCAN_SCRATCH row pointers, and blank_cave (0x00)
    XOR  A
    LD   (trap_count), A
    LD   (door_state_count), A
    LD   (room_count), A
    LD   (active_dungeon_count), A
    LD   (zp_mon_count), A
    LD   (zp_item_count), A
    LD   (abi_mon_count), A
    LD   (abi_item_count), A
    LD   (chest_pending_summons), A
    LD   (vis_room_revealed), A

    LD   HL, glyph_active
    LD   B, MAX_GLYPHS
.clr_glyphs:
    LD   (HL), A
    INC  HL
    DJNZ .clr_glyphs

    LD   HL, fi_item_id
    LD   DE, fi_item_id + 1
    LD   BC, MAX_FLOOR_ITEMS - 1
    LD   (HL), FI_EMPTY
    LDIR

    LD   HL, monster_table
    LD   DE, monster_table + 1
    LD   BC, (MAX_MONSTERS * MONSTER_ENTRY_SIZE) - 1
    LD   (HL), 0xFF
    LDIR

    CALL dg_init_row_ptrs
    ; Ensure abi_rng_seed is non-zero once (Xorshift32(13,17,5) never absorbs to 0 from non-zero)
    LD   HL, abi_rng_seed
    LD   A, (HL)
    INC  HL
    OR   (HL)
    INC  HL
    OR   (HL)
    INC  HL
    OR   (HL)
    JR   NZ, .seed_nz
    LD   HL, 0x3C19
    LD   (abi_rng_seed), HL
    LD   HL, 0xA55A
    LD   (abi_rng_seed + 2), HL
.seed_nz:
    LD   A, TILE_FLOOR          ; blank_cave null fill (0x00)
    CALL map_clear

    ; Stage 2..12 exact pipeline order (DUNGEON_GENERATION_CONTRACT.md)
    CALL dg_place_rooms         ; Stage 2
    CALL dg_shuffle_rooms       ; Stage 3
    CALL dg_connect_rooms       ; Stage 4
    CALL dg_fill_cave_granite   ; Stage 5
    CALL dg_place_streamers     ; Stage 6
    CALL dg_place_junction_doors; Stage 7
    CALL dg_assign_special_room ; Stage 8a
    CALL dg_vault_seal_entrance ; Stage 8b
    CALL dg_place_stairs_dungeon; Stage 9
    CALL dg_place_traps         ; Stage 10a
    CALL dg_place_secrets       ; Stage 10b
    CALL dg_darken_rooms        ; Stage 11
    CALL dg_position_player_dungeon ; Stage 12
    CALL tramp_modal_populate_dungeon
    CALL tramp_items_eff_spawn_level

ovl_gen_finish_exit:
    CALL screen_hard_clear
    LD   A, 1
    LD   (hal_layout_visibility_force_redraw), A
    LD   A, UI_DIRTY_FORCE | UI_DIRTY_STATUS | UI_DIRTY_MAP
    LD   (zp_ui_dirty), A

    OR   A                      ; CF = 0
    POP  IY
    POP  IX
    RET

; ===========================================================================
; GEN_SCAN_SCRATCH Row-Pointer & Map Access Helpers
; ===========================================================================

; Populate DG_ROW_LO/HI plus fast shift & mask tables in GEN_SCAN_SCRATCH_BASE
dg_init_row_ptrs:
    LD   HL, MAP_BASE
    LD   DE, MAP_COLS
    LD   BC, DG_ROW_LO          ; B = 0x8E, C = 0
.lp:
    LD   A, L
    LD   (BC), A
    INC  B
    LD   A, H
    LD   (BC), A
    DEC  B
    ADD  HL, DE
    INC  C
    LD   A, C
    CP   MAP_ROWS
    JR   C, .lp

    ; Build 256-byte DG_SHR3_TBL (x >> 3) and DG_SHL5_TBL ((x << 5) & 0xFF)
    LD   BC, DG_SHR3_TBL        ; B = HIGH(DG_SHR3_TBL), C = 0..255
.tbl_shift:
    LD   A, C
    RRCA
    RRCA
    RRCA
    LD   E, A
    AND  0x1F
    LD   (BC), A                ; DG_SHR3_TBL[C] = C >> 3
    INC  B
    LD   A, E
    AND  0xE0
    LD   (BC), A                ; DG_SHL5_TBL[C] = (C << 5) & 0xFF
    DEC  B
    INC  C
    JR   NZ, .tbl_shift

    ; Build 256-byte DG_RNG_MASK[n] = smallest (2^k - 1) >= max(n - 1, 0)
    LD   HL, DG_RNG_MASK
    XOR  A
    LD   (HL), A                ; n = 0 -> 0
    INC  L
    LD   (HL), A                ; n = 1 -> 0
    INC  L
    LD   (HL), 1                ; n = 2 -> 1
    INC  L
    LD   B, 2
    LD   A, 3
    CALL .fill_mask             ; 3..4 -> 3
    LD   B, 4
    LD   A, 7
    CALL .fill_mask             ; 5..8 -> 7
    LD   B, 8
    LD   A, 15
    CALL .fill_mask             ; 9..16 -> 15
    LD   B, 16
    LD   A, 31
    CALL .fill_mask             ; 17..32 -> 31
    LD   B, 32
    LD   A, 63
    CALL .fill_mask             ; 33..64 -> 63
    LD   B, 64
    LD   A, 127
    CALL .fill_mask             ; 65..128 -> 127
    LD   B, 127
    LD   A, 255
.fill_mask:
    LD   (HL), A
    INC  L
    DJNZ .fill_mask
    RET

; Input: B = row (0..65). Output: HL = MAP_BASE + B * 198.
; Preserves: BC, DE, IX, IY. Clobbers: AF, HL.
dg_row_ptr_b:
    LD   H, HIGH(DG_ROW_LO)
    LD   L, B
    LD   A, (HL)
    INC  H
    LD   H, (HL)
    LD   L, A
    RET

; Input: B = row (0..65), C = col (0..197).
; Output: CF = 0 & HL = &map[B][C]; CF = 1 if out of bounds.
; Preserves: BC, DE, IX, IY. Clobbers: AF, HL.
dg_cell_ptr_bc:
    LD   A, B
    CP   MAP_ROWS
    JR   NC, .oob
    LD   A, C
    CP   MAP_COLS
    JR   NC, .oob
    LD   H, HIGH(DG_ROW_LO)
    LD   L, B
    LD   A, (HL)
    INC  H
    LD   H, (HL)
    ADD  A, C
    LD   L, A
    JR   NC, .ok
    INC  H
.ok:
    OR   A                      ; CF = 0
    RET
.oob:
    SCF
    RET

; Input: B = row, C = col.
; Output: CF = 0 & A = tile & HL = cell ptr; CF = 1 & A = 0 if OOB.
; Preserves: BC, DE, IX, IY.
dg_read_bc:
    CALL dg_cell_ptr_bc
    JR   C, .oob
    LD   A, (HL)
    OR   A
    RET
.oob:
    XOR  A
    SCF
    RET

; Input: B = row, C = col, A = tile. Preserves: AF, BC, DE, HL, IX, IY.
dg_write_bc:
    PUSH HL
    PUSH AF
    CALL dg_cell_ptr_bc
    JR   C, .oob
    POP  AF
    LD   (HL), A
    POP  HL
    RET
.oob:
    POP  AF
    POP  HL
    RET

; Helper: HL = HL + A (8-bit offset), A = (HL).
; Preserves: BC, DE, IX, IY. Clobbers: AF, HL.
dg_idx_read:
    ADD  A, L
    LD   L, A
    ADC  A, H
    SUB  L
    LD   H, A
    LD   A, (HL)
    RET

; ===========================================================================
; Fast bit-exact Xorshift32 (13, 17, 5) range RNG over abi_rng_seed.
; Input:  A = N (0..255)
; Output: A = uniform integer in [0, N-1] (0 if N <= 1)
; Preserves: BC, DE, HL, IX, IY
; ===========================================================================
dg_rng_range:
    CP   2
    JR   NC, .ge2
    XOR  A
    RET
.ge2:
    PUSH BC
    PUSH DE
    PUSH HL
    LD   H, HIGH(DG_RNG_MASK)
    LD   L, A
    LD   H, (HL)                ; H = bitmask
    LD   L, A                   ; L = N
    PUSH HL

    LD   HL, (abi_rng_seed)
    LD   C, L                   ; C = s0
    LD   B, H                   ; B = s1
    LD   HL, (abi_rng_seed + 2)
    LD   E, L                   ; E = s2
    LD   D, H                   ; D = s3

.step1:
    ; x ^= x << 13 (top-down: s3, s2, s1)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, E
    OR   (HL)
    XOR  D
    LD   D, A                   ; s3'

    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, C
    OR   (HL)
    XOR  E
    LD   E, A                   ; s2'

    LD   H, HIGH(DG_SHL5_TBL)
    LD   A, (HL)
    XOR  B
    LD   B, A                   ; s1'

    ; x ^= x >> 17 (s0 ^= (s2'>>1)|(s3'<<7), s1 ^= s3'>>1)
    LD   A, D
    SRL  A
    LD   H, A
    LD   A, E
    RRA
    XOR  C
    LD   C, A                   ; s0''
    LD   A, H
    XOR  B
    LD   B, A                   ; s1''

    ; x ^= x << 5 (top-down: s3, s2, s1, s0)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, D
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, E
    OR   (HL)
    XOR  D
    LD   D, A                   ; s3'''

    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, E
    OR   (HL)
    XOR  E
    LD   E, A                   ; s2'''

    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, C
    OR   (HL)
    XOR  B
    LD   B, A                   ; s1'''

    LD   H, HIGH(DG_SHL5_TBL)
    LD   A, (HL)
    XOR  C
    LD   C, A                   ; s0'''

    POP  HL                     ; H = mask, L = N
    LD   A, D
    AND  H
    CP   L
    JR   C, .accept
    PUSH HL
    JR   .step1

.accept:
    LD   L, C
    LD   H, B
    LD   (abi_rng_seed), HL
    LD   L, E
    LD   H, D
    LD   (abi_rng_seed + 2), HL
    POP  HL
    POP  DE
    POP  BC
    RET

; Fast bit-exact Xorshift32 (13, 17, 5) raw u8 draw -> A. Preserves BC, DE, HL, IX, IY.
dg_rng_next_u8:
    PUSH BC
    PUSH DE
    PUSH HL
    LD   HL, (abi_rng_seed)
    LD   C, L
    LD   B, H
    LD   HL, (abi_rng_seed + 2)
    LD   E, L
    LD   D, H

    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, E
    OR   (HL)
    XOR  D
    LD   D, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, C
    OR   (HL)
    XOR  E
    LD   E, A
    LD   H, HIGH(DG_SHL5_TBL)
    LD   A, (HL)
    XOR  B
    LD   B, A

    LD   A, D
    SRL  A
    LD   H, A
    LD   A, E
    RRA
    XOR  C
    LD   C, A
    LD   A, H
    XOR  B
    LD   B, A

    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, D
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, E
    OR   (HL)
    XOR  D
    LD   D, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, E
    OR   (HL)
    XOR  E
    LD   E, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, C
    OR   (HL)
    XOR  B
    LD   B, A
    LD   H, HIGH(DG_SHL5_TBL)
    LD   A, (HL)
    XOR  C
    LD   C, A

    LD   L, C
    LD   H, B
    LD   (abi_rng_seed), HL
    LD   L, E
    LD   H, D
    LD   (abi_rng_seed + 2), HL
    LD   A, D
    POP  HL
    POP  DE
    POP  BC
    RET

; Fast pair draw of rng_range(5) -> H = 1st [0..4], A = 2nd [0..4].
; Preserves BC, DE, IX, IY. Loads and stores abi_rng_seed ONCE.
dg_rng5_pair:
    PUSH BC
    PUSH DE
    LD   HL, (abi_rng_seed)
    LD   C, L
    LD   B, H
    LD   HL, (abi_rng_seed + 2)
    LD   E, L
    LD   D, H

.r1:
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, E
    OR   (HL)
    XOR  D
    LD   D, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, C
    OR   (HL)
    XOR  E
    LD   E, A
    LD   H, HIGH(DG_SHL5_TBL)
    LD   A, (HL)
    XOR  B
    LD   B, A

    LD   A, D
    SRL  A
    LD   H, A
    LD   A, E
    RRA
    XOR  C
    LD   C, A
    LD   A, H
    XOR  B
    LD   B, A

    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, D
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, E
    OR   (HL)
    XOR  D
    LD   D, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, E
    OR   (HL)
    XOR  E
    LD   E, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, C
    OR   (HL)
    XOR  B
    LD   B, A
    LD   H, HIGH(DG_SHL5_TBL)
    LD   A, (HL)
    XOR  C
    LD   C, A

    LD   A, D
    AND  7
    CP   5
    JR   NC, .r1
    PUSH AF                     ; save 1st draw in high byte on stack

.r2:
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, E
    OR   (HL)
    XOR  D
    LD   D, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, C
    OR   (HL)
    XOR  E
    LD   E, A
    LD   H, HIGH(DG_SHL5_TBL)
    LD   A, (HL)
    XOR  B
    LD   B, A

    LD   A, D
    SRL  A
    LD   H, A
    LD   A, E
    RRA
    XOR  C
    LD   C, A
    LD   A, H
    XOR  B
    LD   B, A

    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, D
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, E
    OR   (HL)
    XOR  D
    LD   D, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHL5_TBL)
    LD   L, E
    OR   (HL)
    XOR  E
    LD   E, A
    LD   L, B
    LD   A, (HL)
    LD   H, HIGH(DG_SHR3_TBL)
    LD   L, C
    OR   (HL)
    XOR  B
    LD   B, A
    LD   H, HIGH(DG_SHL5_TBL)
    LD   A, (HL)
    XOR  C
    LD   C, A

    LD   A, D
    AND  7
    CP   5
    JR   NC, .r2

    LD   L, C
    LD   H, B
    LD   (abi_rng_seed), HL
    LD   L, E
    LD   H, D
    LD   (abi_rng_seed + 2), HL
    POP  HL                     ; H = 1st draw, A = 2nd draw!
    POP  DE
    POP  BC
    RET

; ===========================================================================
; Stage 2: dg_place_rooms — 32 slot rolls on 6x6 grid (MAX_ROOMS = 21)
; ===========================================================================
dg_place_rooms:
    XOR  A
    LD   (room_count), A
    LD   (dg_slot_count), A

    LD   HL, DG_SLOT_SELECTED
    LD   DE, DG_SLOT_SELECTED + 1
    LD   BC, DG_SLOT_COUNT - 1
    LD   (HL), A
    LDIR

    LD   B, DG_DUN_ROOM_ROLLS   ; 32 rolls
.sel_loop:
    LD   A, DG_SLOT_COUNT
    CALL dg_rng_range              ; A = [0, 35]
    LD   HL, DG_SLOT_SELECTED
    CALL dg_idx_read
    OR   A
    JR   NZ, .sel_next
    LD   A, (dg_slot_count)
    CP   MAX_ROOMS
    JR   NC, .sel_next
    LD   (HL), 1
    INC  A
    LD   (dg_slot_count), A
.sel_next:
    DJNZ .sel_loop

    XOR  A
    LD   (dg_idx), A
    LD   (dg_slot_scan), A
.room_loop:
    LD   A, (dg_slot_scan)
    LD   HL, DG_SLOT_SELECTED
    CALL dg_idx_read
    OR   A
    JP   Z, .skip_slot

    ; Load slot center (cx1, cy1)
    LD   A, (dg_slot_scan)
    LD   HL, dg_slot_center_x
    CALL dg_idx_read
    LD   (dg_cx1), A
    LD   A, (dg_slot_scan)
    LD   HL, dg_slot_center_y
    CALL dg_idx_read
    LD   (dg_cy1), A

    ; room_lit[room_count] = (rng_range(25) + 1 < dlvl) ? 0 : 1
    LD   A, 25
    CALL dg_rng_range
    INC  A                      ; [1, 25]
    LD   HL, abi_player_dlvl
    CP   (HL)
    LD   A, 0
    JR   C, .room_dark
    INC  A
.room_dark:
    LD   B, A
    LD   A, (room_count)
    LD   HL, room_lit
    CALL dg_idx_read
    LD   (HL), B

    ; Top extent (1..4) and interior height (3..8)
    LD   A, 4
    CALL dg_rng_range
    INC  A
    LD   E, A                   ; E = top_ext (1..4)
    LD   A, (dg_cy1)
    SUB  E
    LD   (dg_room_y), A
    LD   A, 3
    CALL dg_rng_range
    ADD  A, 2                   ; bottom_ext + center (2..4)
    ADD  A, E
    LD   (dg_room_h), A

    ; Left extent (1..11) and interior width (3..23)
    LD   A, 11
    CALL dg_rng_range
    INC  A
    LD   E, A                   ; E = left_ext (1..11)
    LD   A, (dg_cx1)
    SUB  E
    LD   (dg_room_x), A
    LD   A, 11
    CALL dg_rng_range
    ADD  A, 2                   ; right_ext + center (2..12)
    ADD  A, E
    LD   (dg_room_w), A

    ; Record room_x/y/w/h and temporary slot_id in room_type
    LD   A, (room_count)
    LD   E, A
    LD   D, 0
    LD   HL, room_x
    ADD  HL, DE
    LD   A, (dg_room_x)
    LD   (HL), A
    LD   BC, MAX_ROOMS
    ADD  HL, BC                 ; room_y
    LD   A, (dg_room_y)
    LD   (HL), A
    ADD  HL, BC                 ; room_w
    LD   A, (dg_room_w)
    LD   (HL), A
    ADD  HL, BC                 ; room_h
    LD   A, (dg_room_h)
    LD   (HL), A
    ADD  HL, BC                 ; room_lit (already stored)
    ADD  HL, BC                 ; room_type
    LD   A, (dg_slot_scan)
    LD   (HL), A

    CALL dg_draw_room

    LD   HL, room_count
    INC  (HL)

.skip_slot:
    LD   A, (dg_slot_scan)
    ADD  A, DG_SLOT_STRIDE
    CP   DG_SLOT_COUNT
    JR   C, .scan_ok
    SUB  DG_SLOT_COUNT
.scan_ok:
    LD   (dg_slot_scan), A
    LD   HL, dg_idx
    INC  (HL)
    LD   A, (HL)
    CP   DG_SLOT_COUNT
    RET  Z
    LD   A, (room_count)
    CP   MAX_ROOMS
    JP   C, .room_loop
    RET

; Draw room rectangle (dg_room_x/y/w/h) with DUNGEON_FLAGS
dg_draw_room:
    ; Top wall row: dg_room_y - 1
    LD   A, (dg_room_y)
    DEC  A
    LD   B, A
    LD   A, TILE_CORNER_TL | DUNGEON_FLAGS
    LD   E, TILE_WALL_H | DUNGEON_FLAGS
    LD   D, TILE_CORNER_TR | DUNGEON_FLAGS
    CALL dg_draw_room_row

    ; Interior rows: dg_room_y .. dg_room_y + dg_room_h - 1
    LD   A, (dg_room_h)
    LD   C, A
    LD   A, (dg_room_y)
    LD   B, A
.int_row:
    PUSH BC
    LD   A, TILE_WALL_V | DUNGEON_FLAGS
    LD   E, TILE_FLOOR | DUNGEON_FLAGS
    LD   D, TILE_WALL_V | DUNGEON_FLAGS
    CALL dg_draw_room_row
    POP  BC
    INC  B
    DEC  C
    JR   NZ, .int_row

    ; Bottom wall row: dg_room_y + dg_room_h
    LD   A, TILE_CORNER_BL | DUNGEON_FLAGS
    LD   E, TILE_WALL_H | DUNGEON_FLAGS
    LD   D, TILE_CORNER_BR | DUNGEON_FLAGS
    ; fall through to dg_draw_room_row

; Draw one room row at B: A = left tile, E = interior fill (dg_room_w), D = right tile
dg_draw_room_row:
    PUSH AF
    CALL dg_row_ptr_b           ; HL = row base
    LD   A, (dg_room_x)
    DEC  A                      ; left wall col
    LD   C, A
    LD   B, 0
    ADD  HL, BC                 ; HL = &map[row][left]
    POP  AF
    LD   (HL), A
    INC  HL
    LD   A, (dg_room_w)
    LD   B, A
.mid:
    LD   (HL), E
    INC  HL
    DJNZ .mid
    LD   (HL), D
    RET

; ===========================================================================
; Stage 3: dg_shuffle_rooms — Fisher-Yates shuffle across 6 contiguous arrays
; ===========================================================================
    ASSERT (room_y - room_x) == MAX_ROOMS
    ASSERT (room_w - room_y) == MAX_ROOMS
    ASSERT (room_h - room_w) == MAX_ROOMS
    ASSERT (room_lit - room_h) == MAX_ROOMS
    ASSERT (room_type - room_lit) == MAX_ROOMS
    ASSERT (trap_y - trap_x) == MAX_TRAPS
    ASSERT (trap_type - trap_y) == MAX_TRAPS
    ASSERT (door_state_y - door_state_x) == MAX_DOOR_STATES
    ASSERT (door_state_val - door_state_y) == MAX_DOOR_STATES

dg_shuffle_rooms:
    LD   A, (room_count)
    CP   2
    RET  C
    DEC  A
    LD   C, A                   ; C = i (room_count - 1 down to 1)
.loop:
    LD   A, C
    INC  A
    CALL dg_rng_range              ; A = j in [0, i]
    CP   C
    JR   Z, .skip
    ; Swap HL=&room_x[i] and DE=&room_x[j] across 6 MAX_ROOMS-stride arrays
    PUSH BC
    LD   E, A
    LD   D, 0
    LD   HL, room_x
    ADD  HL, DE
    EX   DE, HL                 ; DE = &room_x[j]
    LD   B, 0
    LD   HL, room_x
    ADD  HL, BC                 ; HL = &room_x[i]
    LD   B, 6
.swap:
    PUSH BC
    LD   B, (HL)
    LD   A, (DE)
    LD   (HL), A
    LD   A, B
    LD   (DE), A
    LD   BC, MAX_ROOMS
    ADD  HL, BC
    EX   DE, HL
    ADD  HL, BC
    EX   DE, HL
    POP  BC
    DJNZ .swap
    POP  BC
.skip:
    DEC  C
    JR   NZ, .loop
    RET

; ===========================================================================
; Stage 4: dg_connect_rooms — Staged cardinal tunnels + room-wall doors
; ===========================================================================
dg_connect_rooms:
    LD   A, (room_count)
    CP   2
    RET  C

    LD   A, 1
    LD   (dg_conn_i), A
.conn_loop:
    LD   A, (dg_conn_i)
    CALL dg_conn_center_start
    LD   A, (dg_conn_i)
    DEC  A
    CALL dg_conn_center_target
    CALL dg_carve_staged_tunnel
    CALL dg_materialize_staged_tunnel

    LD   HL, dg_conn_i
    INC  (HL)
    LD   A, (room_count)
    CP   (HL)
    JR   NZ, .conn_loop

    ; Wrap-around: room 0 -> room (room_count - 1)
    XOR  A
    CALL dg_conn_center_start
    LD   A, (room_count)
    DEC  A
    CALL dg_conn_center_target
    CALL dg_carve_staged_tunnel
    JP   dg_materialize_staged_tunnel

dg_conn_center_start:
    LD   HL, room_type
    CALL dg_idx_read            ; A = slot_id
    PUSH AF
    LD   HL, dg_slot_center_x
    CALL dg_idx_read
    LD   (dg_cx1), A
    POP  AF
    LD   HL, dg_slot_center_y
    CALL dg_idx_read
    LD   (dg_cy1), A
    RET

dg_conn_center_target:
    LD   HL, room_type
    CALL dg_idx_read            ; A = slot_id
    PUSH AF
    LD   HL, dg_slot_center_x
    CALL dg_idx_read
    LD   (dg_cx2), A
    POP  AF
    LD   HL, dg_slot_center_y
    CALL dg_idx_read
    LD   (dg_cy2), A
    RET

dg_carve_staged_tunnel:
    XOR  A
    LD   (dg_tun_dir), A
    LD   (dg_stop_flag), A
    LD   (dg_door_flag), A
    LD   (dg_tun_steps), A
    LD   (dg_tunnel_dirty), A
    LD   HL, DG_TUNNEL_MAX_STEPS
    LD   (dg_tun_count), HL

.cst_loop:
    LD   A, (dg_cx1)
    LD   HL, dg_cx2
    CP   (HL)
    JR   NZ, .not_done
    LD   A, (dg_cy1)
    LD   HL, dg_cy2
    CP   (HL)
    RET  Z

.not_done:
    ; 2,000-step termination guard (DGN-010)
    LD   HL, (dg_tun_count)
    LD   A, H
    OR   L
    RET  Z
    DEC  HL
    LD   (dg_tun_count), HL

    LD   A, (dg_cx1)
    LD   (dg_prev_x), A
    LD   A, (dg_cy1)
    LD   (dg_prev_y), A

    CALL dg_tunnel_step_toward

    LD   HL, dg_tun_steps
    LD   A, (HL)
    CP   0xFF
    JR   Z, .do_stage
    INC  (HL)
.do_stage:
    CALL dg_tunnel_stage_current
    LD   A, (dg_stop_flag)
    OR   A
    JR   Z, .cst_loop
    RET

; Record (B=row, C=col) into staged tunnel bounding box [scan_row/col_start..end].
; Preserves: BC, DE, HL.
dg_record_scan_bounds:
    LD   A, (dg_tunnel_dirty)
    OR   A
    JR   NZ, .update
    INC  A
    LD   (dg_tunnel_dirty), A
    LD   A, C
    LD   (dg_scan_col_start), A
    LD   (dg_scan_col_end), A
    LD   A, B
    LD   (dg_scan_row_start), A
    LD   (dg_scan_row_end), A
    RET
.update:
    PUSH HL
    LD   A, C
    LD   HL, dg_scan_col_start
    CP   (HL)
    JR   NC, .cmin_ok
    LD   (HL), A
.cmin_ok:
    LD   HL, dg_scan_col_end
    CP   (HL)
    JR   C, .cmax_ok
    LD   (HL), A
.cmax_ok:
    LD   A, B
    LD   HL, dg_scan_row_start
    CP   (HL)
    JR   NC, .rmin_ok
    LD   (HL), A
.rmin_ok:
    LD   HL, dg_scan_row_end
    CP   (HL)
    JR   C, .rmax_ok
    LD   (HL), A
.rmax_ok:
    POP  HL
    RET

dg_tunnel_step_toward:
    LD   A, (dg_tun_dir)
    OR   A
    JR   Z, .pick_correct
    LD   A, 100
    CALL dg_rng_range
    CP   DG_DUN_DIR_CHANGE
    JR   NC, .random_or_correct

    ; Keep current direction unless already aligned with target axis
    LD   A, (dg_tun_dir)
    CP   1
    JR   Z, .keep_h
    LD   A, (dg_cy1)
    LD   HL, dg_cy2
    CP   (HL)
    JR   NZ, .step_vert
    JR   .pick_correct
.keep_h:
    LD   A, (dg_cx1)
    LD   HL, dg_cx2
    CP   (HL)
    JR   NZ, .step_horiz

.pick_correct:
    LD   A, (dg_cx1)
    LD   HL, dg_cx2
    CP   (HL)
    JR   Z, .step_vert
    LD   A, (dg_cy1)
    LD   HL, dg_cy2
    CP   (HL)
    JR   Z, .step_horiz
    CALL dg_rng_next_u8
    BIT  0, A
    JR   Z, .step_horiz
    JR   .step_vert

.random_or_correct:
    LD   A, (dg_cx1)
    CP   2
    JR   C, .pick_correct
    CP   MAP_COLS - 2
    JR   NC, .pick_correct
    LD   A, (dg_cy1)
    CP   2
    JR   C, .pick_correct
    CP   MAP_ROWS - 2
    JR   NC, .pick_correct

    LD   A, DG_DUN_RANDOM_DIR
    CALL dg_rng_range
    CP   4
    JR   NC, .pick_correct
    OR   A
    JR   Z, .rand_up
    DEC  A
    JR   Z, .rand_down
    DEC  A
    JR   Z, .rand_left
    LD   A, 1
    LD   (dg_tun_dir), A
    JR   .h_inc
.rand_left:
    LD   A, 1
    LD   (dg_tun_dir), A
    JR   .h_dec
.rand_up:
    LD   A, 2
    LD   (dg_tun_dir), A
    JR   .v_dec
.rand_down:
    LD   A, 2
    LD   (dg_tun_dir), A
    JR   .v_inc

.step_vert:
    LD   A, 2
    LD   (dg_tun_dir), A
    LD   A, (dg_cy1)
    LD   HL, dg_cy2
    CP   (HL)
    JR   C, .v_inc
.v_dec:
    LD   HL, dg_cy1
    DEC  (HL)
    RET
.v_inc:
    LD   HL, dg_cy1
    INC  (HL)
    RET

.step_horiz:
    LD   A, 1
    LD   (dg_tun_dir), A
    LD   A, (dg_cx1)
    LD   HL, dg_cx2
    CP   (HL)
    JR   C, .h_inc
.h_dec:
    LD   HL, dg_cx1
    DEC  (HL)
    RET
.h_inc:
    LD   HL, dg_cx1
    INC  (HL)
    RET

dg_tunnel_stage_current:
    LD   A, (dg_cy1)
    LD   B, A
    CP   MAP_ROWS
    RET  NC
    LD   A, (dg_cx1)
    LD   C, A
    CP   MAP_COLS
    RET  NC
    LD   H, HIGH(DG_ROW_LO)
    LD   L, B
    LD   A, (HL)
    INC  H
    LD   H, (HL)
    ADD  A, C
    LD   L, A
    JR   NC, .ptr_ok
    INC  H
.ptr_ok:
    LD   A, (HL)
    LD   D, A                   ; D = current tile
    OR   A                      ; TILE_FLOOR == 0x00
    JR   Z, .tsc_blank
    CP   DGEN_TUNNEL
    RET  Z
    CP   DGEN_CORR
    JR   Z, .tsc_corr
    CP   DGEN_JUNCTION
    JR   Z, .tsc_corr
    AND  FLAG_OCCUPIED | FLAG_HAS_ITEM
    CP   FLAG_OCCUPIED
    JR   Z, .tsc_guarded_wall
    LD   A, D
    AND  TILE_TYPE_MASK
    RET  Z                      ; room floor / other floor flags
    CP   TILE_DOOR_OPEN
    RET  NC                     ; door
    LD   A, D
    AND  FLAG_LIT
    JR   Z, .tsc_blank          ; unlit rock

    ; Lit room wall -> mark staged door candidate & guard 3x3 lit wall neighbors
    LD   A, D
    OR   FLAG_HAS_ITEM | FLAG_OCCUPIED
    LD   (HL), A
    CALL dg_record_scan_bounds
    CALL dg_mark_neighbor_walls_temp
    XOR  A
    LD   (dg_door_flag), A
    RET

.tsc_blank:
    LD   (HL), DGEN_TUNNEL
    CALL dg_record_scan_bounds
    XOR  A
    LD   (dg_door_flag), A
    RET

.tsc_corr:
    LD   A, (dg_door_flag)
    OR   A
    JR   NZ, .tsc_maybe_stop
    LD   A, D
    OR   FLAG_HAS_ITEM
    LD   (HL), A
    LD   A, 1
    LD   (dg_door_flag), A
.tsc_maybe_stop:
    LD   A, 100
    CALL dg_rng_range
    CP   DG_DUN_TUNNELING
    RET  C
    LD   A, (dg_tun_steps)
    CP   11
    RET  C
    LD   A, 1
    LD   (dg_stop_flag), A
    RET

.tsc_guarded_wall:
    LD   A, (dg_prev_x)
    LD   (dg_cx1), A
    LD   A, (dg_prev_y)
    LD   (dg_cy1), A
    RET

; Mark lit room walls in 3x3 around (dg_cx1, dg_cy1) with FLAG_OCCUPIED
dg_mark_neighbor_walls_temp:
    LD   A, (dg_cy1)
    DEC  A
    LD   B, A                   ; B = row (may wrap 0xFF if cy1==0)
    LD   D, 3
.mnw_row:
    LD   A, B
    CP   MAP_ROWS
    JR   NC, .mnw_next_row
    CALL dg_row_ptr_b           ; HL = &map[B][0]
    LD   A, (dg_cx1)
    DEC  A
    LD   C, A                   ; C = col (may wrap 0xFF if cx1==0)
    LD   E, 0
    ADD  A, L
    LD   L, A
    JR   NC, .mnw_ptr_adj
    INC  H
    ; If C==0xFF (wrapped from 0), HL = &map[B][255] instead of -1; harmless because col bounds check skips!
.mnw_ptr_adj:
    LD   A, C
    CP   0xFF
    JR   NZ, .mnw_c_start
    ; C was 0xFF: skip col 0xFF and wrap HL back to &map[B][0]
    LD   A, (dg_cx1)            ; 0
    LD   E, 2                   ; remaining 2 cols (0, 1)
    INC  C                      ; C = 0
    CALL dg_row_ptr_b           ; HL = &map[B][0]
    JR   .mnw_col
.mnw_c_start:
    LD   E, 3
.mnw_col:
    LD   A, C
    CP   MAP_COLS
    JR   NC, .mnw_next_row
    LD   A, (HL)
    BIT  3, A                   ; FLAG_LIT == 0x08
    JR   Z, .mnw_next_col
    LD   (dg_cur_row), A        ; reuse 1-byte temp for quick mask test
    AND  TILE_TYPE_MASK
    JR   Z, .mnw_next_col
    CP   TILE_DOOR_OPEN
    JR   NC, .mnw_next_col
    LD   A, (dg_cur_row)
    OR   FLAG_OCCUPIED
    LD   (HL), A
.mnw_next_col:
    INC  HL
    INC  C
    DEC  E
    JR   NZ, .mnw_col
.mnw_next_row:
    INC  B
    DEC  D
    JR   NZ, .mnw_row
    RET

dg_materialize_staged_tunnel:
    LD   A, (dg_tunnel_dirty)
    OR   A
    RET  Z
    LD   A, 0x80
    LD   (dg_open_mode), A
    LD   A, (dg_scan_col_end)
    LD   HL, dg_scan_col_start
    SUB  (HL)
    INC  A
    LD   (dg_scan_col_width), A ; >= 1
    LD   A, (dg_scan_row_start)
.mst_row:
    LD   (dg_cur_row), A
    LD   B, A
    CALL dg_row_ptr_b           ; HL = MAP_BASE + B * 198
    LD   A, (dg_scan_col_start)
    LD   E, A
    LD   D, 0
    ADD  HL, DE                 ; HL = &map[row][col_start]
    LD   A, (dg_scan_col_width)
    LD   B, A                   ; B = remaining cols
.mst_col:
    LD   A, (HL)
    AND  DGEN_TUNNEL | FLAG_HAS_ITEM ; 0x06: zero for 0x00,0x01,0x08,0x18..0x68,doors!
    JR   NZ, .mst_hit
.mst_next:
    INC  HL
    DJNZ .mst_col

    LD   A, (dg_cur_row)
    LD   HL, dg_scan_row_end
    CP   (HL)
    JR   Z, .mst_done
    JR   NC, .mst_done
    INC  A
    JR   .mst_row
.mst_done:
    XOR  A
    LD   (dg_open_mode), A
    RET

.mst_hit:
    LD   A, (HL)
    CP   DGEN_TUNNEL
    JR   NZ, .chk_cand
    LD   (HL), DGEN_CORR
    JR   .mst_next
.chk_cand:
    LD   D, A
    AND  TILE_TYPE_MASK
    JR   Z, .mst_next
    CP   TILE_DOOR_OPEN
    JR   NC, .mst_next
    LD   A, D
    AND  FLAG_HAS_ITEM
    JR   Z, .mst_next

    ; Staged wall penetration candidate at HL; recover (B=row, C=col)
    PUSH BC
    PUSH HL
    LD   A, (dg_scan_col_end)
    INC  A
    SUB  B
    LD   C, A
    LD   A, (dg_cur_row)
    LD   B, A

    LD   A, 100
    CALL dg_rng_range
    CP   DG_DUN_ROOM_DOORS
    JR   NC, .cand_floor
    LD   A, D
    AND  TILE_TYPE_MASK
    CP   TILE_WALL_H
    JR   Z, .chk_hwall
    CP   TILE_WALL_V
    JR   NZ, .cand_floor
    CALL dg_opposing_vertical
    JR   NC, .cand_floor
    CALL dg_corridor_left_right
    JR   .checked_wall
.chk_hwall:
    CALL dg_opposing_horizontal
    JR   NC, .cand_floor
    CALL dg_corridor_up_down
.checked_wall:
    JR   NC, .cand_floor
    CALL dg_random_door_type
    POP  HL
    LD   (HL), A
    POP  BC
    JR   .mst_next
.cand_floor:
    POP  HL
    LD   (HL), DGEN_CORR
    POP  BC
    JR   .mst_next

; Return A = random door tile | DUNGEON_FLAGS. Preserves BC, DE, HL, IX, IY.
dg_random_door_type:
    PUSH HL
    LD   A, 3
    CALL dg_rng_range
    ADD  A, LOW(dg_rdt_table)
    LD   L, A
    ADC  A, HIGH(dg_rdt_table)
    SUB  L
    LD   H, A
    LD   A, (HL)
    POP  HL
    RET

; Geometry helpers (all preserve BC)
dg_corridor_left_right:
    PUSH BC
    DEC  C
    CALL dg_cell_is_corridor
    POP  BC
    RET  NC
    PUSH BC
    INC  C
    CALL dg_cell_is_corridor
    POP  BC
    RET

dg_corridor_up_down:
    PUSH BC
    DEC  B
    CALL dg_cell_is_corridor
    POP  BC
    RET  NC
    PUSH BC
    INC  B
    CALL dg_cell_is_corridor
    POP  BC
    RET

dg_opposing_vertical:
    PUSH BC
    DEC  B
    CALL dg_cell_is_wall
    POP  BC
    RET  NC
    PUSH BC
    INC  B
    CALL dg_cell_is_wall
    POP  BC
    RET

dg_opposing_horizontal:
    PUSH BC
    DEC  C
    CALL dg_cell_is_wall
    POP  BC
    RET  NC
    PUSH BC
    INC  C
    CALL dg_cell_is_wall
    POP  BC
    RET

; Output: CF = 1 if (B, C) is corridor/open (depending on dg_open_mode). Preserves BC.
dg_cell_is_corridor:
    CALL dg_read_bc
    JR   C, .no
    LD   E, A
    LD   A, (dg_open_mode)
    BIT  7, A
    JR   NZ, .open
    LD   A, E
    CP   TILE_FLOOR
    JR   Z, .yes
.no:
    OR   A
    RET
.open:
    LD   A, E
    OR   A
    JR   Z, .no                 ; 0x00 blank cave is rock
    AND  TILE_TYPE_MASK
    JR   Z, .yes                ; room floor / corridor / tunnel / junction
    CP   TILE_DOOR_OPEN
    JR   NC, .yes               ; doors
    LD   A, E
    AND  FLAG_HAS_ITEM
    JR   Z, .no                 ; non-candidate wall
.yes:
    SCF
    RET

; Output: CF = 1 if (B, C) is TILE_WALL_H or TILE_WALL_V. Preserves BC.
dg_cell_is_wall:
    CALL dg_read_bc
    JR   C, .no
    AND  TILE_TYPE_MASK
    CP   TILE_WALL_H
    JR   Z, .yes
    CP   TILE_WALL_V
    JR   Z, .yes
.no:
    OR   A
    RET
.yes:
    SCF
    RET

; ===========================================================================
; Stage 5: dg_fill_cave_granite — Convert scratch markers & seal outer border
; ===========================================================================
dg_fill_cave_granite:
    XOR  A
    LD   (dg_jct_count), A
    LD   HL, MAP_BASE
    CALL dg_fcg_border_row      ; row 0

    LD   C, MAP_ROWS - 2        ; rows 1..64
.int_row:
    CALL dg_fcg_border_cell     ; col 0
    INC  HL
    LD   B, MAP_COLS - 2        ; cols 1..196
.int_col:
    LD   A, (HL)
    OR   A
    JR   NZ, .not_blank
    LD   (HL), TILE_WALL_H
.int_next:
    INC  HL
    DJNZ .int_col
    CALL dg_fcg_border_cell     ; col 197
    INC  HL
    DEC  C
    JR   NZ, .int_row
    JP   dg_fcg_border_row      ; row 65

.not_blank:
    CP   DGEN_CORR
    JR   Z, .to_floor
    CP   DGEN_JUNCTION
    JR   Z, .to_jct
    CP   DGEN_TUNNEL
    JR   Z, .to_floor
    LD   D, A
    AND  FLAG_OCCUPIED | FLAG_HAS_ITEM
    CP   FLAG_OCCUPIED
    JR   NZ, .int_next
    LD   A, D
    AND  (~FLAG_OCCUPIED) & 0xFF
    LD   (HL), A
    JR   .int_next
.to_floor:
    LD   (HL), TILE_FLOOR
    JR   .int_next
.to_jct:
    LD   (HL), FLAG_HAS_ITEM
    LD   A, (dg_jct_count)
    CP   DG_MAX_DOOR_SCAN
    JR   NC, .int_next
    PUSH HL
    LD   E, A
    LD   D, 0
    INC  A
    LD   (dg_jct_count), A
    LD   A, MAP_COLS - 1
    SUB  B                      ; col (1..196)
    LD   HL, DG_DOOR_SCAN_X
    ADD  HL, DE
    LD   (HL), A
    LD   A, MAP_ROWS - 1
    SUB  C                      ; row (1..64)
    LD   HL, DG_DOOR_SCAN_Y
    ADD  HL, DE
    LD   (HL), A
    POP  HL
    JR   .int_next

dg_fcg_border_row:
    LD   B, MAP_COLS
.lp:
    CALL dg_fcg_border_cell
    INC  HL
    DJNZ .lp
    RET

dg_fcg_border_cell:
    LD   A, (HL)
    LD   D, A
    AND  TILE_TYPE_MASK
    JR   Z, .rock
    CP   TILE_DOOR_OPEN
    JR   NC, .rock
    LD   A, D
    AND  (~(FLAG_OCCUPIED | FLAG_HAS_ITEM)) & 0xFF
    LD   (HL), A
    RET
.rock:
    LD   (HL), TILE_WALL_H
    RET

; ===========================================================================
; Stage 6: dg_place_streamers — 3 magma + 2 quartz veins (density 5, <= 180)
; ===========================================================================
dg_place_streamers:
    LD   A, TILE_MAGMA
    LD   (dg_mineral), A
    CALL dg_carve_streamer
    CALL dg_carve_streamer
    CALL dg_carve_streamer
    LD   A, TILE_QUARTZ
    LD   (dg_mineral), A
    CALL dg_carve_streamer
    JP   dg_carve_streamer

dg_carve_streamer:
    LD   A, 23
    CALL dg_rng_range
    LD   B, A
    LD   A, (MAP_ROWS / 2) + 10
    SUB  B
    LD   (dg_cy1), A

    LD   A, 33
    CALL dg_rng_range
    LD   B, A
    LD   A, (MAP_COLS / 2) + 15
    SUB  B
    LD   (dg_cx1), A

    CALL dg_rng_next_u8
    AND  7
    LD   HL, dg_cs_dx_table
    CALL dg_idx_read
    LD   (dg_cs_dx), A
    LD   BC, 8
    ADD  HL, BC
    LD   A, (HL)
    LD   (dg_cs_dy), A

    LD   A, DG_STREAMER_MAX_STEPS
    LD   (dg_retries), A

.step:
    LD   A, (dg_cx1)
    LD   C, A
    OR   A
    RET  Z
    CP   MAP_COLS - 1
    RET  NC
    LD   A, (dg_cy1)
    LD   B, A
    OR   A
    RET  Z
    CP   MAP_ROWS - 1
    RET  NC

    LD   E, C                   ; E = cx2 (preserved across dg_rng5_pair / dg_rng_range)
    LD   D, B                   ; D = cy2 (preserved across dg_rng5_pair / dg_rng_range)
    LD   C, DG_STREAMER_DENSITY ; C = stamp counter (5 down to 1)
.stamp:
    CALL dg_rng5_pair           ; H = dx (0..4), A = dy (0..4)
    SUB  2
    ADD  A, D
    LD   B, A                   ; B = target row y
    LD   A, H
    SUB  2
    ADD  A, E
    LD   H, A                   ; H = target col x

    LD   A, H
    OR   A
    JR   Z, .no_write
    CP   MAP_COLS - 1
    JR   NC, .no_write
    LD   A, B
    OR   A
    JR   Z, .no_write
    CP   MAP_ROWS - 1
    JR   NC, .no_write

    ; Inline &map[B][H] via DG_ROW_LO/HI (preserve C=stamp counter)
    PUSH BC
    LD   C, H                   ; C = col x
    LD   H, HIGH(DG_ROW_LO)
    LD   L, B
    LD   A, (HL)
    INC  H
    LD   H, (HL)
    ADD  A, C
    LD   L, A
    JR   NC, .ptr_ok
    INC  H
.ptr_ok:
    POP  BC

    LD   A, (HL)
    CP   TILE_WALL_H            ; only overwrite plain unlit granite (0x10)
    JR   NZ, .no_write
    LD   A, (dg_mineral)
    LD   (HL), A
    CP   TILE_QUARTZ
    LD   A, 95
    JR   NZ, .t_roll
    LD   A, 55
.t_roll:
    CALL dg_rng_range
    OR   A
    JR   NZ, .no_write
    LD   A, (HL)
    OR   FLAG_HAS_ITEM
    LD   (HL), A
.no_write:
    DEC  C
    JR   NZ, .stamp

    LD   A, E
    LD   HL, dg_cs_dx
    ADD  A, (HL)
    LD   (dg_cx1), A
    LD   A, D
    LD   HL, dg_cs_dy
    ADD  A, (HL)
    LD   (dg_cy1), A

    LD   HL, dg_retries
    DEC  (HL)
    JR   NZ, .step
    RET

; Output: CF = 1 iff 1 <= C <= MAP_COLS - 2 && 1 <= B <= MAP_ROWS - 2
dg_cs_in_bounds:
    LD   A, C
    OR   A
    RET  Z                      ; CF = 0
    CP   MAP_COLS - 1
    JR   NC, .oob
    LD   A, B
    OR   A
    RET  Z                      ; CF = 0
    CP   MAP_ROWS - 1
    RET                         ; CF = 1 iff B < MAP_ROWS - 1
.oob:
    OR   A                      ; CF = 0
    RET

; ===========================================================================
; Stage 7: dg_place_junction_doors
; ===========================================================================
dg_place_junction_doors:
    LD   A, (dg_jct_count)
    OR   A
    RET  Z
    CP   DG_MAX_DOOR_SCAN
    JR   NC, .full_scan
    LD   B, A
    LD   DE, 0
.idx_lp:
    PUSH BC
    PUSH DE
    LD   HL, DG_DOOR_SCAN_X
    ADD  HL, DE
    LD   C, (HL)
    LD   HL, DG_DOOR_SCAN_Y
    ADD  HL, DE
    LD   B, (HL)
    LD   H, HIGH(DG_ROW_LO)
    LD   L, B
    LD   A, (HL)
    INC  H
    LD   H, (HL)
    ADD  A, C
    LD   L, A
    JR   NC, .idx_ptr_ok
    INC  H
.idx_ptr_ok:
    LD   A, (HL)
    AND  TILE_TYPE_MASK | FLAG_HAS_ITEM
    CP   FLAG_HAS_ITEM
    JR   NZ, .idx_next
    CALL dg_process_junction_hit
.idx_next:
    POP  DE
    POP  BC
    INC  E
    DJNZ .idx_lp
    RET

.full_scan:
    XOR  A
.row:
    LD   (dg_cur_row), A
    LD   B, A
    CALL dg_row_ptr_b           ; HL = MAP_BASE + row * 198
    LD   B, MAP_COLS
.col:
    LD   A, (HL)
    AND  TILE_TYPE_MASK | FLAG_HAS_ITEM
    CP   FLAG_HAS_ITEM
    JR   Z, .hit
.next:
    INC  HL
    DJNZ .col
    LD   A, (dg_cur_row)
    INC  A
    CP   MAP_ROWS
    JR   C, .row
    RET

.hit:
    PUSH BC
    PUSH HL
    LD   A, MAP_COLS
    SUB  B
    LD   C, A                   ; C = col (0..197)
    LD   A, (dg_cur_row)
    LD   B, A                   ; B = row (0..65)
    CALL dg_process_junction_hit
    POP  HL
    POP  BC
    JR   .next

dg_process_junction_hit:
    ; Clear junction scratch marker and test 4 cardinal neighbors
    LD   (HL), TILE_FLOOR
    XOR  A
    LD   (dg_door_flag), A
    LD   D, 0
.nbr:
    PUSH BC
    PUSH DE
    LD   A, D
    LD   HL, dg_pjd_dx
    CALL dg_idx_read
    ADD  A, C
    LD   C, A
    LD   A, D
    LD   HL, dg_pjd_dy
    CALL dg_idx_read
    ADD  A, B
    LD   B, A
    CALL dg_try_junction_door
    POP  DE
    POP  BC
    INC  D
    LD   A, D
    CP   4
    JR   C, .nbr
    RET

dg_try_junction_door:
    LD   A, (dg_door_flag)
    OR   A
    RET  NZ
    CALL dg_cs_in_bounds
    RET  NC
    CALL dg_read_bc
    CP   TILE_FLOOR             ; unlit corridor floor only (0x00)
    RET  NZ
    LD   A, 100
    CALL dg_rng_range
    CP   DG_DUN_TUNNEL_DOORS
    RET  C
    CALL dg_junction_door_geometry_ok
    RET  NC
    CALL dg_random_door_type
    CALL dg_write_bc
    LD   A, 1
    LD   (dg_door_flag), A
    RET

dg_junction_door_geometry_ok:
    CALL dg_opposing_vertical
    JR   NC, .try_vert
    CALL dg_corridor_left_right
    RET  C
.try_vert:
    CALL dg_opposing_horizontal
    RET  NC
    JP   dg_corridor_up_down

; ===========================================================================
; Stage 8: dg_assign_special_room & dg_vault_seal_entrance
; ===========================================================================
dg_assign_special_room:
    LD   A, (room_count)
    OR   A
    RET  Z
    LD   B, A
    LD   HL, room_type
    XOR  A
.clr:
    LD   (HL), A
    INC  HL
    DJNZ .clr

    LD   A, (abi_player_dlvl)
    CP   3
    RET  C
    LD   A, (room_count)
    CP   2
    RET  C

    LD   A, 100
    CALL dg_rng_range
    LD   D, A                   ; D = roll [0, 99]

    ; threshold = min(dlvl * 3, 60)
    LD   A, (abi_player_dlvl)
    CP   20
    JR   C, .mul3
    LD   A, 60
    JR   .thresh_ok
.mul3:
    LD   E, A
    ADD  A, A
    ADD  A, E
.thresh_ok:
    CP   D
    RET  Z                      ; roll == threshold -> none
    RET  C                      ; threshold < roll -> none

    LD   A, (room_count)
    DEC  A
    CALL dg_rng_range
    INC  A
    LD   (sr_room_idx), A

    LD   A, (abi_player_dlvl)
    CP   8
    JR   NC, .all_three
    CP   5
    JR   NC, .pit_or_nest
    LD   A, RT_NEST
    JR   .store
.pit_or_nest:
    LD   A, 2
    CALL dg_rng_range
    OR   A
    LD   A, RT_NEST
    JR   Z, .store
    LD   A, RT_PIT
    JR   .store
.all_three:
    LD   A, 3
    CALL dg_rng_range
    INC  A                      ; 1=RT_PIT, 2=RT_VAULT, 3=RT_NEST
.store:
    LD   B, A
    LD   A, (sr_room_idx)
    LD   HL, room_type
    CALL dg_idx_read
    LD   (HL), B
    RET

dg_vault_seal_entrance:
    LD   A, (room_count)
    OR   A
    RET  Z
    LD   B, A
    LD   C, 0
    LD   HL, room_type
.find:
    LD   A, (HL)
    CP   RT_VAULT
    JR   Z, .found
    INC  HL
    INC  C
    DJNZ .find
    RET

.found:
    LD   A, C
    LD   HL, room_x
    CALL dg_idx_read
    LD   (dg_room_x), A
    LD   A, C
    LD   HL, room_y
    CALL dg_idx_read
    LD   (dg_room_y), A
    LD   A, C
    LD   HL, room_w
    CALL dg_idx_read
    LD   (dg_room_w), A
    LD   A, C
    LD   HL, room_h
    CALL dg_idx_read
    LD   (dg_room_h), A

    ; Scan top wall: y = ry - 1, x = rx..rx+rw-1
    LD   A, (dg_room_y)
    DEC  A
    LD   B, A
    CALL dg_vse_scan_hwall
    RET  C

    ; Scan bottom wall: y = ry + rh
    LD   A, (dg_room_y)
    LD   HL, dg_room_h
    ADD  A, (HL)
    LD   B, A
    CALL dg_vse_scan_hwall
    RET  C

    ; Scan left wall: x = rx - 1, y = ry..ry+rh-1
    LD   A, (dg_room_x)
    DEC  A
    LD   C, A
    CALL dg_vse_scan_vwall
    RET  C

    ; Scan right wall: x = rx + rw
    LD   A, (dg_room_x)
    LD   HL, dg_room_w
    ADD  A, (HL)
    LD   C, A
    JP   dg_vse_scan_vwall

dg_vse_scan_hwall:
    LD   A, (dg_room_x)
    LD   C, A
    LD   A, (dg_room_w)
    LD   E, A
.lp:
    CALL dg_vse_try_cell
    RET  C
    INC  C
    DEC  E
    JR   NZ, .lp
    OR   A
    RET

dg_vse_scan_vwall:
    LD   A, (dg_room_y)
    LD   B, A
    LD   A, (dg_room_h)
    LD   E, A
.lp:
    CALL dg_vse_try_cell
    RET  C
    INC  B
    DEC  E
    JR   NZ, .lp
    OR   A
    RET

dg_vse_try_cell:
    CALL dg_read_bc
    JR   C, .no
    AND  TILE_TYPE_MASK
    JR   Z, .seal               ; TILE_FLOOR (0x00)
    CP   TILE_DOOR_OPEN
    JR   Z, .seal
    CP   TILE_DOOR_CLOSED
    JR   Z, .seal
.no:
    OR   A
    RET
.seal:
    LD   (HL), TILE_SECRET | DUNGEON_FLAGS
    SCF
    RET

; ===========================================================================
; Stage 9: dg_place_stairs_dungeon — 1..2 up, 3..4 down (DGN-016)
; ===========================================================================
dg_place_stairs_dungeon:
    LD   A, (room_count)
    OR   A
    RET  Z

    ; Tracked up stair (room 0)
    XOR  A
    CALL dg_random_wall_adj_stair_floor
    LD   A, C
    LD   (stairs_up_x), A
    LD   A, B
    LD   (stairs_up_y), A
    LD   A, TILE_STAIRS_UP | DUNGEON_FLAGS
    CALL dg_write_bc

    ; Tracked down stair 1 (room 1)
    LD   A, 1
    CALL dg_random_wall_adj_stair_floor
    LD   A, C
    LD   (stairs_dn1_x), A
    LD   A, B
    LD   (stairs_dn1_y), A
    LD   A, TILE_STAIRS_DN | DUNGEON_FLAGS
    CALL dg_write_bc

    ; Tracked down stair 2 (room 2)
    LD   A, 2
    CALL dg_random_wall_adj_stair_floor
    LD   A, C
    LD   (stairs_dn2_x), A
    LD   A, B
    LD   (stairs_dn2_y), A
    LD   A, TILE_STAIRS_DN | DUNGEON_FLAGS
    CALL dg_write_bc

    ; Extra untracked stairs: 1 down + 0..1 down + 0..1 up
    LD   A, TILE_STAIRS_DN | DUNGEON_FLAGS
    CALL dg_place_extra_stair
    LD   A, TILE_STAIRS_DN | DUNGEON_FLAGS
    CALL dg_maybe_extra_stair
    LD   A, TILE_STAIRS_UP | DUNGEON_FLAGS
dg_maybe_extra_stair:
    LD   D, A
    LD   A, 2
    CALL dg_rng_range
    OR   A
    RET  Z
    LD   A, D
dg_place_extra_stair:
    PUSH AF
    LD   A, (dg_stair_room_idx)
    INC  A
    LD   HL, room_count
    CP   (HL)
    JR   C, .room_ok
    XOR  A
.room_ok:
    CALL dg_random_wall_adj_stair_floor
    CALL dg_read_bc
    JR   C, .skip
    AND  TILE_TYPE_MASK
    CP   TILE_FLOOR
    JR   NZ, .skip
    POP  AF
    LD   (HL), A
    RET
.skip:
    POP  AF
    RET

; Input: A = room_idx. Output: B = y, C = x.
dg_random_wall_adj_stair_floor:
    LD   HL, room_count
    CP   (HL)
    JR   C, .ok
    XOR  A
.ok:
    LD   (dg_stair_room_idx), A
    LD   D, 3                   ; threshold 3..0
.thresh_loop:
    LD   E, DG_STAIR_WALL_TRIES ; 20 tries per threshold
.try_loop:
    LD   A, (dg_stair_room_idx)
    CALL dg_random_floor_in_room ; B = y in [1..64], C = x in [1..196]
    LD   H, HIGH(DG_ROW_LO)
    LD   L, B
    LD   A, (HL)
    INC  H
    LD   H, (HL)
    ADD  A, C
    LD   L, A
    JR   NC, .ptr_ok
    INC  H
.ptr_ok:
    LD   A, (HL)
    AND  TILE_TYPE_MASK
    JR   NZ, .next_try
    ; Count lit walls in 4 cardinal neighbors directly via HL
    PUSH DE
    LD   E, 0                   ; count
    DEC  HL
    CALL dg_stair_chk_hl        ; (x-1, y)
    INC  HL
    INC  HL
    CALL dg_stair_chk_hl        ; (x+1, y)
    DEC  HL
    PUSH BC
    LD   BC, -MAP_COLS
    ADD  HL, BC
    CALL dg_stair_chk_hl        ; (x, y-1)
    LD   BC, MAP_COLS * 2
    ADD  HL, BC
    CALL dg_stair_chk_hl        ; (x, y+1)
    POP  BC
    LD   A, E
    POP  DE
    CP   D
    RET  NC
.next_try:
    DEC  E
    JR   NZ, .try_loop
    LD   A, D
    OR   A
    JR   Z, .fallback
    DEC  D
    JR   .thresh_loop
.fallback:
    LD   A, (dg_stair_room_idx)
dg_random_floor_in_room:
    PUSH AF
    LD   HL, room_w
    CALL dg_idx_read
    CALL dg_rng_range
    LD   C, A
    POP  AF
    PUSH AF
    LD   HL, room_x
    CALL dg_idx_read
    ADD  A, C
    LD   C, A                   ; C = x
    POP  AF
    PUSH AF
    LD   HL, room_h
    CALL dg_idx_read
    CALL dg_rng_range
    LD   B, A
    POP  AF
    LD   HL, room_y
    CALL dg_idx_read
    ADD  A, B
    LD   B, A                   ; B = y
    RET

; Count lit wall at HL into E; preserves BC, DE(D), HL.
dg_stair_chk_hl:
    LD   A, (HL)
    BIT  3, A                   ; FLAG_LIT == 0x08
    RET  Z
    AND  TILE_TYPE_MASK
    RET  Z
    CP   TILE_DOOR_OPEN
    RET  NC
    INC  E
    RET

; ===========================================================================
; Stage 10a: dg_place_traps — Hidden traps [1, clamp(dlvl/3,2,10)], 0..17 (DGN-019)
; ===========================================================================
dg_place_traps:
    LD   A, (abi_player_dlvl)
    OR   A
    RET  Z
    LD   L, A
    LD   H, 0
    LD   C, 3
    CALL div_hl_c               ; L = dlvl / 3
    LD   A, L
    CP   2
    JR   NC, .min_ok
    LD   A, 2
.min_ok:
    CP   11
    JR   C, .max_ok
    LD   A, 10
.max_ok:
    CALL dg_rng_range
    INC  A
    LD   (trap_count), A

    XOR  A
    LD   (dg_idx), A
.loop:
    LD   A, (dg_idx)
    LD   HL, trap_count
    CP   (HL)
    RET  Z
    CALL dg_find_random_floor
    JR   NC, .cap_count

    LD   A, (dg_idx)
    LD   E, A
    LD   D, 0
    LD   HL, trap_x
    ADD  HL, DE
    LD   A, (df_target_x)
    LD   (HL), A
    LD   BC, MAX_TRAPS
    ADD  HL, BC                 ; trap_y
    LD   A, (df_target_y)
    LD   (HL), A
    ADD  HL, BC                 ; trap_type
    PUSH HL
    LD   A, TRAP_TYPE_COUNT     ; 18 (uniform [0, 17])
    CALL dg_rng_range
    POP  HL
    LD   (HL), A

    LD   HL, dg_idx
    INC  (HL)
    JR   .loop

.cap_count:
    LD   A, (dg_idx)
    LD   (trap_count), A
    RET

; Find unoccupied interior floor tile -> CF = 1 & df_target_x/y; CF = 0 after 2048 tries
dg_find_random_floor:
    LD   D, 8                   ; 8 * 256 = 2,048 tries
    LD   E, 0
.loop:
    LD   A, MAP_COLS - 2
    CALL dg_rng_range
    INC  A
    LD   C, A                   ; C = x in [1, 196]
    LD   A, MAP_ROWS - 2
    CALL dg_rng_range
    INC  A
    LD   B, A                   ; B = y in [1, 64]
    CALL dg_read_bc
    JR   C, .next
    AND  TILE_TYPE_MASK | FLAG_OCCUPIED
    JR   NZ, .next
    LD   A, C
    LD   (df_target_x), A
    LD   A, B
    LD   (df_target_y), A
    SCF
    RET
.next:
    DEC  E
    JR   NZ, .loop
    DEC  D
    JR   NZ, .loop
    OR   A
    RET

; ===========================================================================
; Stage 10b: dg_place_secrets — Secret door conversion + locked/stuck states (DGN-015)
; ===========================================================================
dg_place_secrets:
    XOR  A
    LD   (dg_door_scan_count), A

    ; Pass 1: collect TILE_DOOR_CLOSED across 1..MAP_ROWS-2 x 1..MAP_COLS-2
    LD   A, 1
.ps_row:
    LD   (dg_cur_row), A
    LD   B, A
    CALL dg_row_ptr_b
    INC  HL                     ; &map[row][1]
    LD   B, MAP_COLS - 2
.ps_col:
    LD   A, (HL)
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_CLOSED
    JR   Z, .ps_hit
.ps_next:
    INC  HL
    DJNZ .ps_col
    LD   A, (dg_cur_row)
    INC  A
    CP   MAP_ROWS - 1
    JR   C, .ps_row
    JR   .ps_check_any

.ps_hit:
    LD   A, (dg_door_scan_count)
    CP   DG_MAX_DOOR_SCAN
    JR   NC, .ps_next
    PUSH HL
    LD   E, A
    LD   D, 0
    INC  A
    LD   (dg_door_scan_count), A
    LD   A, MAP_COLS - 1
    SUB  B                      ; A = col (1..196)
    LD   HL, DG_DOOR_SCAN_X
    ADD  HL, DE
    LD   (HL), A
    LD   A, (dg_cur_row)
    LD   HL, DG_DOOR_SCAN_Y
    ADD  HL, DE
    LD   (HL), A
    POP  HL
    JR   .ps_next

.ps_check_any:
    LD   A, (dg_door_scan_count)
    OR   A
    RET  Z
    LD   (dg_door_orig_count), A

    ; Init row-major index table DG_DOOR_IDX[0..count-1] so DG_DOOR_SCAN_X/Y stays sorted
    LD   B, A
    LD   HL, DG_DOOR_IDX
    XOR  A
.idx_init:
    LD   (HL), A
    INC  HL
    INC  A
    DJNZ .idx_init

    ; Convert 1..3 random closed doors (clamped to dg_door_scan_count)
    LD   A, 3
    CALL dg_rng_range
    INC  A
    LD   HL, dg_door_scan_count
    CP   (HL)
    JR   C, .conv_cnt_ok
    LD   A, (HL)
.conv_cnt_ok:
    LD   E, A                   ; E = remaining conversions
.conv_loop:
    LD   A, (dg_door_scan_count)
    CALL dg_rng_range           ; A = pick in DG_DOOR_IDX
    LD   D, A                   ; D = pick slot
    PUSH DE
    LD   HL, DG_DOOR_IDX
    CALL dg_idx_read
    LD   D, A                   ; D = actual door index
    LD   HL, DG_DOOR_SCAN_X
    CALL dg_idx_read
    LD   C, A
    LD   A, D
    LD   HL, DG_DOOR_SCAN_Y
    CALL dg_idx_read
    LD   B, A
    CALL dg_read_bc
    JR   C, .skip_wr
    AND  TILE_FLAG_MASK
    OR   TILE_SECRET
    LD   (HL), A
.skip_wr:
    ; Swap picked index with last in DG_DOOR_IDX (preserves DG_DOOR_SCAN_X/Y row-major order!)
    LD   HL, dg_door_scan_count
    DEC  (HL)
    LD   A, (HL)
    LD   HL, DG_DOOR_IDX
    CALL dg_idx_read
    LD   C, A                   ; C = last index
    POP  DE                     ; D = pick slot, E = rem
    PUSH DE
    LD   A, D
    LD   HL, DG_DOOR_IDX
    CALL dg_idx_read
    LD   (HL), C
    POP  DE
    DEC  E
    JR   NZ, .conv_loop

    ; Pass 2: iterate preserved row-major DG_DOOR_SCAN_X/Y directly unless table saturated (>=128)
    LD   A, (dg_door_orig_count)
    CP   DG_MAX_DOOR_SCAN
    JR   NC, .pss_full_scan
    LD   B, A                   ; count 1..127
    LD   DE, 0                  ; E = idx 0..count-1
.pss_idx_lp:
    PUSH BC
    PUSH DE
    LD   HL, DG_DOOR_SCAN_X
    ADD  HL, DE
    LD   C, (HL)                ; C = col
    LD   HL, DG_DOOR_SCAN_Y
    ADD  HL, DE
    LD   B, (HL)                ; B = row
    LD   H, HIGH(DG_ROW_LO)
    LD   L, B
    LD   A, (HL)
    INC  H
    LD   H, (HL)
    ADD  A, C
    LD   L, A
    JR   NC, .pss_idx_ptr_ok
    INC  H
.pss_idx_ptr_ok:
    LD   A, (HL)
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_CLOSED
    JR   NZ, .pss_idx_next
    LD   A, (door_state_count)
    CP   MAX_DOOR_STATES
    JR   NC, .pss_idx_full
    LD   A, B
    LD   (dg_cur_row), A
    CALL dg_pss_roll_store
.pss_idx_next:
    POP  DE
    POP  BC
    INC  E
    DJNZ .pss_idx_lp
    RET
.pss_idx_full:
    POP  DE
    POP  BC
    RET

.pss_full_scan:
    ; Fallback row-major rescan if >= 128 closed doors
    LD   A, 1
.pss_row:
    LD   (dg_cur_row), A
    LD   B, A
    CALL dg_row_ptr_b
    INC  HL                     ; &map[row][1]
    LD   B, MAP_COLS - 2
.pss_col:
    LD   A, (HL)
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_CLOSED
    JR   Z, .pss_hit
.pss_next:
    INC  HL
    DJNZ .pss_col
    LD   A, (dg_cur_row)
    INC  A
    CP   MAP_ROWS - 1
    JR   C, .pss_row
    RET

.pss_hit:
    LD   A, (door_state_count)
    CP   MAX_DOOR_STATES
    RET  NC                     ; table full: remaining stay plain
    LD   A, MAP_COLS - 1
    SUB  B
    LD   C, A                   ; C = col
    PUSH HL
    PUSH BC
    CALL dg_pss_roll_store
    POP  BC
    POP  HL
    JR   .pss_next

; Input: C = col, (dg_cur_row) = row, (door_state_count) < MAX_DOOR_STATES.
; Rolls rng_range(120) and stores locked/stuck state if applicable.
dg_pss_roll_store:
    LD   A, 120
    CALL dg_rng_range
    CP   20
    JR   C, .locked
    CP   60
    RET  C
    CP   70
    RET  NC
    SUB  49
    OR   0x80
    JR   .store
.locked:
    SRL  A
    ADD  A, 11
.store:
    PUSH AF
    LD   A, (door_state_count)
    LD   E, A
    INC  A
    LD   (door_state_count), A
    LD   D, 0
    LD   HL, door_state_x
    ADD  HL, DE
    LD   (HL), C
    LD   BC, MAX_DOOR_STATES
    ADD  HL, BC                 ; door_state_y
    LD   A, (dg_cur_row)
    LD   (HL), A
    ADD  HL, BC                 ; door_state_val
    POP  AF
    LD   (HL), A
    RET

; ===========================================================================
; Stage 11: dg_darken_rooms — Clear FLAG_LIT inside dark rooms (room_lit == 0)
; ===========================================================================
dg_darken_rooms:
    LD   A, (room_count)
    OR   A
    RET  Z
    LD   C, 0                   ; C = room idx
.room_loop:
    LD   A, C
    LD   HL, room_lit
    CALL dg_idx_read
    OR   A
    JR   NZ, .next_room

    LD   A, C
    LD   HL, room_y
    CALL dg_idx_read
    DEC  A
    LD   B, A                   ; B = top wall row
    LD   A, C
    LD   HL, room_h
    CALL dg_idx_read
    ADD  A, 2
    LD   D, A                   ; D = total rows (room_h + 2)

    LD   A, C
    LD   HL, room_x
    CALL dg_idx_read
    DEC  A
    LD   (dg_dr_x0), A
    LD   A, C
    LD   HL, room_w
    CALL dg_idx_read
    ADD  A, 2
    LD   E, A                   ; E = total cols (room_w + 2)

.row_loop:
    PUSH DE
    CALL dg_row_ptr_b           ; HL = row base
    LD   A, (dg_dr_x0)
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    POP  DE
    PUSH BC
    LD   B, E
.col_loop:
    LD   A, (HL)
    AND  (~FLAG_LIT) & 0xFF
    LD   (HL), A
    INC  HL
    DJNZ .col_loop
    POP  BC
    INC  B
    DEC  D
    JR   NZ, .row_loop

.next_room:
    INC  C
    LD   A, (room_count)
    CP   C
    JR   NZ, .room_loop
    RET

; ===========================================================================
; Stage 12: dg_position_player_dungeon — Place player on stairs or fallback floor
; ===========================================================================
dg_position_player_dungeon:
    LD   A, (level_entry_dir)
    OR   A
    JR   NZ, .ascended
    LD   A, (stairs_up_x)
    LD   C, A
    LD   A, (stairs_up_y)
    LD   B, A
    JR   .validate
.ascended:
    LD   A, (stairs_dn1_x)
    LD   C, A
    LD   A, (stairs_dn1_y)
    LD   B, A

.validate:
    CALL dg_cs_in_bounds
    JR   NC, .fallback_room0
    CALL dg_read_bc
    JR   C, .fallback_room0
    AND  TILE_TYPE_MASK
    JR   Z, .pos_ok
    CP   TILE_STAIRS_DN
    JR   Z, .pos_ok
    CP   TILE_STAIRS_UP
    JR   Z, .pos_ok

.fallback_room0:
    LD   A, (room_count)
    OR   A
    JR   Z, .fallback_rnd
    LD   A, (room_x)
    LD   C, A
    LD   A, (room_y)
    LD   B, A
    CALL dg_read_bc
    JR   C, .fallback_rnd
    AND  TILE_TYPE_MASK
    JR   Z, .pos_ok
    CP   TILE_STAIRS_DN
    JR   Z, .pos_ok
    CP   TILE_STAIRS_UP
    JR   Z, .pos_ok

.fallback_rnd:
    CALL dg_find_random_floor
    JR   NC, .fallback_scan
    LD   A, (df_target_x)
    LD   C, A
    LD   A, (df_target_y)
    LD   B, A
    JR   .pos_ok

.fallback_scan:
    LD   A, 1
.fs_row:
    LD   (dg_cur_row), A
    LD   B, A
    CALL dg_row_ptr_b
    INC  HL                     ; &map[row][1]
    LD   B, MAP_COLS - 2
.fs_col:
    LD   A, (HL)
    AND  TILE_TYPE_MASK
    JR   Z, .fs_hit
    INC  HL
    DJNZ .fs_col
    LD   A, (dg_cur_row)
    INC  A
    CP   MAP_ROWS - 1
    JR   C, .fs_row
    LD   C, 1
    LD   B, 1
    JR   .pos_ok
.fs_hit:
    LD   A, MAP_COLS - 1
    SUB  B
    LD   C, A
    LD   A, (dg_cur_row)
    LD   B, A

.pos_ok:
    LD   A, C
    LD   (abi_player_x), A
    LD   (player_data + PL_MAP_X), A
    LD   A, B
    LD   (abi_player_y), A
    LD   (player_data + PL_MAP_Y), A

    LD   A, 0xFF
    LD   (vis_cached_room_idx), A
    JP   player_sync_to_abi

; ===========================================================================
; Tables & Local Scratch
; ===========================================================================
ovl_gen_store_pos_x:    DB 10, 22, 34, 46, 10, 22, 34, 46
ovl_gen_store_pos_y:    DB  2,  2,  2,  2, 12, 12, 12, 12
ovl_gen_store_door_x:   DB 15, 27, 39, 51, 15, 27, 39, 51
ovl_gen_store_door_y:   DB  6,  6,  6,  6, 16, 16, 16, 16

dg_slot_center_x:
    DB 16, 49, 82, 115, 148, 181
    DB 16, 49, 82, 115, 148, 181
    DB 16, 49, 82, 115, 148, 181
    DB 16, 49, 82, 115, 148, 181
    DB 16, 49, 82, 115, 148, 181
    DB 16, 49, 82, 115, 148, 181

dg_slot_center_y:
    DB  5,  5,  5,  5,  5,  5
    DB 16, 16, 16, 16, 16, 16
    DB 27, 27, 27, 27, 27, 27
    DB 38, 38, 38, 38, 38, 38
    DB 49, 49, 49, 49, 49, 49
    DB 60, 60, 60, 60, 60, 60

dg_rdt_table:
    DB TILE_SECRET | DUNGEON_FLAGS
    DB TILE_DOOR_OPEN | DUNGEON_FLAGS
    DB TILE_DOOR_CLOSED | DUNGEON_FLAGS

dg_cs_dx_table:         DB -1,  0,  1, -1,  1, -1,  0,  1
dg_cs_dy_table:         DB -1, -1, -1,  0,  0,  1,  1,  1
    ASSERT (dg_cs_dy_table - dg_cs_dx_table) == 8

dg_pjd_dx:              DB -1,  1,  0,  0
dg_pjd_dy:              DB  0,  0, -1,  1

ovl_gen_x0:             DB 0
ovl_gen_x1:             DB 0
ovl_gen_y0:             DB 0
ovl_gen_y1:             DB 0

dg_room_x:              DB 0
dg_room_y:              DB 0
dg_room_w:              DB 0
dg_room_h:              DB 0
dg_idx:                 DB 0
dg_retries:             DB 0
dg_slot_count:          DB 0
dg_slot_scan:           DB 0
dg_cx1:                 DB 0
dg_cy1:                 DB 0
dg_cx2:                 DB 0
dg_cy2:                 DB 0
dg_prev_x:              DB 0
dg_prev_y:              DB 0
dg_tun_dir:             DB 0
dg_conn_i:              DB 0
dg_stop_flag:           DB 0
dg_door_flag:           DB 0
dg_tun_steps:           DB 0
dg_tun_count:           DW 0
dg_scan_row_start:      DB 0
dg_scan_row_end:        DB 0
dg_scan_col_start:      DB 0
dg_scan_col_end:        DB 0
dg_scan_col_width:      DB 0
dg_cur_row:             DB 0
dg_open_mode:           DB 0
dg_tunnel_dirty:        DB 0
dg_mineral:             DB 0
dg_cs_dx:               DB 0
dg_cs_dy:               DB 0
dg_stair_room_idx:      DB 0
dg_jct_count:           DB 0
dg_door_scan_count:     DB 0
dg_door_orig_count:     DB 0
dg_dr_x0:               DB 0
ovl_gen_str_busy:       DB "GENERATING...", 0

ovl_end:
    ASSERT_OVL_FIT ovl_start, ovl_end

    SAVEBIN "ovl_gen.ovl", ovl_start, ovl_end - ovl_start
