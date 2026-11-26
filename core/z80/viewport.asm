; viewport.asm — 198x66 map accessors, deadband scrolling, Town store door lookup,
; and 78x18 ASCII dungeon/town viewport renderer (screen rows 2..19, cols 1..78).
;
; Resident core module included once by platforms/z80/cpm/main.asm.
; Uses pure 0xNN hex syntax for sjasmplus v1.24.0 (DEVICE NOSLOT64K).
; All public entry points preserve IX and IY.

    IFNDEF CORE_Z80_VIEWPORT_ASM
    DEFINE CORE_Z80_VIEWPORT_ASM 1

    EXPORT map_get_tile
    EXPORT map_set_tile
    EXPORT map_clear
    EXPORT store_door_lookup
    EXPORT store_door_x
    EXPORT store_door_y
    EXPORT viewport_center_on_player
    EXPORT viewport_render

; ============================================================
; _map_cell_ptr — Compute HL = MAP_BASE + B * 198 + C with bounds check.
; Input:  B = y (0..65), C = x (0..197)
; Output: CF = 0 & HL = cell ptr; CF = 1 if out of bounds
; Preserves: BC, DE, IX, IY (clobbers AF, HL)
; ============================================================
_map_cell_ptr:
    LD   A, B
    CP   MAP_ROWS
    JR   NC, .oob
    LD   A, C
    CP   MAP_COLS
    JR   NC, .oob
    PUSH BC
    PUSH DE
    ; 198 * y = (3 * y) * 64 + (3 * y) * 2
    LD   H, 0
    LD   L, B
    LD   D, H
    LD   E, L
    ADD  HL, HL                 ; 2*y
    ADD  HL, DE                 ; 3*y
    ADD  HL, HL                 ; 6*y (<= 390)
    PUSH HL                     ; [6*y]
    LD   B, 5
.sh:
    ADD  HL, HL
    DJNZ .sh                    ; 192*y
    POP  DE
    ADD  HL, DE                 ; 198*y
    LD   D, 0
    LD   E, C                   ; + x
    ADD  HL, DE
    LD   DE, MAP_BASE
    ADD  HL, DE
    POP  DE
    POP  BC
    OR   A                      ; CF = 0
    RET
.oob:
    SCF
    RET

; ============================================================
; map_get_tile — Bounds-checked read at (B=y, C=x).
; Output: A = tile byte (TILE_WALL_H if out of bounds), CF = 1 if OOB
; Preserves: BC, DE, HL, IX, IY
; ============================================================
map_get_tile:
    PUSH HL
    CALL _map_cell_ptr
    JR   C, .oob
    LD   A, (HL)
    POP  HL
    OR   A
    RET
.oob:
    POP  HL
    LD   A, TILE_WALL_H
    SCF
    RET

; ============================================================
; map_set_tile — Bounds-checked write A at (B=y, C=x) (no-op if OOB).
; Preserves: AF, BC, DE, HL, IX, IY
; ============================================================
map_set_tile:
    PUSH HL
    PUSH DE
    PUSH AF
    CALL _map_cell_ptr
    JR   C, .oob
    EX   DE, HL
    POP  AF
    LD   (DE), A
    POP  DE
    POP  HL
    RET
.oob:
    POP  AF
    POP  DE
    POP  HL
    RET

; ============================================================
; map_clear — Fill entire 198x66 MAP_BASE (13,068 B) with byte A.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
map_clear:
    LD   HL, MAP_BASE
    LD   DE, MAP_BASE + 1
    LD   BC, MAP_SIZE - 1
    LD   (HL), A
    LDIR
    RET

; ============================================================
; store_door_lookup — Check whether map cell (B=y, C=x) is a Town store/home door.
; Input:  B = map y, C = map x
; Output: CF = 1 & A = building index (0..6 stores, 7 Home); CF = 0 if none
; Preserves: BC, IX, IY (clobbers AF, DE, HL)
; ============================================================
store_door_lookup:
    LD   HL, store_door_x
    LD   DE, store_door_y
    PUSH BC
    LD   B, STORE_COUNT
    LD   A, 0                   ; store index 0..7
