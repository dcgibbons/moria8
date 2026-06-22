#importonce
// gameplay_messages.s - shared player-facing gameplay strings.

#if !GAME_LOOP_NAV_STRINGS_EXTERNAL && !GAME_LOOP_STAIR_MOVE_STRINGS_EXTERNAL
search_mode_on_str:
    .text "Search mode on." ; .byte 0

search_mode_off_str:
    .text "Search mode off." ; .byte 0

descend_str:
    .text "You descend the staircase." ; .byte 0

ascend_str:
    .text "You ascend the staircase." ; .byte 0

at_surface_str:
    .text "You are already at the surface." ; .byte 0
#endif

#if !GAME_LOOP_NO_STAIRS_STR_EXTERNAL
no_stairs_str:
    .text "You see no stairs here." ; .byte 0
#endif

#if !GAMEPLAY_DEATH_STRINGS_EXTERNAL
death_terminal_str:
    .text "* You have died *" ; .byte 0
#endif

#if !GAMEPLAY_DUNGEON_ONLY_STR_EXTERNAL
dungeon_only_str:
    .text "That is only useful in the dungeon." ; .byte 0
#endif

#if !GAMEPLAY_DUNGEON_READY_STRINGS_EXTERNAL
dungeon_ready_prefix_str:
    .text "Dungeon level " ; .byte 0

dungeon_ready_suffix_str:
    .text " ready." ; .byte 0
#endif

#if !GAMEPLAY_TOWN_RECOVERY_STR_EXTERNAL
town_recovery_str:
    .text "Rested and resupplied." ; .byte 0
#endif

#if !GAMEPLAY_MONSTER_COMBAT_STRINGS_EXTERNAL
monster_hit_prefix_str:
    .text "You hit the " ; .byte 0

monster_player_miss_prefix_str:
    .text "You miss the " ; .byte 0

monster_kill_prefix_str:
    .text "You have slain the " ; .byte 0

monster_attack_prefix_str:
    .text "The " ; .byte 0

monster_attack_suffix_str:
    .text " hits you." ; .byte 0

monster_miss_suffix_str:
    .text " misses you." ; .byte 0
#endif
