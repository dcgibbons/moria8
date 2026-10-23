#importonce
// memory.s — Acorn BBC Master 128 memory map constants, ZP save/restore,
// and Sideways RAM / Shadow RAM hardware definitions.
//
// Authority: docs/BBCMASTER_MEMORY_CONTRACT.md.
//
// Main RAM ($0000-$7FFF):
//   $0002-$008F  shared core zero page (142 B, saved/restored across MOS calls)
//   $0090-$00AF  platform zero page (32 B; $00B0-$00FF untouched for MOS/DFS)
//   $0400-$04FF  FLOOR_ITEM_BASE (256 B)
//   $0500-$05FF  CREATURE_BASE (256 B)
//   $0600-$063F  PLATFORM_HD_DECODE_BUF_BASE (64 B)
//   $0640-$0680  DUNGEON_GEN_DOOR_SCAN_BASE (65 B)
//   $0681-$06FF  MOS OSFILE/OSGBPB/OSWORD/OSARGS control blocks & pathnames
//   $0700-$07FF  beeb_ss_buf (256 B stream & SWR bounce buffer)
//   $0800-$0DFF  untouched MOS sound/serial/Econet/NMI/DFS workspace
//   $0E00-$2FFF  Low Always-Resident code (< $3000: ACCCON/ROMSEL switchers,
//                Mode 0 LYNNE renderer, storage/stream wrappers, zp_save_buf)
//   $3000-$7FFF  High Always-Resident continuation (program_end <= $8000)
//
// Shadow Screen RAM LYNNE ($3000-$7FFF, 20 KB, ACCCON = $05):
//   $3000-$33FF  beeb_font_table (1 KB C64-screen-code-ordered RAM font)
//   $3400-$37FF  DUNGEON_GEN_SCAN_SCRATCH_BASE (1 KB generation scratch)
//   $3800-$3F7F  beeb_char_shadow (80x24 = 1,920 B character shadow)
//   $3F80-$43FF  reserved guard (1,152 B)
//   $4400-$7FFF  80x24 Mode 0 bitmap (15,360 B, CRTC R12=$08, R13=$80)
//
// Private 4 KB RAM ANDY ($8000-$8FFF, ROMSEL = $84):
//   $8000-$8D93  BeebHuffData (3,476 B Huffman trees, dictionary, & stream)
//
// Sideways RAM Banks 4-7 ($8000-$BFFF, 4 x 16 KB = 64 KB):
//   Bank 4 (ROMSEL=$04): BeebPlaySlot ($8000-$A3FF), tier-name pool ($A400-$A7FF),
//                        Active Overlay & Tier Window ($A800-$BFFF, 6,144 B)
//   Bank 5 (ROMSEL=$05): Live 198x66 Map ($8000-$B30B, 13,068 B) + cached OVL.UI
//   Bank 6 (ROMSEL=$06): BeebAuxData ($8000-$96FF, virt $6000-$76FF) + cached
//                        OVL.TOWN, OVL.MODAL, MONSTER.DB1
//   Bank 7 (ROMSEL=$07): cached OVL.SPELL, OVL.ITEMS, OVL.GEN

#import "hal/memory_bank_consts.s"
#import "hal/entropy_consts.s"

// ============================================================
// Hardware Registers (SHEILA $FE00-$FEFF & MOS Vectors)
// ============================================================
.const CRTC_ADDR       = $fe00
.const CRTC_DATA       = $fe01
.const VIDEO_ULA_CTRL  = $fe20
.const VIDEO_ULA_PAL   = $fe21
.const SHEILA_ROMSEL   = $fe30
.const SHEILA_ACCCON   = $fe34
.const SYSVIA_T1CL     = $fe44
.const SYSVIA_T1CH     = $fe45

// ACCCON ($FE34) bit masks:
//   Bit 0 (D = $01): CRTC displays Shadow RAM LYNNE
//   Bit 1 (E = $02): VDU driver accesses LYNNE
//   Bit 2 (X = $04): Main CPU accesses LYNNE at $3000-$7FFF
//   Bit 3 (Y = $08): 8 KB HAZEL mapped at $C000-$DFFF
.const ACCCON_NORMAL   = $01    // D=1, X=0 (main RAM at $3000-$7FFF, CRTC displays LYNNE)
.const ACCCON_LYNNE    = $05    // D=1, X=1 (LYNNE mapped at $3000-$7FFF for CPU & CRTC)

// ROMSEL ($FE30) bank values:
.const ROMSEL_BANK4    = $04    // Active gameplay bank (PlaySlot + TierPool + Overlay Window)
.const ROMSEL_BANK5    = $05    // Map ($8000-$B30B) + cached OVL.UI ($B400)
.const ROMSEL_BANK6    = $06    // BeebAuxData ($8000-$96FF) + cached TOWN/MODAL/DB1
.const ROMSEL_BANK7    = $07    // Cached SPELL/ITEMS/GEN
.const ROMSEL_ANDY     = $84    // Bit 7 = 1 maps 4 KB ANDY at $8000-$8FFF, Bank 4 at $9000-$BFFF