.lp:
    PUSH AF
    LD   A, (HL)
    CP   C
    JR   NZ, .next
    ; Check y (caller's B is at SP+2 -> peek or swap)
    PUSH HL
    LD   HL, 5
    ADD  HL, SP
    LD   A, (HL)                ; caller B (y)
    POP  HL
    EX   DE, HL
    CP   (HL)
    EX   DE, HL
    JR   Z, .hit
.next:
    POP  AF
    INC  A
    INC  HL
    INC  DE
    DJNZ .lp
    POP  BC
    OR   A
    RET
.hit:
    POP  AF
    POP  BC
    SCF
    RET

store_door_x: DB 15, 27, 39, 51, 15, 27, 39, 51
store_door_y: DB  6,  6,  6,  6, 16, 16, 16, 16

; ============================================================
; viewport_center_on_player — Update abi_view_x/y using C128 78x18 deadband policy.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
viewport_center_on_player:
    ; Horizontal deadband: [view_x + 12 .. view_x + 65]
    LD   A, (abi_view_x)
    ADD  A, VIEW_SCROLL_MARGIN_X
    LD   B, A
    LD   A, (abi_player_x)
    CP   B
    JR   NC, .chk_right
    ; Player left of left deadband
    SUB  VIEW_SCROLL_MARGIN_X
    JR   NC, .store_vx
    XOR  A
    JR   .store_vx
.chk_right:
    LD   A, (abi_view_x)
    ADD  A, VIEW_COLS - 1 - VIEW_SCROLL_MARGIN_X
    LD   B, A
    LD   A, (abi_player_x)
    CP   B
    JR   C, .vy_chk
    JR   Z, .vy_chk
    SUB  VIEW_COLS - 1 - VIEW_SCROLL_MARGIN_X
    CP   MAP_COLS - VIEW_COLS
    JR   C, .store_vx
    LD   A, MAP_COLS - VIEW_COLS
.store_vx:
    LD   (abi_view_x), A

.vy_chk:
    ; Vertical deadband: [view_y + 4 .. view_y + 13]
    LD   A, (abi_view_y)
    ADD  A, VIEW_SCROLL_MARGIN_Y
    LD   B, A
    LD   A, (abi_player_y)
    CP   B
    JR   NC, .chk_bot
    SUB  VIEW_SCROLL_MARGIN_Y
    JR   NC, .store_vy
    XOR  A
    JR   .store_vy
.chk_bot:
    LD   A, (abi_view_y)
    ADD  A, VIEW_ROWS - 1 - VIEW_SCROLL_MARGIN_Y
    LD   B, A
    LD   A, (abi_player_y)
    CP   B
    JR   C, .done
    JR   Z, .done
    SUB  VIEW_ROWS - 1 - VIEW_SCROLL_MARGIN_Y
    CP   MAP_ROWS - VIEW_ROWS
    JR   C, .store_vy
    LD   A, MAP_ROWS - VIEW_ROWS
.store_vy:
    LD   (abi_view_y), A
.done:
    RET

; ============================================================
; viewport_render — Draw 78x18 viewport at screen cols 1..78, rows 2..19.
; Steps cpm_char_shadow (HL), cpm_color_shadow (BC), and map (DE) sequentially
; without IX/IY or per-cell _screen_calc_row_offset, and bypasses glyph scan
; when glyph_active[0..3] are all zero.
; Preserves: IX, IY (clobbers AF, BC, DE, HL)
; ============================================================
viewport_render:
    ; Clamp abi_view_x <= 120, abi_view_y <= 48 defensively
    LD   A, (abi_view_x)
    CP   MAP_COLS - VIEW_COLS + 1
    JR   C, .vx_ok
    LD   A, MAP_COLS - VIEW_COLS
    LD   (abi_view_x), A
.vx_ok:
    LD   A, (abi_view_y)
    CP   MAP_ROWS - VIEW_ROWS + 1
    JR   C, .vy_ok
    LD   A, MAP_ROWS - VIEW_ROWS
    LD   (abi_view_y), A
.vy_ok:
    ; Pre-check glyph_active[0..3] ONCE per frame
    LD   HL, glyph_active
    LD   A, (HL)
    INC  HL
    OR   (HL)
    INC  HL
    OR   (HL)
    INC  HL
    OR   (HL)
    LD   (vr_any_glyph), A

    ; Pre-check whether player '@' lies inside viewport, and snapshot pre-loop cell state
    ; so stationary '@' keeps its prior dirty flag and never triggers spurious terminal redraws.
    XOR  A
    LD   (vr_pl_in_view), A
    LD   A, (abi_view_x)
    LD   B, A
    LD   A, (abi_player_x)
    SUB  B
    JR   C, .pl_pre_done
    CP   VIEW_COLS
    JR   NC, .pl_pre_done
    LD   C, A                   ; C = dx (0..77)
    LD   A, (abi_view_y)
    LD   B, A
    LD   A, (abi_player_y)
    SUB  B
    JR   C, .pl_pre_done
    CP   VIEW_ROWS
    JR   NC, .pl_pre_done
    ADD  A, VIEWPORT_Y          ; A = screen row (2..19)
    LD   L, A
    LD   H, 0
    ADD  HL, HL                 ; *2
    ADD  HL, HL                 ; *4
    ADD  HL, HL                 ; *8
    ADD  HL, HL                 ; *16
    LD   E, L
    LD   D, H
    ADD  HL, HL                 ; *32
    ADD  HL, HL                 ; *64
    ADD  HL, DE                 ; *80
    LD   A, C
    ADD  A, VIEWPORT_X          ; col (1..78)
    LD   E, A
    LD   D, 0
    ADD  HL, DE
    LD   DE, CPM_CHAR_SHADOW_BASE
    ADD  HL, DE
    LD   (vr_pl_char_ptr), HL
    LD   A, 1
    LD   (vr_pl_in_view), A
    LD   A, (HL)
    CP   CH_PLAYER
    JR   NZ, .pl_diff
    LD   DE, CPM_CHAR_SHADOW_SIZE
    ADD  HL, DE
    LD   A, (HL)
    LD   B, A
    AND  0x7F
    CP   COL_WHITE
    JR   NZ, .pl_diff
    LD   A, B
    LD   (vr_pl_old_attr), A
    LD   A, 1
    JR   .pl_set_same
.pl_diff:
    XOR  A
.pl_set_same:
    LD   (vr_pl_same), A
.pl_pre_done:

    ; Compute initial map slice pointer ONCE and fixed screen shadow base at row 2 col 0
    LD   A, (abi_view_y)
    LD   (vr_map_y), A
    LD   B, A
    LD   A, (abi_view_x)
    LD   C, A
    CALL _map_cell_ptr          ; HL = MAP_BASE + view_y * 198 + view_x
    EX   DE, HL                 ; DE = map_ptr
    LD   HL, CPM_CHAR_SHADOW_BASE + (VIEWPORT_Y * SCREEN_COLS)
    LD   BC, CPM_COLOR_SHADOW_BASE + (VIEWPORT_Y * SCREEN_COLS)
    LD   A, VIEW_ROWS
    LD   (vr_rows_rem), A

.row_loop:
    CALL _vr_emit_blank_step    ; col 0 left border -> steps HL, BC to col 1
    LD   (vr_row_map_ptr), DE
    LD   A, E
    ADD  A, VIEW_COLS
    LD   (vr_end_e), A

.col_loop:
    LD   A, (DE)
    BIT  2, A                   ; FLAG_VISITED
    JR   NZ, .visited

    ; Unvisited cell
    BIT  0, A                   ; FLAG_OCCUPIED
    JR   NZ, .unvis_mon
.emit_blank:
    LD   A, ' '
    CP   (HL)
    JR   NZ, .wr_blank
    LD   A, (BC)
    AND  0x7F                   ; COL_BLACK == 0
    JR   Z, .next_cell
    LD   A, COL_BLACK | CPM_ATTR_DIRTY
    LD   (BC), A
    JR   .next_cell
.wr_blank:
    LD   (HL), A
    LD   A, COL_BLACK | CPM_ATTR_DIRTY
    LD   (BC), A
.next_cell:
    INC  HL
    INC  BC
    INC  DE
    LD   A, (vr_end_e)
    CP   E
    JP   NZ, .col_loop

    ; End of row: col 79 right border -> steps HL, BC to col 0 of next row
    CALL _vr_emit_blank_step
    PUSH HL
    LD   HL, MAP_COLS - VIEW_COLS
    ADD  HL, DE
    EX   DE, HL
    POP  HL
    LD   A, (vr_map_y)
    INC  A
    LD   (vr_map_y), A
    LD   A, (vr_rows_rem)
    DEC  A
    LD   (vr_rows_rem), A
    JP   NZ, .row_loop

    ; Post-pass: draw '@' if inside viewport
    LD   A, (vr_pl_in_view)
    OR   A
    JR   Z, .clear_dirty
    LD   HL, (vr_pl_char_ptr)
    LD   (HL), CH_PLAYER
    LD   DE, CPM_CHAR_SHADOW_SIZE
    ADD  HL, DE
    LD   A, (vr_pl_same)
    OR   A
    JR   NZ, .restore_pl_attr
    LD   (HL), COL_WHITE | CPM_ATTR_DIRTY
    JR   .clear_dirty
.restore_pl_attr:
    LD   A, (vr_pl_old_attr)
    LD   (HL), A
.clear_dirty:
    LD   A, (zp_ui_dirty)
    AND  0xFF ^ UI_DIRTY_MAP
    LD   (zp_ui_dirty), A
    RET

.unvis_mon:
    PUSH DE
    PUSH HL
    PUSH BC
    CALL _vr_cur_map_yx         ; sets B=map_y, C=map_x & saves vr_tmp_x
    CALL _vr_find_monster       ; CF=1 -> A=char, E=color
    JP   C, .vis_emit
    POP  BC
    POP  HL
    POP  DE
    JR   .emit_blank

.visited:
    ; Fast path for plain lit Town/room floor (TILE_FLOOR | TOWN_FLAGS = 0x0C) when no glyphs
    CP   TILE_FLOOR | TOWN_FLAGS
    JR   NZ, .vis_general
    LD   A, (vr_any_glyph)
    OR   A
    JR   Z, .vis_0c_fast
    LD   A, TILE_FLOOR | TOWN_FLAGS
    JR   .vis_general

.vis_0c_fast:
    LD   A, '.'
    CP   (HL)
    JR   NZ, .wr_0c_ch
    LD   A, (BC)
    AND  0x7F
    CP   COL_DGREY
    JP   Z, .next_cell
    LD   A, COL_DGREY | CPM_ATTR_DIRTY
    LD   (BC), A
    JP   .next_cell
.wr_0c_ch:
    LD   (HL), A
    LD   A, COL_DGREY | CPM_ATTR_DIRTY
    LD   (BC), A
    JP   .next_cell

.vis_general:
    PUSH DE                     ; [map_ptr]
    PUSH HL                     ; [char_ptr]
    PUSH BC                     ; [color_ptr]
    LD   (vr_cur_cell), A
    LD   HL, vr_row_map_ptr
    LD   A, E
    SUB  (HL)
    LD   HL, abi_view_x
    ADD  A, (HL)
    LD   (vr_tmp_x), A          ; vr_tmp_x = map_x

    LD   A, (vr_cur_cell)
    LD   D, A
    AND  0xF0
    RRCA
    RRCA
    RRCA                        ; A = tile_type * 2 (0..30)
    CP   14
    JR   NC, .normal_tile
    OR   A
    JR   Z, .normal_tile
    BIT  3, D                   ; FLAG_LIT
    JR   NZ, .normal_tile
    LD   A, '#'
    LD   E, COL_LGREY
    JR   .after_tile

.normal_tile:
    ADD  A, low _vr_tile_pairs
    LD   L, A
    ADC  A, high _vr_tile_pairs
    SUB  L
    LD   H, A
    LD   A, (HL)                ; terrain char
    INC  HL
    LD   E, (HL)                ; terrain color
    LD   B, A                   ; save terrain char
    LD   A, D
    AND  TILE_TYPE_MASK
    CP   TILE_DOOR_OPEN
    JR   NZ, .restore_ch
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .restore_ch
    PUSH BC
    PUSH DE
    CALL _vr_load_yx
    CALL store_door_lookup      ; CF=1 -> A=0..7
    POP  DE
    POP  BC
    JR   NC, .restore_ch
    ADD  A, '1'
    LD   E, COL_YELLOW
    JR   .after_tile
.restore_ch:
    LD   A, B

.after_tile:
    LD   HL, vr_cur_cell
    BIT  3, (HL)                ; FLAG_LIT
    JR   NZ, .vis_ok
    PUSH AF
    PUSH DE
    CALL _vr_load_yx
    CALL _vr_in_light
    POP  DE
    JR   C, .lit_pop
    POP  AF
    LD   E, COL_DGREY           ; dimmed terrain
    JR   .chk_monster
.lit_pop:
    POP  AF

.vis_ok:
    LD   HL, vr_cur_cell
    BIT  1, (HL)                ; FLAG_HAS_ITEM
    JR   Z, .chk_glyph
    PUSH AF
    PUSH DE
    CALL _vr_load_yx
    CALL _vr_find_item
    JR   C, .item_hit
    POP  DE
    POP  AF
    JR   .chk_glyph
.item_hit:
    POP  HL
    POP  HL

.chk_glyph:
    LD   H, A
    LD   A, (vr_any_glyph)
    OR   A
    LD   A, H
    JR   Z, .chk_monster
    PUSH AF
    PUSH DE
    CALL _vr_load_yx
    CALL _vr_check_glyph
    JR   C, .glyph_hit
    POP  DE
    POP  AF
    JR   .chk_monster
.glyph_hit:
    POP  HL
    POP  HL

.chk_monster:
    LD   HL, vr_cur_cell
    BIT  0, (HL)                ; FLAG_OCCUPIED
    JR   Z, .vis_emit
    PUSH AF
    PUSH DE
    CALL _vr_load_yx
    CALL _vr_find_monster
    JR   C, .mon_hit
    POP  DE
    POP  AF
    JR   .vis_emit
.mon_hit:
    POP  HL
    POP  HL

.vis_emit:
    POP  BC                     ; color_ptr
    POP  HL                     ; char_ptr
    CP   (HL)
    JR   NZ, .ve_ch_diff
    LD   A, (BC)
    AND  0x7F
    CP   E
    JR   Z, .ve_pop_de
    LD   A, E
    OR   CPM_ATTR_DIRTY
    LD   (BC), A
    JR   .ve_pop_de
.ve_ch_diff:
    LD   (HL), A
    LD   A, E
    OR   CPM_ATTR_DIRTY
    LD   (BC), A
.ve_pop_de:
    POP  DE                     ; map_ptr
    JP   .next_cell

; Write (' ', COL_BLACK) at (HL)/(BC) if changed and advance both pointers by 1.
_vr_emit_blank_step:
    LD   A, ' '
    CP   (HL)
    JR   NZ, .wr
    LD   A, (BC)
    AND  0x7F
    JR   Z, .step
    LD   A, COL_BLACK | CPM_ATTR_DIRTY
    LD   (BC), A
    JR   .step
.wr:
    LD   (HL), A
    LD   A, COL_BLACK | CPM_ATTR_DIRTY
    LD   (BC), A
.step:
    INC  HL
    INC  BC
    RET

; Load (vr_map_y, vr_tmp_x) -> (B=y, C=x). Preserves DE, IX, IY.
_vr_load_yx:
    LD   A, (vr_map_y)
    LD   B, A
    LD   A, (vr_tmp_x)
    LD   C, A
    RET

; Compute (B=y, C=x) from DE=map_ptr and save vr_tmp_x. Preserves DE, IX, IY.
_vr_cur_map_yx:
    LD   A, (vr_row_map_ptr)
    LD   C, A
    LD   A, E
    SUB  C
    LD   C, A
    LD   A, (abi_view_x)
    ADD  A, C
    LD   (vr_tmp_x), A
    LD   C, A
    LD   A, (vr_map_y)
    LD   B, A
    RET

; Check Chebyshev distance max(|C - px|, |B - py|) <= abi_light_rad -> CF = 1.
; Clobbers A, H (preserves BC, DE, L, IX, IY).
_vr_in_light:
    LD   A, (abi_player_x)
    SUB  C
    JR   NC, .dx_ok
    NEG
.dx_ok:
    LD   H, A
    LD   A, (abi_player_y)
    SUB  B
    JR   NC, .dy_ok
    NEG
.dy_ok:
    CP   H
    JR   NC, .have_max
    LD   A, H
.have_max:
    LD   H, A
    LD   A, (abi_light_rad)
    CP   H
    JR   NC, .lit_yes
    OR   A
    RET
.lit_yes:
    SCF
    RET

; Scan fi_item_id[0..41] for item at (B=y, C=x). CF=1 -> A=char, E=color.
_vr_find_item:
    LD   A, B
    LD   (vr_map_y), A
    LD   A, C
    LD   (vr_tmp_x), A
    LD   C, 0
    LD   B, MAX_FLOOR_ITEMS
.lp:
    PUSH BC
    LD   B, 0
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    CP   FI_EMPTY
    JR   Z, .next
    LD   DE, MAX_FLOOR_ITEMS
    ADD  HL, DE                 ; fi_x
    LD   A, (vr_tmp_x)
    CP   (HL)
    JR   NZ, .next
    ADD  HL, DE                 ; fi_y
    LD   A, (vr_map_y)
    CP   (HL)
    JR   NZ, .next
    LD   HL, fi_meta_hi
    ADD  HL, BC
    LD   A, (HL)
    AND  ITEM_PAGE_BIT
    LD   (item_cur_page), A
    LD   HL, fi_item_id
    ADD  HL, BC
    LD   A, (HL)
    LD   C, A
    CALL item_get_display_char_a
    PUSH AF
    LD   A, C
    CALL item_get_floor_color_a
    LD   E, A
    POP  AF
    POP  BC
    SCF
    RET
.next:
    POP  BC
    INC  C
    DJNZ .lp
    OR   A
    RET

; Check glyph_active[0..3] at (B=y, C=x). CF=1 -> A=CH_GLYPH, E=COL_WHITE.
_vr_check_glyph:
    LD   A, B
    LD   (vr_map_y), A
    LD   A, C
    LD   (vr_tmp_x), A
    LD   C, 0
.glp:
    LD   B, 0
    LD   HL, glyph_active
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   Z, .gnxt
    LD   HL, glyph_x
    ADD  HL, BC
    LD   A, (vr_tmp_x)
    CP   (HL)
    JR   NZ, .gnxt
    LD   HL, glyph_y
    ADD  HL, BC
    LD   A, (vr_map_y)
    CP   (HL)
    JR   NZ, .gnxt
    LD   E, COL_WHITE
    LD   A, CH_GLYPH
    SCF
    RET
.gnxt:
    INC  C
    LD   A, C
    CP   MAX_GLYPHS
    JR   C, .glp
    OR   A
    RET

; Scan monster_table[0..31] for visible/detected monster at (B=y, C=x).
; CF=1 -> A=char, E=color.
_vr_find_monster:
    LD   A, B
    LD   (vr_map_y), A
    LD   A, C
    LD   (vr_tmp_x), A
    LD   HL, monster_table
    LD   B, MAX_MONSTERS
.lp:
    LD   A, (vr_tmp_x)
    CP   (HL)                   ; MX_X
    JR   NZ, .next
    INC  HL
    LD   A, (vr_map_y)
    CP   (HL)                   ; MX_Y
    DEC  HL
    JR   NZ, .next
    LD   DE, 5                  ; MX_FLAGS
    ADD  HL, DE
    LD   A, (HL)
    AND  0x18                   ; MF_VISIBLE (0x08) | MF_DETECTED (0x10)
    JR   Z, .skip_m5
    DEC  HL
    DEC  HL
    DEC  HL                     ; MX_TYPE
    LD   C, (HL)
    LD   A, C
    CP   MAX_CREATURES
    JR   NC, .bad
    LD   B, 0
    LD   HL, cr_display
    ADD  HL, BC
    LD   A, (HL)
    OR   A
    JR   Z, .bad
    LD   HL, cr_color
    ADD  HL, BC
    LD   E, (HL)
    SCF
    RET
.skip_m5:
    LD   DE, 0xFFFB             ; -5 back to MX_X
    ADD  HL, DE
.next:
    LD   DE, MONSTER_ENTRY_SIZE
    ADD  HL, DE
    DJNZ .lp
.bad:
    OR   A
    RET

; Interleaved (char, color) pairs for tiles 0..15 (matching core/6502/color.s)
_vr_tile_pairs:
    DB   '.', COL_DGREY,  '#', COL_LGREY,  '#', COL_LGREY,  '#', COL_LGREY
    DB   '#', COL_LGREY,  '#', COL_LGREY,  '#', COL_LGREY,  0x27, COL_BROWN
    DB   '+', COL_BROWN,  '>', COL_WHITE,  '<', COL_WHITE,  ':', COL_GREY
    DB   '%', COL_RED,    '%', COL_WHITE,  '^', COL_RED,    '#', COL_LGREY

    ENDIF
