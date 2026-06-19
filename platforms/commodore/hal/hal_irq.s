#importonce
// IRQ/timer contract.
//
// Required exports per platform:
//   hal_irq_install_runtime
//   hal_irq_restore_os
//   hal_irq_mask
//   hal_irq_unmask
//   hal_irq_ack
//   hal_irq_critical_begin
//   hal_irq_critical_end
//
// Platform implementations own vectors and hardware acknowledge mechanics.
//
// Service contracts:
// - hal_irq_install_runtime: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; installs platform runtime vectors/timers.
// - hal_irq_restore_os: input none; output C=0 success/C=1 A=status;
//   clobbers A/X/Y allowed; restores OS-safe interrupt vectors/timers.
// - hal_irq_mask: input none; output previous IRQ state is platform-owned;
//   clobbers processor flags; no ROM visibility guarantee.
// - hal_irq_unmask: input none; output IRQs unmasked per platform policy;
//   clobbers processor flags; no ROM visibility guarantee.
// - hal_irq_ack: input none; output interrupt source acknowledged; clobbers A
//   allowed; hardware-specific status registers stay platform-owned.
// - hal_irq_critical_begin: input none; output critical section entered;
//   clobbers flags/A allowed; implementation preserves enough state for end.
// - hal_irq_critical_end: input none; output prior critical state restored;
//   clobbers flags/A allowed; must pair with hal_irq_critical_begin.
