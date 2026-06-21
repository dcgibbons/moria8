#importonce
// config.s - Commander X16 shared-core configuration constants

.const MACHINE_C64 = $00
.const MACHINE_C128 = $80
.const COLUMNS_40 = $00
.const COLUMNS_80 = $80

#if CX16_IMPORT_SHARED_GAME_LOOP
#define PLATFORM_GET_INFRA_RANGE_INLINE
#endif
#define HAL_PLATFORM_NO_MONSTER_TARGETS
#define HAL_PLATFORM_NO_TUNNEL_GOLD
#define HAL_PLATFORM_NO_FEAR_EFFECTS
#define HAL_PLATFORM_NO_EGO_DAMAGE
#define HAL_PLATFORM_NO_STORE_ITEMDESC
#define HAL_PLATFORM_NO_MODAL_RESTORE

.const PLATFORM_COMBAT_MSG_BUF_SIZE = 54
#define HAL_HUFFMAN_COMBAT_APPEND
.const PLATFORM_RESIDENT_PLAY = "Default"
.const PLATFORM_HD_DECODE_BUF_BASE = $9e80
.const PLATFORM_HD_DECODE_BUF_LIMIT = $9f00
#define HAL_PLATFORM_ITEM_CATALOG_BANKED
#define CX16_ITEM_NAMES_BANKED

.const OVL_NONE        = 0
.const OVL_STARTUP     = 1
.const OVL_TOWN        = 2
.const OVL_DEATH       = 3
.const OVL_DUNGEON_GEN = 4
.const OVL_HELP        = 5
.const OVL_UI          = 6
.const OVL_ITEMS       = 7
.const OVL_SPELL       = 8
.const CX16_OVERLAY_SLOT_ROYAL  = 4
.const CX16_OVERLAY_SLOT_DISARM = 10

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
