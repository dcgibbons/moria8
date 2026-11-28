; memory.inc — CP/M 2.2 Z80 memory map constants, ABI offsets, and ASSERT macros.
;
; Authority: docs/CPM_MEMORY_CONTRACT.md.
; Assembled with sjasmplus (pure 0xNN hex syntax; '$' is assembly PC).

    IFNDEF CPM_MEMORY_INC
    DEFINE CPM_MEMORY_INC 1

; ============================================================
; CP/M 2.2 Page Zero & BDOS Vectors
; ============================================================
CPM_WARM_BOOT       EQU 0x0000
CPM_IOBYTE          EQU 0x0003
CPM_CDISK           EQU 0x0004
CPM_BDOS_ENTRY      EQU 0x0005  ; CALL 0x0005
CPM_BDOS_VEC        EQU 0x0006  ; 16-bit BDOS entry address (exclusive TPA top)
CPM_DEFAULT_FCB     EQU 0x005C
CPM_CLI_TAIL        EQU 0x0080  ; Length byte at 0x0080, args at 0x0081+
CPM_DEFAULT_DMA     EQU 0x0080
CPM_RECORD_SIZE     EQU 128

; Minimum 52 KB TPA ceiling required (0x0100..0xD0FF usable below BDOS)
BDOS_MIN_TOP        EQU 0xD100

; ============================================================
; CP/M 2.2 BDOS Function Codes
; ============================================================
BDOS_TERM           EQU 0
BDOS_CONIN          EQU 1
BDOS_CONOUT         EQU 2
BDOS_RAWIO          EQU 6       ; E=0xFF poll only; E=0x00..0x7F output (no 0xFE/0xFD on 2.2)
BDOS_PRTSTR         EQU 9
BDOS_READSTR        EQU 10
BDOS_CONST          EQU 11
BDOS_VERS           EQU 12      ; Returns >= 0x22 for CP/M 2.2
BDOS_RESETDSK       EQU 13
BDOS_SELDSK         EQU 14
BDOS_OPEN           EQU 15
BDOS_CLOSE          EQU 16
BDOS_SFIRST         EQU 17
BDOS_SNEXT          EQU 18
BDOS_DELETE         EQU 19
BDOS_READSEQ        EQU 20
BDOS_WRITESEQ       EQU 21
BDOS_MAKE           EQU 22
BDOS_RENAME         EQU 23
BDOS_CURDSK         EQU 25
BDOS_SETDMA         EQU 26
BDOS_READRAND       EQU 33
BDOS_WRITERAND      EQU 34
BDOS_FSIZE          EQU 35
BDOS_SETRAND        EQU 36
BDOS_ERRMODE        EQU 45      ; CP/M 3.0+ Set Hardware Error Mode (E=0xFF return errors; guarded by BDOS 12 >= 0x30)

BDOS_RAWIO_POLL     EQU 0xFF

; ============================================================
; 52 KB TPA Memory Layout (0x0100 - 0xD0FF)
; ============================================================
RESIDENT_BASE       EQU 0x0100
RESIDENT_LIMIT      EQU 0x5600
RESIDENT_MAX_SIZE   EQU 0x5500  ; 21,760 B

OVL_WINDOW_BASE     EQU 0x5600
OVL_WINDOW_LIMIT    EQU 0x6A00
OVL_WINDOW_SIZE     EQU 0x1400  ; 5,120 B = 40 x 128 B CP/M records
OVL_MAX_RECORDS     EQU 40

BSS_BASE            EQU 0x6A00
BSS_LIMIT           EQU 0x8C00
BSS_MAX_SIZE        EQU 0x2200  ; 8,704 B
Z80_STATE_BASE      EQU 0x6A00  ; Fixed 64-byte ABI block at start of BSS
Z80_STATE_SIZE      EQU 64

STACK_BOTTOM        EQU 0x8C00
STACK_TOP           EQU 0x8E00
STACK_SIZE          EQU 0x0200  ; 512 B
STACK_CANARY_ADDR   EQU 0x8C00
STACK_CANARY_LEN    EQU 4
STACK_CANARY_B0     EQU 0x4D    ; 'M'
STACK_CANARY_B1     EQU 0x38    ; '8'
STACK_CANARY_B2     EQU 0x53    ; 'S'
STACK_CANARY_B3     EQU 0x4B    ; 'K'

SCREEN_COLS         EQU 80
SCREEN_ROWS         EQU 24
SCREEN_CELLS        EQU 1920    ; 80 * 24

