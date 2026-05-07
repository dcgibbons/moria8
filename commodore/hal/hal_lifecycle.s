#importonce
// Lifecycle contract.
//
// Required exports per platform:
//   hal_platform_init_early
//   hal_platform_init_runtime
//   hal_platform_runtime_resync
//   hal_platform_shutdown
//   hal_platform_panic
//
// Carry clear = success. Carry set = failure, A = HAL_STATUS_*.
// Each platform file must document register and zero-page clobbers locally.
