#importonce
// Lifecycle contract.
//
// Required exports per platform:
//   hal_platform_init_early
//   hal_platform_init_runtime
//   hal_platform_main_loop_begin
//   hal_platform_vector_reassert
//   hal_platform_runtime_resync
//   hal_platform_shutdown
//   hal_platform_panic
//
// Carry clear = success. Carry set = failure, A = HAL_STATUS_*.
// Each platform file must document register and zero-page clobbers locally.
//
// Service contracts:
// - hal_platform_init_early: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; IRQ state platform-owned; runtime RAM visibility.
// - hal_platform_init_runtime: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; installs runtime-visible machine state.
// - hal_platform_main_loop_begin: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; reasserts state needed before command polling.
// - hal_platform_vector_reassert: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; reasserts runtime vectors after OS-visible paths.
// - hal_platform_runtime_resync: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; restores display/banking state after OS calls.
// - hal_platform_shutdown: input none; output ignored; clobbers A/X/Y allowed;
//   returns platform to a safe OS-visible state when possible.
// - hal_platform_panic: input A=status; output does not promise return;
//   clobbers all volatile state; may force OS-visible diagnostics.
