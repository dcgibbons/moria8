; bdos_io.asm — CP/M 2.2 BDOS HAL wrappers (IX/IY preservation, DMA, FCBs, BDOS 13 recovery).
;
; Requires main.asm to INCLUDE "memory.inc" and core/z80/state.inc beforehand.
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax).
; Never uses CP/M 3-only BDOS 6 E=0xFE/0xFD subfunctions.

    EXPORT bdos_call
    EXPORT bdos_rawio_poll
    EXPORT bdos_rawio_putc
    EXPORT bdos_puts_asciiz
    EXPORT bdos_set_dma
    EXPORT bdos_reset_dma_default
    EXPORT bdos_zero_fcb
    EXPORT bdos_init_fcb_name
    EXPORT bdos_open
    EXPORT bdos_close
    EXPORT bdos_rename
    EXPORT bdos_read_rand
    EXPORT bdos_open_dat
    EXPORT bdos_reset_disk_recover
    EXPORT dat_filename_83

; ---------------------------------------------------------------------------
; bdos_call — Invoke CP/M 2.2 BDOS (0x0005) while preserving IX and IY.
; Input:  C  = BDOS function code
;         DE = BDOS argument
; Output: A  = BDOS return byte (L)
;         HL = BDOS return word
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_call:
    PUSH IX
    PUSH IY
    CALL CPM_BDOS_ENTRY
    POP  IY
    POP  IX
    RET

; ---------------------------------------------------------------------------
; bdos_rawio_poll — Non-blocking console input poll via BDOS 6 (E = 0xFF only).
; Output: A = ASCII byte if ready (Z=0), or A = 0 if none (Z=1); CF = 0
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_rawio_poll:
    LD   C, BDOS_RAWIO
    LD   DE, 0x00FF             ; E=0xFF poll only; never use 0xFE/0xFD on CP/M 2.2
    CALL bdos_call
    OR   A                      ; normalize flags (strict_bdos may poison F)
    RET

; ---------------------------------------------------------------------------
; bdos_rawio_putc — Raw console byte output via BDOS 6 (guards against E=0xFF).
; Input:  A = byte to transmit (0xFF is ignored and never sent raw)
; Output: none
; Preserves: BC, DE, HL, IX, IY (clobbers AF)
; ---------------------------------------------------------------------------
bdos_rawio_putc:
    CP   BDOS_RAWIO_POLL
    RET  Z                      ; guard: E=0xFF triggers BDOS 6 poll instead of output
    PUSH BC
    PUSH DE
    PUSH HL
    LD   E, A
    LD   D, 0
    LD   C, BDOS_RAWIO
    CALL bdos_call
    POP  HL
    POP  DE
    POP  BC
    RET

; ---------------------------------------------------------------------------
; bdos_puts_asciiz — Print NUL-terminated ASCII string via bdos_rawio_putc.
; Input:  HL = pointer to NUL-terminated string
; Output: HL = pointer to terminating NUL byte
; Preserves: BC, DE, IX, IY (clobbers AF, HL)
; ---------------------------------------------------------------------------
bdos_puts_asciiz:
    LD   A, (HL)
    OR   A
    RET  Z
    CALL bdos_rawio_putc
    INC  HL
    JR   bdos_puts_asciiz

; ---------------------------------------------------------------------------
; bdos_set_dma — Set CP/M BDOS DMA address (BDOS 26).
; Input:  DE = target DMA address
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_set_dma:
    LD   C, BDOS_SETDMA
    JP   bdos_call

; ---------------------------------------------------------------------------
; bdos_reset_dma_default — Restore canonical BDOS DMA buffer at cpm_dma_buf (0xD080).
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_reset_dma_default:
    LD   DE, CPM_DMA_BUF_BASE
    LD   C, BDOS_SETDMA
    JP   bdos_call

; ---------------------------------------------------------------------------
; bdos_zero_fcb — Zero all 36 bytes of a CP/M 2.2 random-access FCB via LDIR.
; Input:  HL = FCB base address
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_zero_fcb:
    LD   E, L
    LD   D, H
    INC  DE
    LD   (HL), 0
    LD   BC, FCB_SIZE - 1
    LDIR
    RET

