#importonce
// Commander X16 memory-bank policy.
// $00 = active 8 KB RAM bank ($A000-$BFFF), $01 = active 16 KB ROM bank ($C000-$FFFF).
// ROM bank 0 is KERNAL; writing $00 to $01 keeps KERNAL ROM selected.

.const hal_memory_has_cpu_port     = 0
.const hal_memory_cpu_port         = $01
.const hal_memory_bank_all_ram     = $00
.const hal_memory_bank_all_rom     = $00
.const hal_memory_bank_no_basic    = $00
.const hal_memory_bank_no_kernal   = $00
.const hal_memory_bank_no_roms     = $00
.const hal_huffman_lock_irq_during_decode = 0
.const hal_huffman_print_uses_cached_msg  = 0
.const hal_memory_map_row_helper_enabled  = 0
