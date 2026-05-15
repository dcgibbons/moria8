#importonce
// C128 8502 processor-port bank policy exported for common compatibility aliases.

.const hal_memory_has_cpu_port     = true
.const hal_memory_cpu_port         = $01
.const hal_memory_bank_all_ram     = $30
.const hal_memory_bank_all_rom     = $37
.const hal_memory_bank_no_basic    = $36
.const hal_memory_bank_no_kernal   = $35
.const hal_memory_bank_no_roms     = $34
.const hal_huffman_lock_irq_during_decode = true
.const hal_huffman_print_uses_cached_msg  = true

.const hal_memory_vic_bank_select = $dd00
.const hal_memory_vic_bank0_mask  = %00000011

.const hal_memory_reu_status  = $df00
.const hal_memory_reu_command = $df01
.const hal_memory_reu_c64lo   = $df02
.const hal_memory_reu_c64hi   = $df03
.const hal_memory_reu_reulo   = $df04
.const hal_memory_reu_reuhi   = $df05
.const hal_memory_reu_bank    = $df06
.const hal_memory_reu_lenlo   = $df07
.const hal_memory_reu_lenhi   = $df08
.const hal_memory_reu_irqmask = $df09
.const hal_memory_reu_control = $df0a

.const hal_memory_mmu_config_register = $ff00
.const hal_memory_mmu_preconfig_a     = $d501