// MOS Zero-Page & Vector Addresses (never accessed via raw $90-$FF literals)
.label zp_mos_romsel_shadow = $f4
.label zp_mos_brk_ptr       = $fd
.const MOS_BRKV        = $0202
.const MOS_WRCHV       = $020e
.const MOS_OSRDSC      = $ffb9
.const MOS_OSWRSC      = $ffb6
.const MOS_OSBYTE      = $fff4
.const MOS_OSWORD      = $fff1
.const MOS_OSWRCH      = $ffee
.const MOS_OSNEWL      = $ffe7
.const MOS_OSRDCH      = $ffe0
.const MOS_OSFILE      = $ffdd
.const MOS_OSARGS      = $ffda
.const MOS_OSBGET      = $ffd7
.const MOS_OSBPUT      = $ffd4
.const MOS_OSGBPB      = $ffd1
.const MOS_OSFIND      = $ffce
.const MOS_OSCLI       = $fff7

// ============================================================
// Memory Map Constants
// ============================================================
.const MAP_BASE         = $8000 // Bank 5: 198x66 = 13,068 bytes
.const MAP_END          = $b30b // Bank 5
.const FLOOR_ITEM_BASE  = $0400 // Main RAM: floor item table (256 bytes)
.const FLOOR_ITEM_END   = $04ff
.const CREATURE_BASE    = $0500 // Main RAM: runtime creature/hiscore scratch (256 bytes)
.const CREATURE_END     = $05ff
.const PLATFORM_TIER_NAME_POOL_BASE = $a400 // Bank 4: active tier names (1,024 bytes)
.const PLATFORM_TIER_NAME_POOL_END  = $a7ff
.const BANKED_DATA_BASE = $a800 // Bank 4: shared overlay/tier window (6,144 bytes)
.const BANKED_DATA_END  = $bfff
.const BANK1_DB_BASE    = BANKED_DATA_BASE

// Play slot in Bank 4 ($8000-$A3FF, 9,216 bytes)
.const BEEB_PLAY_SLOT_BASE = $8000
.const BEEB_PLAY_SLOT_END  = $a3ff
.const BEEB_PLAY_SLOT_SIZE = BEEB_PLAY_SLOT_END - BEEB_PLAY_SLOT_BASE + 1

// BeebAuxData virtual ($6000-$76FF) -> Bank 6 physical ($8000-$96FF)
.const BEEB_AUXDATA_VIRT_BASE = $6000
.const BEEB_AUXDATA_VIRT_END  = $76ff
.const BEEB_AUXDATA_PHYS_BASE = $8000
.const BEEB_AUXDATA_PHYS_OFFSET = $20

// BeebHuffData in 4 KB ANDY ($8000-$8FFF)
.const BEEB_HUFFDATA_BASE = $8000
.const BEEB_HUFFDATA_LIMIT = $9000

// LYNNE Shadow RAM layout ($3000-$7FFF when ACCCON = $05)
.const BEEB_FONT_BASE        = $3000 // 1,024 B C64-ordered RAM font ($3000-$33FF)
.const BEEB_FONT_END         = $33ff
.const DUNGEON_GEN_SCAN_SCRATCH_BASE = $3400 // 1,024 B gen scratch in LYNNE ($3400-$37FF)
.const DUNGEON_GEN_SCAN_SCRATCH_SIZE = 1024
.const DUNGEON_GEN_SCAN_SCRATCH_END  = DUNGEON_GEN_SCAN_SCRATCH_BASE + DUNGEON_GEN_SCAN_SCRATCH_SIZE - 1
.const BEEB_CHAR_SHADOW_BASE = $3800 // 80x24 = 1,920 B char shadow in LYNNE ($3800-$3F7F)
.const BEEB_CHAR_SHADOW_END  = $3f7f
.const BEEB_BITMAP_BASE      = $4400 // 80x24 Mode 0 bitmap in LYNNE ($4400-$7FFF, 15,360 B)
.const BEEB_BITMAP_END       = $7fff
.const SCREEN_RAM            = BEEB_CHAR_SHADOW_BASE
.const COLOR_RAM             = BEEB_CHAR_SHADOW_BASE

.const DUNGEON_GEN_DOOR_SCAN_BASE  = hal_layout_dungeon_door_scan_base
.const DUNGEON_GEN_DOOR_SCAN_LIMIT = hal_layout_dungeon_door_scan_limit

// Fixed low-RAM control blocks and bounce buffer ($0681-$07FF)
.const BEEB_OS_CTRL_BASE   = $0681   // OSFILE (18B) / OSGBPB (13B) / OSWORD (14B) control block
.const BEEB_OS_PATH_BASE   = $06a0   // CR-terminated DFS pathname buffer (<= 32 B)
.const BEEB_OS_CMD_BASE    = $06c0   // CR-terminated OSCLI buffer / scratch (<= 64 B)
.const BEEB_SS_BUF_BASE    = $0700   // 256-byte stream & SWR bounce buffer ($0700-$07FF)
.label beeb_ss_buf         = BEEB_SS_BUF_BASE
.label rv_row_map_buf      = beeb_ss_buf
.label rv_row_scr_buf      = beeb_ss_buf + 80

