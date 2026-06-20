// shared_imports.s - guarded CX16 shared-gameplay import probe
//
// This file is intentionally imported only when CX16_IMPORT_SHARED_GAME_LOOP is
// defined. It mirrors the Commodore resident import order far enough to expose
// real CX16 platform-contract gaps without changing the current boot/title PRG.

.encoding "screencode_mixed"

.const DUNGEON_GEN_BUSY = 1

#import "../../core/color.s"
#import "../../core/rng.s"
#import "../../core/math.s"
#import "../../core/tables.s"
#import "../../core/item_defs.s"
#import "../../core/player.s"
#import "../../core/ui_messages.s"
#import "../../core/ui_status.s"
#import "../../core/generation_busy.s"
#import "../../core/stat_display.s"
#import "../../core/huffman.s"
#import "../../core/dungeon_data.s"
#define DISARM_COMMAND_EXTERNAL
#define DISARM_HELPERS_EXTERNAL
#import "../../core/dungeon_features.s"
#undef DISARM_HELPERS_EXTERNAL
#undef DISARM_COMMAND_EXTERNAL
#import "../../core/monster.s"
#import "../../core/tier_manager.s"
#import "../../core/monster_ai.s"
#import "../../core/recall.s"
#import "../../core/monster_magic.s"
#import "../../core/item.s"
#define ITEM_ACTIONS_OVERLAY_EXTERNAL
#import "../../core/player_items.s"
#import "../../core/spell_data.s"
#define SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../core/spell_effects.s"
#undef SPELL_EFFECTS_INCLUDE_IDENTIFY
#import "../../core/player_magic_state.s"
#import "../../core/player_magic_state_ops.s"
#import "../../core/player_magic.s"
#import "../../core/dungeon_los.s"
#import "../../core/player_move.s"
#define PMU_TURN_FEEDBACK_EXTERNAL
#import "../../core/combat.s"
#undef PMU_TURN_FEEDBACK_EXTERNAL
#import "../../core/projectile.s"
#import "../../core/monster_attack.s"
#import "../../core/turn.s"
#import "../../core/store_data.s"
#import "../../core/runtime_ui_strings.s"
#import "../../core/wizard.s"
#define DISARM_COMMAND_EXTERNAL
#import "../../core/game_loop.s"
#undef DISARM_COMMAND_EXTERNAL
