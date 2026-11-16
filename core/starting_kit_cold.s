#importonce
// starting_kit_cold.s — New-game base provisions and starting equipment (S5)
//
// Module ownership:
//   owner: TitleOverlay / HomeOverlay when STARTING_KIT_EXTERNAL is defined;
//     inline inside game_new_start (core/game_loop.s, +0 B overhead) otherwise.
//   lifetime: once per New Game, immediately after test_seed_point and before
//     player_recalc_equipment.
//   callers: game_new_start (via tramp_init_starting_kit when external). Pure
//     inventory / ZP stores; zero overlay callees.

#if STARTING_KIT_EXTERNAL
init_starting_kit:
#endif
    // --- Starting equipment ---
    // Wooden torch (type 13) in EQUIP_LIGHT with 134 charges (134 × 30 = 4,020
    // turns), and four more in carried slot 2: VMS player_init / Umoria
    // class_base_provisions give every class 5 torches and 5 rations (one of
    // each until 2026-10-25, found by the M5b playtest).
    lda #13
    sta inv_item_id + EQUIP_LIGHT
    sta inv_item_id + 2
    lda #1
    sta inv_qty + EQUIP_LIGHT
    lda #134
    sta inv_p1 + EQUIP_LIGHT
    sta inv_p1 + 2
    lda #0
    sta inv_flags + EQUIP_LIGHT
    sta inv_flags + 2
    lda #4
    sta inv_qty + 2
    lda #1
    sta zp_light_radius
    sta player_data + PL_LIGHT_RAD

    // Five rations of food (type 15) in carried slot 0
    lda #15
    sta inv_item_id
    lda #5
    sta inv_qty
    lda #0
    sta inv_p1
    sta inv_flags

    // Dagger (type 2) in EQUIP_WEAPON
    lda #2
    sta inv_item_id + EQUIP_WEAPON
    lda #1
    sta inv_qty + EQUIP_WEAPON
    lda #0
    sta inv_p1 + EQUIP_WEAPON
    sta inv_flags + EQUIP_WEAPON

    // Leather armor (type 7) in EQUIP_BODY
    lda #7
    sta inv_item_id + EQUIP_BODY
    lda #1
    sta inv_qty + EQUIP_BODY
    lda #0
    sta inv_p1 + EQUIP_BODY
    sta inv_flags + EQUIP_BODY

    // Starting spellbook for casters (carried slot 1)
    lda player_data + PL_SPELL_TYPE
    beq !no_book+
    cmp #SPELL_MAGE
    bne !priest_book+
    lda #47                 // Beginner's Spellbook
    jmp !store_book+
!priest_book:
    lda #48                 // Holy Prayer Book
!store_book:
    sta inv_item_id + 1     // Carried slot 1
    lda #1
    sta inv_qty + 1
    lda #0
    sta inv_p1 + 1
    sta inv_flags + 1
!no_book:
#if STARTING_KIT_EXTERNAL
    rts
#endif
