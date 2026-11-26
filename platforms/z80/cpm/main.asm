; main.asm — Resident CP/M 2.2 Z80 entrypoint, TPA guard, HAL/Core, and RO tables.
;
; Authority: docs/CPM_MEMORY_CONTRACT.md.
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax, DEVICE NOSLOT64K).
; Build outputs into build/cpm/ via --outprefix=$(ABSOUTCPM)/.

    DEVICE NOSLOT64K

    INCLUDE "memory.inc"
    INCLUDE "defs.inc"
    INCLUDE "dat_toc.inc"
    INCLUDE "version_z80.inc"

    ORG  RESIDENT_BASE          ; 0x0100

    EXPORT resident_start
resident_start:
    ; ------------------------------------------------------------------
    ; Phase 1: Parse CP/M CLI tail at 0x0080 BEFORE touching >= 0x5600,
    ; changing BDOS DMA, or moving SP.
    ; ------------------------------------------------------------------
    CALL parse_cli_tail

    ; ------------------------------------------------------------------
    ; Phase 2: 52 KB TPA ceiling check via Page Zero BDOS vector (0x0006).
    ; If HL < 0xD100, keep CCP stack intact, print error via BDOS 9, exit.
    ; ------------------------------------------------------------------
    LD   HL, (CPM_BDOS_VEC)
    LD   A, H
    CP   HIGH(BDOS_MIN_TOP)
    JR   NC, .tpa_ok

    LD   C, BDOS_PRTSTR
    LD   DE, str_insufficient_tpa
    CALL CPM_BDOS_ENTRY
    LD   C, BDOS_TERM
    LD   DE, 0
    CALL CPM_BDOS_ENTRY
    JP   CPM_WARM_BOOT

.tpa_ok:
    ; ------------------------------------------------------------------
    ; Phase 3: Switch SP to STACK_TOP (0x8E00) and plant 4-byte stack canary.
    ; ------------------------------------------------------------------
    LD   SP, STACK_TOP
    LD   HL, stack_canary_bytes
    LD   DE, STACK_CANARY_ADDR
    LD   BC, STACK_CANARY_LEN
    LDIR

    ; ------------------------------------------------------------------
    ; Phase 4: Zero-fill entire resident BSS (0x6A00..bss_end-1) via LDIR.
    ; ------------------------------------------------------------------
    LD   HL, BSS_BASE
    LD   DE, BSS_BASE + 1
    LD   BC, bss_end - BSS_BASE - 1
    LD   (HL), 0
    LDIR

    ; ------------------------------------------------------------------
    ; Phase 5: Initialize fixed z80_state ABI block (0x6A00..0x6A3F).
    ; ------------------------------------------------------------------
    LD   HL, abi_magic_bytes
    LD   DE, z80_state + Z80_ABI_MAGIC
    LD   BC, 4
    LDIR

    LD   A, Z80_ABI_VERSION_NUM
    LD   (abi_version), A

    LD   A, (startup_term_flag)
    LD   (abi_term_mode), A
    LD   A, (startup_mono_flag)
    LD   (abi_monochrome), A

    XOR  A                      ; OVL_NONE = 0
    LD   (abi_current_overlay), A
    LD   (abi_overlay_depth), A

    ; Resolve program drive (0..15 = A:..P:) from CLI override or BDOS 25
    LD   A, (startup_drive_override)
    CP   16
    JR   C, .have_prog_drive
    LD   C, BDOS_CURDSK
    LD   DE, 0
    CALL bdos_call
    AND  0x0F
.have_prog_drive:
    LD   (abi_program_drive), A
    LD   (abi_save_drive), A

    ; ------------------------------------------------------------------
    ; Phase 6: Initialize BDOS DMA (0xD080), MORIA8.DAT, RNG, sound, screen.
    ; ------------------------------------------------------------------
    CALL bdos_reset_dma_default
    CALL dat_init
    JR   NC, .dat_ok

    LD   C, BDOS_PRTSTR
    LD   DE, str_dat_open_err
    CALL bdos_call
    LD   C, BDOS_TERM
    LD   DE, 0
    JP   bdos_call

.dat_ok:
    CALL huff_lru_init
    CALL catalog_init_town_creatures
    CALL icat_init
    CALL msg_init
    CALL rng_init_boot
    CALL sound_init
    CALL screen_init
    CALL screen_hard_clear

    ; ------------------------------------------------------------------
    ; Phase 7: Title / Chargen / Load / Town Loop via unpinned trampolines.
    ; OVL_TITLE exits with A = 0 (Quit), 1 (New Game), 2 (Load Game) so
    ; gameplay enters game_loop_enter at abi_overlay_depth == 0.
    ; ------------------------------------------------------------------
.title_loop:
    LD   A, 0xFF
    LD   (save_slot_selected), A
    CALL tramp_title_menu
    JR   NC, .title_dispatch

    LD   C, BDOS_PRTSTR
    LD   DE, str_title_load_err
    CALL bdos_call
    JR   .exit_warm_boot

