; los.asm — Resident Z80 Line-of-Sight & Dungeon Visibility (M3)
;
; Exports: los_check, los_update_visibility
; Preserves IX and IY across every public entry point.

    EXPORT los_check
    EXPORT los_update_visibility

; ------------------------------------------------------------
; los_check — Major-axis integer Bresenham LOS trace from (C,B) to (E,D)
; Input:  B = y0, C = x0, D = y1, E = x1
; Output: CF = 1 clear, CF = 0 blocked. Preserves BC, DE, IX, IY.
; ------------------------------------------------------------
los_check:
    LD   A, B
    CP   MAP_ROWS
    RET  NC
    LD   A, D
    CP   MAP_ROWS
    RET  NC
    LD   A, C
    CP   MAP_COLS
    RET  NC
    LD   A, E
    CP   MAP_COLS
    RET  NC

.ok_b:
    LD   A, B
    CP   D
    JR   NZ, .ns
    LD   A, C
    CP   E
    JR   NZ, .ns
    SCF
    RET

.ns:
    PUSH IX
    PUSH BC
    PUSH DE

    LD   A, E
    SUB  C
    LD   L, 1
    JR   NC, .dxp
    NEG
    LD   L, 0xFF
.dxp:
    LD   H, A                   ; H=dx, L=sx

    LD   A, D
    SUB  B
    LD   E, 1
    JR   NC, .dyp
    NEG
    LD   E, 0xFF
.dyp:
    LD   D, A                   ; D = ady, E = sdy
    CP   H
    JR   NC, .have_steps
    LD   A, H                   ; A = steps = max(adx, ady)
.have_steps:
    PUSH DE                     ; (IX+7)=ady, (IX+6)=sdy
    PUSH HL                     ; (IX+5)=adx, (IX+4)=sdx
    LD   H, A
    LD   L, 0
    PUSH HL                     ; (IX+3)=steps, (IX+2)=err_y (0)
    LD   H, L
    LD   L, A
    PUSH HL                     ; (IX+1)=err_x (0), (IX+0)=rem_steps
    LD   IX, 0
    ADD  IX, SP

.step_lp:
    LD   D, B                   ; D = old_y
    LD   E, C                   ; E = old_x

    LD   A, (IX+1)              ; err_x += adx
    ADD  A, (IX+5)
    JR   C, .sub_x
    CP   (IX+3)
    JR   C, .no_x
.sub_x:
    SUB  (IX+3)
    LD   (IX+1), A
    LD   A, C
    ADD  A, (IX+4)              ; cx += sdx
    LD   C, A
    JR   .do_y
.no_x:
    LD   (IX+1), A

.do_y:
    LD   A, (IX+2)              ; err_y += ady
    ADD  A, (IX+7)
    JR   C, .sub_y
    CP   (IX+3)
    JR   C, .no_y
.sub_y:
    SUB  (IX+3)
    LD   (IX+2), A
    LD   A, B
    ADD  A, (IX+6)              ; cy += sdy
    LD   B, A
    JR   .diag
.no_y:
    LD   (IX+2), A

.diag:
    LD   A, C
    CP   E
    JR   Z, .chk_tgt
    LD   A, B
    CP   D
    JR   Z, .chk_tgt
    PUSH BC
    LD   B, D                   ; check (old_y, cx)
    CALL _los_is_transparent
    POP  BC
    JR   C, .chk_tgt
    PUSH BC
    LD   C, E                   ; check (cy, old_x)
    CALL _los_is_transparent
    POP  BC
    JR   NC, .blocked

.chk_tgt:
    LD   A, C
    CP   (IX+8)                 ; cx == x1?
    JR   NZ, .chk_tile
    LD   A, B
    CP   (IX+9)                 ; cy == y1?
    JR   Z, .clear

.chk_tile:
    CALL _los_is_transparent
    JR   NC, .blocked
    DEC  (IX+0)
    JR   NZ, .step_lp

.clear:
    SCF
    JR   .exit
.blocked:
    OR   A
.exit:
    POP  HL
    POP  HL
    POP  HL
    POP  HL
    POP  DE
    POP  BC
    POP  IX
    RET

_los_is_transparent:
    CALL map_get_tile
    JR   C, .op
    AND  TILE_TYPE_MASK
    RRCA
    RRCA
    RRCA
    RRCA
    PUSH BC
    LD   C, 0x81                ; bits 0 (FLOOR), 7 (DOOR_OPEN)
    BIT  3, A
    JR   Z, .lo
    LD   C, 0x4E                ; bits 9 (STAIRS_DN), 10 (STAIRS_UP), 11 (RUBBLE), 14 (TRAP)
.lo:
    AND  7
    INC  A
    LD   B, A
    LD   A, C
.sh:
    RRCA
    DJNZ .sh
    POP  BC
    RET
.op:
    OR   A
    RET

; ------------------------------------------------------------
; los_update_visibility — Update FLAG_VISITED around player & lit rooms
; Uses bss_scratch + 0..5. Never modifies IX or IY.
; ------------------------------------------------------------
los_update_visibility:
    LD   A, (zp_eff_blind)
    OR   A
    JR   NZ, .no_cache
    LD   A, (abi_player_dlvl)
    OR   A
    JR   NZ, .in_dng
.no_cache:
    LD   A, 0xFF
    LD   (vis_cached_room_idx), A
    RET

.in_dng:
    ; Effective radius C (0..4): 0 if light equipped and burnt out
    LD   A, (inv_item_id + EQUIP_LIGHT)
    INC  A                      ; FI_EMPTY (0xFF)?
    JR   Z, .rc
    LD   A, (inv_p1 + EQUIP_LIGHT)
    OR   A
    JR   Z, .rok                ; burnt out -> C = 0