// Platform Zero-Page Allocation ($90-$AF; $B0-$FF untouched for MOS/DFS)
.const BEEB_ZP_PLATFORM_BASE = $90
// $90-$93: hal_entropy_timer0_lo..hal_entropy_timer1_hi (defined in hal/entropy_consts.s)
.label beeb_io_dst           = $94   // 2 bytes ($94-$95): DFS->SWR destination pointer (outside $A0-$AF DFS NMI)
.label beeb_io_dst_hi        = $95
.label beeb_ss_name_len      = $96
.label beeb_ss_lfn           = $97
.label beeb_ss_sec           = $98
.label beeb_ss_handle        = $99
.label beeb_ss_dir           = $9a
.label beeb_ss_eof           = $9b
.label beeb_ss_status        = $9c
.label beeb_acccon_shadow    = $9d   // Software shadow of write-only SHEILA_ACCCON ($FE34)
.label beeb_mmu_byte         = $9e   // Return byte scratch for mmu_safe_* readers
.label beeb_ss_open          = $9f
.label beeb_ss_slot          = $a0
.label beeb_aux_ptr          = $a2   // 2 bytes ($a2-$a3): Bank 6 BeebAuxData physical pointer
.label beeb_aux_ptr_hi       = $a3
.label beeb_nc_ptr           = $a4   // 2 bytes ($a4-$a5): filename converter pointer
.label beeb_io_src           = $a4
.label beeb_io_src_hi        = $a5
.label beeb_nc_len           = $a6
.label beeb_io_cnt           = $a6
.label beeb_nc_tmp           = $a7
.label beeb_io_pages         = $a7
.label beeb_zp_scratch       = $a8
.label beeb_save_aux_mode_flag = $a9
.label save_slot_index       = $aa
.label beeb_bmp_ptr          = $ab   // 2 bytes ($ab-$ac): Mode 0 bitmap cell pointer
.label beeb_fnt_ptr          = $ad   // 2 bytes ($ad-$ae): RAM font glyph pointer
.label beeb_inv_mask         = $af   // $00 normal / $ff inverse-video EOR mask

.const ZP_SAVE_SIZE          = 174   // $02-$AF inclusive (core ZP $02-$8F + platform ZP $90-$AF)

// ============================================================
// Compatibility macros
// ============================================================
.macro BankOutBasic() {}
.macro BankInBasic() {}
.macro BankOutKernal() {}
.macro BankInKernal() {}
.macro BankOutAll() {}
.macro BankRestoreDefault() {}
.macro MachineRestoreDefault() {}
.macro MachineRestoreAllRam() {}
.macro EnterKernal() { php }
.macro ExitKernal() { plp }

// ============================================================
// Low-RAM ZP Save/Restore (< $3000)
// ============================================================
zp_save_buf: .fill ZP_SAVE_SIZE, 0

save_zp:
    ldx #0
!loop:
    lda zp_temp0,x
    sta zp_save_buf,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

restore_zp:
    ldx #0
!loop:
    lda zp_save_buf,x
    sta zp_temp0,x
    inx
    cpx #ZP_SAVE_SIZE
    bne !loop-
    rts

mmu_select_bank1:
    rts

mmu_select_bank0:
    rts

// ============================================================
// Compile-time validation
// ============================================================
.assert "Bank 5 map fits 198x66", MAP_END - MAP_BASE + 1, 13068
.assert "Floor items fit $0400-$04FF", FLOOR_ITEM_END - FLOOR_ITEM_BASE + 1, 256
.assert "Creature scratch fits $0500-$05FF", CREATURE_END - CREATURE_BASE + 1, 256
.assert "Tier name pool is 1,024 bytes", PLATFORM_TIER_NAME_POOL_END - PLATFORM_TIER_NAME_POOL_BASE + 1, 1024
.assert "Overlay/tier window is 6,144 bytes", BANKED_DATA_END - BANKED_DATA_BASE + 1, 6144
.assert "Play slot is 9,216 bytes", BEEB_PLAY_SLOT_SIZE, 9216
.assert "Dungeon-gen scan scratch is page-aligned in LYNNE", <DUNGEON_GEN_SCAN_SCRATCH_BASE, 0
.assert "Dungeon-gen scan scratch fits $3400-$37FF", DUNGEON_GEN_SCAN_SCRATCH_END, $37ff
.assert "Dungeon-gen door scan fits $0640-$0680", DUNGEON_GEN_DOOR_SCAN_BASE == $0640 && DUNGEON_GEN_DOOR_SCAN_LIMIT == $0681, true
.assert "Platform ZP stays below $B0 MOS boundary", beeb_inv_mask < $b0, true
.assert "ZP save buffer size is 174 bytes ($02-$AF)", ZP_SAVE_SIZE, 174
