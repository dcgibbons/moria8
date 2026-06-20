#importonce
// config.s - Commander X16 shared-core configuration constants

.const MACHINE_C64 = $00
.const MACHINE_C128 = $80
.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

.const PLATFORM_COMBAT_MSG_BUF_SIZE = 54
.const PLATFORM_RESIDENT_PLAY = "Default"
.const PLATFORM_HD_DECODE_BUF_BASE = $7000
.const PLATFORM_HD_DECODE_BUF_LIMIT = $7400

.const hal_huffman_lock_irq_during_decode = 0
.const hal_huffman_print_uses_cached_msg = 0

.const DEATH_ALIVE = $00
.const DEATH_TRAP_PIT = $f9
.const DEATH_TRAP_ARROW = $fa
.const DEATH_TRAP_DART = $fb
.const DEATH_TRAP_ROCKFALL = $fc
.const DEATH_CURSED = $fd
.const DEATH_POISON = $fe
.const DEATH_STARVE = $ff