.title_dispatch:
    OR   A
    JR   Z, .title_done
    CP   1
    JR   Z, .do_new_game
    CP   2
    JR   Z, .do_load_game
    JR   .title_loop_clear

.do_new_game:
    CALL tramp_player_create
    JR   C, .title_loop_clear
    CALL tramp_gen_town
    JR   C, .title_loop_clear
    CALL msg_init
    CALL game_loop_enter
    JR   .title_loop_clear

.do_load_game:
    CALL tramp_load_menu
    JR   C, .title_loop_clear
    CALL game_loop_enter

.title_loop_clear:
    CALL screen_hard_clear
    JR   .title_loop

.title_done:
    ; Verify stack canary at 0x8C00..0x8C03 remained intact
    LD   HL, STACK_CANARY_ADDR
    LD   DE, stack_canary_bytes
    LD   B, STACK_CANARY_LEN
.chk_canary:
    LD   A, (DE)
    CP   (HL)
    JR   NZ, .canary_bad
    INC  HL
    INC  DE
    DJNZ .chk_canary
    JR   .clean_term_reset

.canary_bad:
    LD   C, BDOS_PRTSTR
    LD   DE, str_canary_corrupt
    CALL bdos_call

.clean_term_reset:
    LD   A, (abi_term_mode)
    OR   A
    LD   HL, str_exit_adm3a
    JR   Z, .exit_puts
    LD   HL, str_exit_ansi
.exit_puts:
    CALL bdos_puts_asciiz

.exit_warm_boot:
    ; Mandatory CP/M warm-boot exit (MAP_BASE overwrites CCP; never RET).
    LD   C, BDOS_TERM
    LD   DE, 0
    CALL bdos_call
    JP   CPM_WARM_BOOT

; ---------------------------------------------------------------------------
; parse_cli_tail — Scan CP/M 0x0080 CLI tail for /A, /V, /M and [A-P]: drive.
; Default terminal mode is ADM-3A (startup_term_flag=0, startup_mono_flag=1).
; Every loop path strictly consumes >= 1 byte (DEC B), guaranteeing termination.
; Safe before TPA check (touches no memory >= 0x5600 and preserves CCP SP).
; ---------------------------------------------------------------------------
parse_cli_tail:
    XOR  A
    LD   (startup_term_flag), A
    INC  A
    LD   (startup_mono_flag), A
    LD   A, 0xFF
    LD   (startup_drive_override), A

    LD   A, (CPM_CLI_TAIL)
    OR   A
    RET  Z
    CP   128
    JR   C, .len_ok
    LD   A, 127
.len_ok:
    LD   B, A                   ; B = remaining bytes in tail (1..127)
    LD   HL, CPM_CLI_TAIL + 1

.scan_ws:
    LD   A, B
    OR   A
    RET  Z
    LD   A, (HL)
    CP   ' '
    JR   Z, .skip_ws
    CP   0x09                   ; TAB
    JR   NZ, .tok_start
.skip_ws:
    INC  HL
    DEC  B
    JR   .scan_ws

.tok_start:
    ; At start of token (or '/'-switch). B >= 1.
    LD   A, (HL)
    CP   '/'
    JR   NZ, .chk_drive

    ; Consume '/' immediately so B always strictly decreases
    INC  HL
    DEC  B
    RET  Z                      ; trailing '/' at end of tail
    LD   A, (HL)
    CP   '/'
    JR   Z, .tok_start          ; e.g. "//M" -> treat second '/' as switch start
    CP   ' '
    JR   Z, .scan_ws            ; e.g. "/ M"
    CP   0x09
    JR   Z, .scan_ws
    ; Uppercase ASCII letter and check /A (ADM-3A), /V (ANSI Color), /M (ANSI Mono)
    CP   'a'
    JR   C, .sw_upper
    CP   'z' + 1
    JR   NC, .sw_upper
    AND  0xDF
.sw_upper:
    LD   DE, (1 << 8) | TERM_ADM3A
    CP   'A'
    JR   Z, .sw_chk_delim
    LD   DE, (0 << 8) | TERM_ANSI
    CP   'V'
    JR   Z, .sw_chk_delim
    LD   DE, (1 << 8) | TERM_ANSI
    CP   'M'
    JR   NZ, .skip_tok_step
.sw_chk_delim:
    ; Require delimiter (EOF, whitespace, or '/') so /MON, /VT, /ADM are ignored
    INC  HL
    DEC  B
    JR   Z, .sw_store_done
    LD   A, (HL)
    CP   ' '
    JR   Z, .sw_store_ws
    CP   0x09
    JR   Z, .sw_store_ws
    CP   '/'
    JR   NZ, .skip_tok_step
    CALL .sw_commit
    JR   .tok_start
.sw_store_ws:
    CALL .sw_commit
    JR   .scan_ws
.sw_store_done:
.sw_commit:
    LD   A, E
    LD   (startup_term_flag), A
    LD   A, D
    LD   (startup_mono_flag), A
    RET

