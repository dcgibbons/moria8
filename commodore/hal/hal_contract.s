#importonce
// Commodore HAL contract aggregator.
//
// This directory is contract-only. Platform-specific register writes, banking
// mechanics, KERNAL call wrappers, and drive behavior belong under the owning
// platform directory.

#import "hal_lifecycle.s"
#import "hal_memory.s"
#import "hal_irq.s"
#import "hal_layout.s"
#import "hal_screen.s"
#import "hal_input.s"
#import "hal_sound.s"
#import "hal_storage.s"
#import "hal_overlay.s"
#import "hal_entropy.s"

.const HAL_STATUS_OK = 0
.const HAL_STATUS_ERR_NOT_FOUND = 1
.const HAL_STATUS_ERR_NO_DEVICE = 2
.const HAL_STATUS_ERR_WRITE_PROTECTED = 3
.const HAL_STATUS_ERR_DISK_FULL = 4
.const HAL_STATUS_ERR_WRONG_MEDIA = 5
.const HAL_STATUS_ERR_DEVICE_NOT_READY = 6
.const HAL_STATUS_ERR_UNSUPPORTED = 7
.const HAL_STATUS_ERR_UNKNOWN = 255

// Common storage phase bands. Platform code may add more specific phase values,
// but user-facing diagnostics should preserve this normalized layer.
.const HAL_STORAGE_PHASE_NONE = 0
.const HAL_STORAGE_PHASE_PROBE = $10
.const HAL_STORAGE_PHASE_OPEN = $20
.const HAL_STORAGE_PHASE_READ = $30
.const HAL_STORAGE_PHASE_WRITE = $40
.const HAL_STORAGE_PHASE_CLOSE = $50
.const HAL_STORAGE_PHASE_COMMAND = $60
.const HAL_STORAGE_PHASE_STATUS = $70
.const HAL_STORAGE_PHASE_MARKER = $80
