#importonce
// Memory/banking contract.
//
// Required exports per platform:
//   hal_memory_enter_os
//   hal_memory_exit_os
//   hal_memory_restore_runtime
//   hal_memory_copy
//   hal_memory_read_byte
//   hal_memory_write_byte
//
// Required memory-bank constants per platform:
//   hal_memory_bank_all_ram
//   hal_memory_bank_all_rom
//   hal_memory_bank_no_basic
//   hal_memory_bank_no_kernal
//   hal_memory_bank_no_roms
//
// Required VIC-bank constants per VIC platform:
//   hal_memory_vic_bank_select
//   hal_memory_vic_bank0_mask
//
// Required REU register constants per REU-capable platform:
//   hal_memory_reu_status
//   hal_memory_reu_command
//   hal_memory_reu_c64lo
//   hal_memory_reu_c64hi
//   hal_memory_reu_reulo
//   hal_memory_reu_reuhi
//   hal_memory_reu_bank
//   hal_memory_reu_lenlo
//   hal_memory_reu_lenhi
//   hal_memory_reu_irqmask
//   hal_memory_reu_control
//
// Entry/return ROM and RAM visibility must be documented by the platform
// implementation. Common code must not write hardware banking registers.
//
// Service contracts:
// - hal_memory_enter_os: input none; output C=0 success/C=1 A=status;
//   clobbers A allowed; returns with OS/KERNAL ROM callable.
// - hal_memory_exit_os: input none; output C=0 success/C=1 A=status;
//   clobbers A allowed; returns with documented runtime RAM visibility.
// - hal_memory_restore_runtime: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; restores platform runtime banking after foreign code.
// - hal_memory_copy: input platform-owned copy descriptor; output C=status;
//   clobbers A/X/Y allowed; IRQ and banking safety owned by platform.
// - hal_memory_read_byte: input platform-owned address/bank descriptor;
//   output A=byte and C=status; X/Y clobber documented by implementation.
// - hal_memory_write_byte: input A=byte plus platform-owned address/bank
//   descriptor; output C=status; X/Y clobber documented by implementation.
