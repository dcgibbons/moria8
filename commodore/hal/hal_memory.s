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
// Entry/return ROM and RAM visibility must be documented by the platform
// implementation. Common code must not write hardware banking registers.
