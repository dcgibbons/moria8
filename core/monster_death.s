#importonce
// monster_death.s — Monster treasure drops (MON-014; VMS moria.inc
// monster_death). A killed creature's treasure flags are staged here at the
// kill and fulfilled by chest_fulfill_loot (core/chest_loot.s) before the
// command's turn_post_action, through the chest-contents generator.
//
// Placement: resident and always visible, because kills happen in resident
// combat code and in overlays (spells, thrown/fired missiles). monster.s
// imports this file unless the port defines MONSTER_DEATH_EXTERNAL and imports
// it after monster.s into a roomier resident segment.

.const MD_QUEUE_MAX = 4       // kills staged per command; later drops are lost

// Treasure flags per active creature row: VMS CMOVE bits 24-30 in bits 0-6
// (carry object, carry gold, 60% drop, 90% drop, 1d2 drops, 2d2 drops, 4d3
// drops), the chest_loot_flags layout. Dungeon rows load from tier data
// (load_tier_to_buffer); town rows are fixed (pinned Umoria creature list).
cr_treasure:
    .fill MAX_DUNGEON_CREATURES, 0                // 0-56: loaded from tier data
    .byte $00, $00, $00, $00, $07, $06, $0b, $0b  // 57-64: town
cr_treasure_end:
.assert "cr_treasure size", cr_treasure_end - cr_treasure, MAX_CREATURES

// Staged drops: count, then position and flags per kill. The C64 product
// keeps them in free page-2 RAM; md_count is cleared with the monster table
// (every new level) and on load, before any kill can stage one.
#if PLATFORM_SCRATCH_BUFS_IN_PAGE2
.label md_count = PLATFORM_MD_QUEUE_BASE
.label md_x     = md_count + 1
.label md_y     = md_x + MD_QUEUE_MAX
.label md_flags = md_y + MD_QUEUE_MAX
#else
md_count:  .byte 0
md_x:      .fill MD_QUEUE_MAX, 0
md_y:      .fill MD_QUEUE_MAX, 0
md_flags:  .fill MD_QUEUE_MAX, 0
#endif

// ============================================================
// monster_death_stage — Stage the treasure drop of a just-killed creature.
// Input: X = creature type; mfa_x/mfa_y = its position, left there by the
// monster_remove that deleted it (combat_note_kill callers).
// A creature without treasure flags, or a full queue, stages nothing.
// Clobbers: A, X
// ============================================================
monster_death_stage:
    lda cr_treasure,x
    beq !mds_done+
    ldx md_count
    cpx #MD_QUEUE_MAX
    bcs !mds_done+
    sta md_flags,x
    lda mfa_x
    sta md_x,x
    lda mfa_y
    sta md_y,x
    inc md_count
!mds_done:
    rts
