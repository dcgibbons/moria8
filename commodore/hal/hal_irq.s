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