CPM_CHAR_SHADOW_BASE    EQU 0x8E00
CPM_CHAR_SHADOW_SIZE    EQU 1920    ; 0x0780
CPM_CHAR_SHADOW_END     EQU 0x957F
; OVL_GEN reuses cpm_char_shadow as temporary scan scratch and emits ESC[0m+ESC[2J on exit
GEN_SCAN_SCRATCH_BASE   EQU CPM_CHAR_SHADOW_BASE
GEN_SCAN_SCRATCH_SIZE   EQU CPM_CHAR_SHADOW_SIZE

CPM_COLOR_SHADOW_BASE   EQU 0x9580
CPM_COLOR_SHADOW_SIZE   EQU 1920    ; 0x0780
CPM_COLOR_SHADOW_END    EQU 0x9CFF

; cpm_color_shadow bit flags
CPM_ATTR_COLOR_MASK EQU 0x0F    ; Bits 0..3: logical Moria8/C64 palette index (0..15)
CPM_ATTR_BOLD       EQU 0x20    ; Bit 5: SGR 1 bold
CPM_ATTR_REVERSE    EQU 0x40    ; Bit 6: SGR 7 reverse video
CPM_ATTR_DIRTY      EQU 0x80    ; Bit 7: dirty cell awaiting ANSI flush

MAP_COLS            EQU 198
MAP_ROWS            EQU 66
MAP_BASE            EQU 0x9D00
MAP_SIZE            EQU 13068   ; 198 * 66 = 0x330C
MAP_END             EQU 0xD00B

FCB_POOL_BASE       EQU 0xD00C
FCB_SIZE            EQU 36      ; CP/M 2.2 random-access FCB (DR + 8.3 + EX..R2)
FCB_DAT_ADDR        EQU 0xD00C  ; 0xD00C..0xD02F: MORIA8.DAT (DR pinned to abi_program_drive + 1)
FCB_SAVE_ADDR       EQU 0xD030  ; 0xD030..0xD053: SAVE*.SAV / HISCORE.DAT / MORIAID
FCB_TMP_ADDR        EQU 0xD054  ; 0xD054..0xD077: media probe / search temp
FCB_POOL_LIMIT      EQU 0xD080  ; 0xD078..0xD07F = 8 B alignment slack

CPM_DMA_BUF_BASE    EQU 0xD080  ; 128 B aligned BDOS DMA buffer
CPM_DMA_BUF_SIZE    EQU 128
CPM_DMA_BUF_END     EQU 0xD0FF
CPM_TPA_END         EQU 0xD100

; ============================================================
; Fixed ABI Block (z80_state at 0x6A00) Field Offsets
; ============================================================
Z80_ABI_VERSION_NUM     EQU 0x01
Z80_ABI_MAGIC           EQU 0x00    ; 4 B: 'M','8','Z','0'
Z80_ABI_VERSION         EQU 0x04    ; 1 B: 0x01
Z80_ABI_MONOCHROME      EQU 0x05    ; 1 B: 0=color, 1=/M monochrome
Z80_ABI_CURRENT_OVL     EQU 0x06    ; 1 B: OVL_NONE(0) or 1..19
Z80_ABI_OVL_DEPTH       EQU 0x07    ; 1 B: nested trampoline stack depth
Z80_ABI_RNG_SEED        EQU 0x08    ; 4 B: 32-bit PRNG state (LE)
Z80_ABI_ENTROPY_POLL    EQU 0x0C    ; 4 B: 32-bit BDOS 6 idle-poll counter (LE)
Z80_ABI_TURN            EQU 0x10    ; 2 B: 16-bit turn counter (LE)
Z80_ABI_GAME_FLAGS      EQU 0x12    ; 1 B: GAME_FLAG_*
Z80_ABI_PLAYER_X        EQU 0x13    ; 1 B
Z80_ABI_PLAYER_Y        EQU 0x14    ; 1 B
Z80_ABI_PLAYER_DLVL     EQU 0x15    ; 1 B
Z80_ABI_PLAYER_LVL      EQU 0x16    ; 1 B
Z80_ABI_PLAYER_HP       EQU 0x17    ; 2 B (LE)
Z80_ABI_PLAYER_MHP      EQU 0x19    ; 2 B (LE)
Z80_ABI_PLAYER_MP       EQU 0x1B    ; 1 B
Z80_ABI_PLAYER_MMP      EQU 0x1C    ; 1 B
Z80_ABI_HUNGER_STATE    EQU 0x1D    ; 1 B
Z80_ABI_MON_COUNT       EQU 0x1E    ; 1 B
Z80_ABI_ITEM_COUNT      EQU 0x1F    ; 1 B
Z80_ABI_VIEW_X          EQU 0x20    ; 1 B
Z80_ABI_VIEW_Y          EQU 0x21    ; 1 B
Z80_ABI_LIGHT_RAD       EQU 0x22    ; 1 B
Z80_ABI_DEATH_SOURCE    EQU 0x23    ; 1 B
Z80_ABI_SAVE_DRIVE      EQU 0x24    ; 1 B: 0..15 = A:..P:
Z80_ABI_PROGRAM_DRIVE   EQU 0x25    ; 1 B: 0..15 = A:..P:
Z80_ABI_LAST_BDOS_ERR   EQU 0x26    ; 1 B: 0=OK
Z80_ABI_ESC_PENDING     EQU 0x27    ; 1 B: 1-byte CSI pushback lookahead
Z80_ABI_TERM_MODE       EQU 0x28    ; 1 B: 0=ADM-3A (default), 1=VT100/ANSI
Z80_ABI_RESERVED        EQU 0x29    ; 23 B reserved (0x29..0x3F)

TERM_ADM3A              EQU 0
TERM_ANSI               EQU 1

; ============================================================
; Overlay IDs, Save Format V2, & MORIA8.DAT Constants
; ============================================================
OVL_NONE            EQU 0
OVL_START           EQU 1       ; DAT slot 0
OVL_TOWN            EQU 2       ; DAT slot 1
OVL_DEATH           EQU 3       ; DAT slot 2
OVL_GEN             EQU 4       ; DAT slot 3
OVL_HELP            EQU 5       ; DAT slot 4
OVL_UI              EQU 6       ; DAT slot 5
OVL_ITEMS           EQU 7       ; DAT slot 6
OVL_SPELL           EQU 8       ; DAT slot 7
OVL_MODAL           EQU 9       ; DAT slot 8
OVL_CHEST           EQU 10      ; DAT slot 9
OVL_HOME            EQU 11      ; DAT slot 10
OVL_STORAGE         EQU 12      ; DAT slot 11
OVL_TITLE           EQU 13      ; DAT slot 12
OVL_LEGAL           EQU 14      ; DAT slot 13
OVL_ITEMS_EFF       EQU 15      ; DAT slot 20 (split gameplay overlay)
OVL_SPELL_EFF       EQU 16      ; DAT slot 21 (split gameplay overlay)
OVL_ACTIONS         EQU 17      ; DAT slot 22 (split gameplay overlay)
OVL_MON_EXT         EQU 18      ; DAT slot 23 (split gameplay overlay)
OVL_ITEM_MGT        EQU 19      ; DAT slot 24 (split gameplay overlay)
OVL_COUNT           EQU 19
OVL_STACK_MAX       EQU 8

SAVE_VERSION        EQU 0x22    ; Save Format V2 (shared across all ports)
SAVE_SLOT_COUNT     EQU 4
SAVE_STREAM_BYTES   EQU 17164   ; Exact V2 stream size for 198x66 map
SAVE_SLOT_RECORDS   EQU 135     ; (17164 + 127) / 128

; Guard shared TOC constants individually so memory.inc and dat_toc.inc
; assemble cleanly in either include order.
    IFNDEF DAT_HEADER_RECORDS_DEFINED
    DEFINE DAT_HEADER_RECORDS_DEFINED 1
DAT_HEADER_RECORDS  EQU 2       ; 256 B 'M8CP' TOC header
    ENDIF
    IFNDEF DAT_HEADER_BYTES_DEFINED
    DEFINE DAT_HEADER_BYTES_DEFINED 1
DAT_HEADER_BYTES    EQU 256
    ENDIF
    IFNDEF DAT_VERSION_DEFINED
    DEFINE DAT_VERSION_DEFINED 1
DAT_VERSION         EQU 1
    ENDIF
    IFNDEF DAT_MAX_ENTRIES_DEFINED
    DEFINE DAT_MAX_ENTRIES_DEFINED 1
DAT_MAX_ENTRIES     EQU 41
    ENDIF
DAT_MAX_REC_COUNT     EQU 255   ; u8 rec_count limit in 3 B in-RAM TOC cache
DAT_CACHE_HEADER_SIZE EQU 4
DAT_CACHE_ENTRY_SIZE  EQU 3     ; +0..1 u16 start_rec, +2 u8 rec_count
DAT_CACHE_SIZE        EQU 127   ; 4 + 41 * 3 = 127 B

; Input & ESC/CSI disambiguation constants (safe down to 2400 baud on 4-8 MHz Z80)
ESC_CSI_POLL_ITERS  EQU 255
KEY_BEL             EQU 0x07
KEY_BS              EQU 0x08
KEY_CR              EQU 0x0D
KEY_ESC             EQU 0x1B

; ============================================================
; Compile-Time Layout ASSERT Helper Macros
; ============================================================
    MACRO ASSERT_LE sym, limit, msg
        ASSERT (sym) <= (limit), msg
    ENDM

    MACRO ASSERT_LT sym, limit, msg
        ASSERT (sym) < (limit), msg
    ENDM

    MACRO ASSERT_GE sym, floor_val, msg
        ASSERT (sym) >= (floor_val), msg
    ENDM

    MACRO ASSERT_EQ sym, expected, msg
        ASSERT (sym) == (expected), msg
    ENDM

    MACRO ASSERT_RANGE sym, lo, hi, msg
        ASSERT ((sym) >= (lo)) && ((sym) <= (hi)), msg
    ENDM

    MACRO ASSERT_SPAN_FIT start_sym, end_sym, base_val, limit_val, msg
        ASSERT ((start_sym) == (base_val)) && ((end_sym) >= (start_sym)) && ((end_sym) <= (limit_val)), msg
    ENDM

    MACRO ASSERT_RESIDENT_FIT start_sym, end_sym
        ASSERT ((start_sym) == RESIDENT_BASE) && ((end_sym) > (start_sym)) && ((end_sym) <= OVL_WINDOW_BASE), "MORIA8.COM resident segment exceeds 0x5600 OVL_WINDOW_BASE"
    ENDM

    MACRO ASSERT_OVL_FIT start_sym, end_sym
        ASSERT ((start_sym) == OVL_WINDOW_BASE) && ((end_sym) > (start_sym)) && ((end_sym) <= OVL_WINDOW_LIMIT), "Overlay segment exceeds 0x5600..0x69FF (5,120 B) window"
    ENDM

    MACRO ASSERT_BSS_FIT start_sym, end_sym
        ASSERT ((start_sym) == BSS_BASE) && ((end_sym) >= (start_sym)) && ((end_sym) <= STACK_BOTTOM), "Resident BSS exceeds 0x8C00 STACK_BOTTOM"
    ENDM

; ============================================================
; Memory Map Self-Consistency Assertions
; ============================================================
    ASSERT RESIDENT_BASE == 0x0100, "CP/M .COM origin must be 0x0100"
    ASSERT RESIDENT_BASE + RESIDENT_MAX_SIZE == OVL_WINDOW_BASE, "Resident ceiling mismatch"
    ASSERT OVL_WINDOW_BASE + OVL_WINDOW_SIZE == BSS_BASE, "Overlay window ceiling mismatch"
    ASSERT OVL_WINDOW_SIZE == OVL_MAX_RECORDS * CPM_RECORD_SIZE, "Overlay window must be 40 x 128 B records"
    ASSERT DAT_CACHE_SIZE == DAT_CACHE_HEADER_SIZE + DAT_MAX_ENTRIES * DAT_CACHE_ENTRY_SIZE, "DAT TOC cache size mismatch"
    ASSERT BSS_BASE + BSS_MAX_SIZE == STACK_BOTTOM, "BSS ceiling must meet STACK_BOTTOM"
    ASSERT STACK_TOP - STACK_BOTTOM == STACK_SIZE, "Stack size mismatch"
    ASSERT STACK_BOTTOM + STACK_CANARY_LEN <= STACK_TOP, "Stack canary exceeds stack"
    ASSERT CPM_CHAR_SHADOW_BASE == STACK_TOP, "Char shadow must follow STACK_TOP"
    ASSERT CPM_CHAR_SHADOW_BASE + CPM_CHAR_SHADOW_SIZE == CPM_COLOR_SHADOW_BASE, "Color shadow must follow char shadow"
    ASSERT CPM_COLOR_SHADOW_BASE + CPM_COLOR_SHADOW_SIZE == MAP_BASE, "MAP_BASE must follow color shadow"
    ASSERT MAP_BASE + MAP_SIZE - 1 == MAP_END, "MAP_END mismatch"
    ASSERT MAP_END + 1 == FCB_POOL_BASE, "FCB pool must follow MAP_END"
    ASSERT FCB_TMP_ADDR + FCB_SIZE <= CPM_DMA_BUF_BASE, "FCBs overlap DMA buffer"
    ASSERT CPM_DMA_BUF_BASE + CPM_DMA_BUF_SIZE == CPM_TPA_END, "DMA buffer must end at 0xD100"
    ASSERT CPM_TPA_END == BDOS_MIN_TOP, "Minimum TPA must match 0xD100"
    ASSERT (CPM_DMA_BUF_BASE & 0x7F) == 0, "cpm_dma_buf must be 128-byte aligned"

    ENDIF