.rc:
    LD   A, (abi_light_rad)
    CP   5
    JR   C, .rok
    LD   A, 4
.rok:
    LD   C, A

    ; Phase A: Mark Chebyshev box [px-rad..px+rad] x [py-rad..py+rad] as FLAG_VISITED
    LD   DE, (abi_player_x)     ; E=px, D=py
    LD   B, E
    LD   E, C
    LD   HL, bss_scratch
    LD   A, MAP_COLS - 1
    CALL _los_clamp_to_hl
    LD   B, D
    LD   A, MAP_ROWS - 1
    CALL _los_clamp_to_hl

    LD   A, (bss_scratch + 2)
    LD   D, A                   ; cur_y = y0
.dy_lp:
    LD   A, (bss_scratch + 0)
    LD   E, A
.dx_lp:
    LD   B, D
    LD   C, E
    CALL _los_mark_visited
    LD   A, (bss_scratch + 1)
    CP   E
    JR   Z, .nx_dy
    INC  E
    JR   .dx_lp
.nx_dy:
    LD   A, (bss_scratch + 3)
    CP   D
    JR   Z, .phase_b
    INC  D
    JR   .dy_lp

.phase_b:
    LD   BC, (abi_player_x)     ; C=px, B=py
    CALL map_get_tile           ; B=py, C=px
    JR   C, .no_rm
    AND  FLAG_LIT
    JR   Z, .no_rm

    LD   A, (vis_cached_room_idx)
    LD   HL, room_count
    CP   (HL)
    JR   NC, .scan_rms
    CALL _los_in_room_a
    RET  C

.scan_rms:
    LD   A, (room_count)
    OR   A
    JR   Z, .no_rm
    LD   B, A
    LD   C, 0
.rm_lp:
    LD   A, C
    CALL _los_in_room_a
    JR   C, .reveal_c
    INC  C
    DJNZ .rm_lp
.no_rm:
    JP   .no_cache

.reveal_c:
    LD   A, C
    LD   (vis_cached_room_idx), A
    LD   HL, (bss_scratch + 0)  ; L=x0, H=x1
    LD   DE, (bss_scratch + 2)  ; E=y0, D=y1
    LD   B, E
.ry_lp:
    LD   C, L
.rx_lp:
    CALL _los_mark_visited
    JR   Z, .rx_nx
    LD   (vis_room_revealed), A ; non-zero (tile | FLAG_VISITED)
.rx_nx:
    LD   A, C
    CP   H
    JR   Z, .ry_nx
    INC  C
    JR   .rx_lp
.ry_nx:
    LD   A, B
    CP   D
    RET  Z
    INC  B
    JR   .ry_lp

_los_idx_hl_a:
    ADD  A, L
    LD   L, A
    JR   NC, .nc
    INC  H
.nc:
    LD   A, (HL)
    RET

_los_mark_visited:
    CALL map_get_tile
    JR   C, .alr
    BIT  2, A
    JR   NZ, .alr
    OR   FLAG_VISITED
    JP   map_set_tile           ; preserves AF: A!=0 & Z=0 because FLAG_VISITED!=0
.alr:
    XOR  A
    RET

; Check room A lit & player inside [rx..rx+rw) x [ry..ry+rh); on match clamp [rx-1..rx+rw] x [ry-1..ry+rh] -> bss_scratch+0..3.
; Preserves BC.
_los_in_room_a:
    LD   E, A
    LD   D, 0
    LD   HL, room_lit
    ADD  HL, DE
    LD   A, (HL)
    OR   A
    RET  Z                      ; unlit room -> fast exit CF=0

    PUSH BC
    LD   HL, room_x
    ADD  HL, DE
    LD   DE, MAX_ROOMS
    LD   B, (HL)                ; rx
    ADD  HL, DE
    LD   C, (HL)                ; ry
    ADD  HL, DE                 ; HL = &room_w[i]
    LD   A, (abi_player_x)
    SUB  B
    JR   C, .no
    CP   (HL)                   ; x - rx < rw?
    JR   NC, .no
    ADD  HL, DE                 ; HL = &room_h[i]
    LD   A, (abi_player_y)
    SUB  C
    JR   C, .no
    CP   (HL)                   ; y - ry < rh?
    JR   NC, .no

    LD   A, (HL)                ; rh
    OR   A
    SBC  HL, DE
    LD   E, (HL)                ; rw
    LD   D, A                   ; preserve rh across clamp
    PUSH BC                     ; save C = ry
    LD   C, 1
    LD   HL, bss_scratch
    LD   A, MAP_COLS - 1
    CALL _los_clamp_to_hl
    POP  BC                     ; C = ry
    LD   E, D                   ; rh
    LD   B, C                   ; ry
    LD   C, 1
    LD   A, MAP_ROWS - 1
    CALL _los_clamp_to_hl
    POP  BC
    SCF
    RET
.no:
    POP  BC
    OR   A
    RET

; [B - C .. B + E] clamped to [0 .. A] -> store lo, hi at (HL), advance HL+=2. Preserves DE, C.
_los_clamp_to_hl:
    PUSH DE
    LD   D, A
    LD   A, B
    SUB  C
    JR   NC, .lo
    XOR  A
.lo:
    LD   (HL), A
    INC  HL
    LD   A, B
    ADD  A, E
    JR   C, .hc
    CP   D
    JR   C, .ho
.hc:
    LD   A, D
.ho:
    LD   (HL), A
    INC  HL
    POP  DE
    RET
