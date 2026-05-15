#importonce
// Plus/4 ROM/RAM visibility policy exported for common compatibility aliases.

.const hal_memory_has_cpu_port     = false
.const hal_memory_bank_all_ram     = $00
.const hal_memory_bank_all_rom     = $01
.const hal_memory_bank_no_basic    = $01
.const hal_memory_bank_no_kernal   = $00
.const hal_memory_bank_no_roms     = $00
.const hal_huffman_lock_irq_during_decode = false
.const hal_huffman_print_uses_cached_msg  = false
