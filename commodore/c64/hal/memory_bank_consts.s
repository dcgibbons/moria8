#importonce
// C64 processor-port bank policy exported for common compatibility aliases.

.const hal_memory_bank_all_ram     = $30
.const hal_memory_bank_all_rom     = $37
.const hal_memory_bank_no_basic    = $36
.const hal_memory_bank_no_kernal   = $35
.const hal_memory_bank_no_roms     = $34

.const hal_memory_vic_bank_select = $dd00
.const hal_memory_vic_bank0_mask  = %00000011
