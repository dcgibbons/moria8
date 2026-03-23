#importonce
// monster_threat_vdc.s — C128 live viewport threat coloring
//
// Keeps the shared species palette (`cr_color`) intact while mapping visible
// dungeon monsters to a threat palette relative to the player's level.

// Input:  X = monster type ID
// Output: A = VIC color
// Clobbers: A
monster_get_threat_color:
    // Town NPCs keep their authored species colors; they are the only live
    // creatures that carry level 0 in the shipped tables.
    lda cr_level,x
    beq !species_color+

    // Easy: monster is 3+ levels below the player.
    clc
    adc #3
    cmp zp_player_lvl
    bcc !low+
    beq !low+

    // Moderate: monster is below or equal to the player.
    lda cr_level,x
    cmp zp_player_lvl
    bcc !med+
    beq !med+

    // Dangerous/deadly: monster is above the player.
    sec
    sbc zp_player_lvl
    cmp #3
    bcc !high+
    lda #COL_THREAT_DEADLY
    rts

!species_color:
    lda cr_color,x
    rts
!low:
    lda #COL_THREAT_LOW
    rts
!med:
    lda #COL_THREAT_MED
    rts
!high:
    lda #COL_THREAT_HIGH
    rts