.chk_drive:
    ; Consume first token char C; check '[A-P]:' or '[a-p]:'
    LD   C, A
    INC  HL
    DEC  B
    RET  Z                      ; 1-char token cannot be 'X:'
    LD   A, (HL)
    CP   ':'
    JR   NZ, .skip_tok_cur      ; not 'X:', inspect current (HL) (may be '/')
    LD   A, C
    CP   'a'
    JR   C, .drv_upper
    CP   'z' + 1
    JR   NC, .drv_upper
    AND  0xDF
.drv_upper:
    CP   'A'
    JR   C, .skip_tok_step
    CP   'P' + 1
    JR   NC, .skip_tok_step
    ; Valid drive letter 'A'..'P' followed by ':'; consume ':' and check delimiter
    SUB  'A'
    LD   E, A
    INC  HL
    DEC  B
    JR   Z, .set_drv_done
    LD   A, (HL)
    CP   ' '
    JR   Z, .set_drv_ws
    CP   0x09
    JR   Z, .set_drv_ws
    CP   '/'
    JR   NZ, .skip_tok_step     ; e.g. "B:FOO" -> not standalone drive override
    LD   A, E
    LD   (startup_drive_override), A
    JP   .tok_start             ; e.g. "B:/M"
.set_drv_ws:
    LD   A, E
    LD   (startup_drive_override), A
    JP   .scan_ws
.set_drv_done:
    LD   A, E
    LD   (startup_drive_override), A
    RET

.skip_tok_step:
    INC  HL
    DEC  B
.skip_tok_cur:
    LD   A, B
    OR   A
    RET  Z
    LD   A, (HL)
    CP   ' '
    JP   Z, .scan_ws
    CP   0x09
    JP   Z, .scan_ws
    CP   '/'
    JP   Z, .tok_start
    JR   .skip_tok_step

; ---------------------------------------------------------------------------
; Startup Resident Constants & Flags (inside 0x0100..0x55FF)
; ---------------------------------------------------------------------------
startup_term_flag:
    DB   TERM_ADM3A
startup_mono_flag:
    DB   1
startup_drive_override:
    DB   0xFF

abi_magic_bytes:
    DB   "M8Z0"
stack_canary_bytes:
    DB   STACK_CANARY_B0, STACK_CANARY_B1, STACK_CANARY_B2, STACK_CANARY_B3

str_insufficient_tpa:
    DB   "Insufficient TPA: requires 52K (0xD100+).", 0x0D, 0x0A, "$"
str_dat_open_err:
    DB   "Error: MORIA8.DAT missing or invalid.", 0x0D, 0x0A, "$"
str_canary_corrupt:
    DB   0x0D, 0x0A, "WARNING: Stack canary corrupted!", 0x0D, 0x0A, "$"

; ============================================================
; CP/M HAL Modules
; ============================================================
    INCLUDE "hal/bdos_io.asm"
    INCLUDE "hal/screen_ansi.asm"
    INCLUDE "hal/input_csi.asm"
    INCLUDE "hal/sound_bel.asm"
    INCLUDE "hal/dat_loader.asm"

; ============================================================
; Core Z80 Modules
; ============================================================
    INCLUDE "math.asm"
    INCLUDE "rng.asm"
    INCLUDE "messages.asm"
    INCLUDE "huffman.asm"
    INCLUDE "numeric_format.asm"
    INCLUDE "item_catalog.asm"
    INCLUDE "item_desc.asm"
    INCLUDE "player_core.asm"
    INCLUDE "status_bar.asm"
    INCLUDE "viewport.asm"
    INCLUDE "los.asm"
    INCLUDE "monster_core.asm"
    INCLUDE "monster_ai.asm"
    INCLUDE "turn.asm"
    INCLUDE "game_loop.asm"

; ============================================================
; Resident Overlay Trampolines
; ============================================================
    INCLUDE "trampolines.asm"

str_title_load_err:
    DB   "Error: failed to load title overlay.", 0x0D, 0x0A, "$"
str_exit_adm3a:
    DB   KEY_ESC, '=', 23 + 0x20, 0x20, 0x0D, 0x0A, 0
str_exit_ansi:
    DB   KEY_ESC, "[0m", KEY_ESC, "[24;1H", 0x0D, 0x0A, 0

; ============================================================
; Pinned RO Item Catalog Metadata & Hot Tables (measured in M1)
; ============================================================
    INCLUDE "item_cat_pinned_z80.inc"
    EXPORT icat_blk_index
    EXPORT icat_canon_counts
    EXPORT icat_canon_syms

    INCLUDE "item_hot_tables_z80.inc"
    EXPORT it_category
    EXPORT it_color_ac
    EXPORT it_ac_extra_id_lo
    EXPORT it_ac_extra_id_hi
    EXPORT it_ac_extra_val
    EXPORT it_unknown_idx
    EXPORT flavour_colors

    EXPORT resident_end
resident_end:
    ASSERT_RESIDENT_FIT resident_start, resident_end

    SAVEBIN "MORIA8.COM", resident_start, resident_end - resident_start

; ============================================================
; Resident BSS (0x6A00..0x8BFF) — emitted AFTER SAVEBIN so MORIA8.COM is not padded
; ============================================================
    INCLUDE "state.inc"
