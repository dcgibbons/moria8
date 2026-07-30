#importonce
// Apple IIe memory-bank policy. The Apple II has no CPU banking port on the
// runtime path (main RAM is always visible; aux is reached via RAMRD/RAMWRT
// soft switches owned by memory_aux.s, not via a bank register).

.const hal_memory_has_cpu_port     = 0
// Dummy port address for shared code that writes the port anyway (e.g.
// core/player_items.s reload path): $0001 is unused RAM on this platform,
// so the write is harmless. The BANK_* values are never consumed.
.const hal_memory_cpu_port         = $01
.const hal_memory_bank_all_ram     = $00
.const hal_memory_bank_all_rom     = $00
.const hal_memory_bank_no_basic    = $00
.const hal_memory_bank_no_kernal   = $00
.const hal_memory_bank_no_roms     = $00
.const hal_huffman_lock_irq_during_decode = 0
.const hal_huffman_print_uses_cached_msg  = 0
.const hal_memory_map_row_helper_enabled  = 0