; ---------------------------------------------------------------------------
; bdos_init_fcb_name — Zero 36-byte FCB and set DR + 8.3 uppercase filename.
; Input:  HL = FCB base address (36 B)
;         DE = pointer to 11-byte uppercase space-padded 8.3 name
;         A  = drive byte DR (0 = default, 1..16 = A:..P:)
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_init_fcb_name:
    PUSH AF
    PUSH DE
    PUSH HL
    CALL bdos_zero_fcb
    POP  DE                     ; DE = FCB base
    POP  HL                     ; HL = 11-byte 8.3 name source
    POP  AF                     ; A = DR
    LD   (DE), A                ; FCB+0 = DR
    INC  DE                     ; DE = FCB+1
    LD   BC, 11
    LDIR
    RET

; ---------------------------------------------------------------------------
; bdos_open / bdos_close / bdos_rename — Open (15), close (16), or rename (23).
; Input:  DE = initialized FCB address (+16..+27 new name for bdos_rename)
; Output: A  = BDOS return (0..3 OK, 0xFF error)
;         CF = 0 on success, CF = 1 on error; abi_last_bdos_err updated
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_open:
    LD   C, BDOS_OPEN
    JR   _bdos_open_close

bdos_close:
    LD   C, BDOS_CLOSE
    JR   _bdos_open_close

bdos_rename:
    LD   C, BDOS_RENAME

_bdos_open_close:
    CALL bdos_call
    CP   0xFF
    JR   Z, .oc_err
    PUSH AF
    XOR  A
    LD   (abi_last_bdos_err), A
    POP  AF
    OR   A                      ; CF = 0
    RET
.oc_err:
    LD   (abi_last_bdos_err), A
    SCF
    RET

; ---------------------------------------------------------------------------
; bdos_read_rand — Random-access 128-byte record read via BDOS 33 (F_READRAND).
; Input:  DE = opened FCB address
;         HL = 16-bit record number (0..65535)
; Output: A  = BDOS return (0 = OK, nonzero = error)
;         CF = 0 on success, CF = 1 on error; abi_last_bdos_err updated
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_read_rand:
    EX   DE, HL                 ; HL = FCB, DE = record_num
    PUSH HL                     ; save FCB pointer for BDOS call
    LD   BC, 33                 ; FCB+33..35 = R0, R1, R2
    ADD  HL, BC
    LD   (HL), E
    INC  HL
    LD   (HL), D
    INC  HL
    LD   (HL), 0
    POP  DE                     ; DE = FCB
    LD   C, BDOS_READRAND
    CALL bdos_call
    OR   A                      ; CF = 0, Z = (A == 0)
    LD   (abi_last_bdos_err), A
    RET  Z
    SCF
    RET

; ---------------------------------------------------------------------------
; bdos_open_dat — Pin fcb_dat[0] = abi_program_drive + 1 ("MORIA8  DAT") and open.
; Output: CF = 0 on success, CF = 1 on error
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_open_dat:
    LD   HL, FCB_DAT_ADDR
    LD   DE, dat_filename_83
    LD   A, (abi_program_drive)
    INC  A                      ; DR = 1..16 (never 0)
    CALL bdos_init_fcb_name
    LD   DE, FCB_DAT_ADDR
    JP   bdos_open

; ---------------------------------------------------------------------------
; bdos_reset_disk_recover — BDOS 13 Reset Disk System + full CP/M 2.2 recovery.
; Input:  A = target drive to re-select via BDOS 14 (0..15 = A:..P:)
; Output: CF = 0 on success, CF = 1 on drive-select or MORIA8.DAT reopen failure
; Sequence: BDOS 13 -> SETDMA 0xD080 -> BDOS 14 target drive -> reopen fcb_dat.
; Clobbers: AF, BC, DE, HL (preserves IX, IY)
; ---------------------------------------------------------------------------
bdos_reset_disk_recover:
    PUSH AF                     ; preserve target drive (0..15)
    LD   C, BDOS_RESETDSK
    LD   DE, 0
    CALL bdos_call
    CALL bdos_reset_dma_default ; BDOS 13 resets DMA to 0x0080 -> restore 0xD080
    POP  AF
    CP   16
    JR   NC, .bad_drive
    LD   E, A
    LD   D, 0
    LD   C, BDOS_SELDSK
    CALL bdos_call
    CP   0xFF
    JR   Z, .sel_err
    JP   bdos_open_dat
.bad_drive:
    LD   A, 0xFF
.sel_err:
    PUSH AF                     ; keep failure code while ensuring fcb_dat is re-opened
    CALL bdos_open_dat
    POP  AF
    LD   (abi_last_bdos_err), A
    SCF
    RET

dat_filename_83:
    DB   "MORIA8  DAT"
