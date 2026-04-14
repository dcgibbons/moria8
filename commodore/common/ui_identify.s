#importonce
// ui_identify.s — `/` symbol-identify glossary
//
// Looks up the normalized symbol in recall_query_sc and prints a one-line
// description on the message row. Imported into OVL.UI so the glossary text
// does not consume resident C64 main-RAM headroom.

ui_identify_print:
    jsr msg_clear
    jsr identify_symbol_get_desc
    jsr msg_print
    rts

identify_symbol_get_desc:
    lda recall_query_sc
    bne !identify_not_player+
    lda #<player_data
    sta zp_ptr0
    lda #>player_data
    sta zp_ptr0_hi
    rts
!identify_not_player:
    ldx #0
!identify_search:
    lda identify_symbol_key,x
    cmp recall_query_sc
    beq !identify_found+
    inx
    cpx #IDENTIFY_SYMBOL_COUNT
    bcc !identify_search-
    lda #<identify_not_used_str
    sta zp_ptr0
    lda #>identify_not_used_str
    sta zp_ptr0_hi
    rts
!identify_found:
    lda identify_symbol_lo,x
    sta zp_ptr0
    lda identify_symbol_hi,x
    sta zp_ptr0_hi
    rts

identify_symbol_key:
    .text " "
    .text "!"
    .byte $22
    .text "#"
    .text "$"
    .text "&"
    .text "'"
    .text "("
    .text ")"
    .text "*"
    .text "+"
    .text ","
    .text "-"
    .text "."
    .text "/"
    .text "1"
    .text "2"
    .text "3"
    .text "4"
    .text "5"
    .text "6"
    .text "7"
    .text "8"
    .text ":"
    .text ";"
    .text "<"
    .text "="
    .text ">"
    .text "?"
    .text "A"
    .text "B"
    .text "C"
    .text "D"
    .text "E"
    .text "F"
    .text "G"
    .text "H"
    .text "I"
    .text "J"
    .text "K"
    .text "L"
    .text "M"
    .text "O"
    .text "P"
    .text "Q"
    .text "R"
    .text "S"
    .text "T"
    .text "U"
    .text "V"
    .text "W"
    .text "X"
    .text "Y"
    .text "["
    .byte $5c
    .text "]"
    .text "^"
    .text "a"
    .text "b"
    .text "c"
    .text "d"
    .text "e"
    .text "f"
    .text "g"
    .text "h"
    .text "i"
    .text "j"
    .text "k"
    .text "l"
    .text "m"
    .text "n"
    .text "o"
    .text "p"
    .text "q"
    .text "r"
    .text "s"
    .text "t"
    .text "w"
    .text "y"
    .text "z"
    .text "{"
    .text "|"
    .text "}"
    .text "~"
identify_symbol_key_end:
.label IDENTIFY_SYMBOL_COUNT = identify_symbol_key_end - identify_symbol_key

identify_symbol_lo:
    .byte <identify_space_str, <identify_potion_str, <identify_amulet_str, <identify_wall_str, <identify_treasure_str, <identify_chest_str, <identify_open_door_str, <identify_soft_armor_str, <identify_shield_str, <identify_gems_str
    .byte <identify_closed_door_str, <identify_food_str, <identify_wand_str, <identify_floor_str, <identify_polearm_str
    .byte <identify_store_1_str, <identify_store_2_str, <identify_store_3_str, <identify_store_4_str, <identify_store_5_str, <identify_store_6_str, <identify_store_7_str, <identify_store_8_str
    .byte <identify_rubble_str, <identify_loose_rock_str, <identify_stairs_up_str, <identify_ring_str, <identify_stairs_down_str, <identify_scroll_str
    .byte <identify_A_str, <identify_B_str, <identify_C_str, <identify_D_str, <identify_E_str, <identify_F_str, <identify_G_str, <identify_H_str, <identify_I_str, <identify_J_str
    .byte <identify_K_str, <identify_L_str, <identify_M_str, <identify_O_str, <identify_P_str, <identify_Q_str, <identify_R_str, <identify_S_str, <identify_T_str, <identify_U_str
    .byte <identify_V_str, <identify_W_str, <identify_X_str, <identify_Y_str
    .byte <identify_hard_armor_str, <identify_hafted_weapon_str, <identify_misc_armor_str, <identify_trap_str
    .byte <identify_a_str, <identify_b_str, <identify_c_str, <identify_d_str, <identify_e_str, <identify_f_str, <identify_g_str, <identify_h_str, <identify_i_str, <identify_j_str
    .byte <identify_k_str, <identify_l_str, <identify_m_str, <identify_n_str, <identify_o_str, <identify_p_str, <identify_q_str, <identify_r_str, <identify_s_str, <identify_t_str
    .byte <identify_w_str, <identify_y_str, <identify_z_str
    .byte <identify_missile_str, <identify_sword_str, <identify_bow_str, <identify_misc_item_str

identify_symbol_hi:
    .byte >identify_space_str, >identify_potion_str, >identify_amulet_str, >identify_wall_str, >identify_treasure_str, >identify_chest_str, >identify_open_door_str, >identify_soft_armor_str, >identify_shield_str, >identify_gems_str
    .byte >identify_closed_door_str, >identify_food_str, >identify_wand_str, >identify_floor_str, >identify_polearm_str
    .byte >identify_store_1_str, >identify_store_2_str, >identify_store_3_str, >identify_store_4_str, >identify_store_5_str, >identify_store_6_str, >identify_store_7_str, >identify_store_8_str
    .byte >identify_rubble_str, >identify_loose_rock_str, >identify_stairs_up_str, >identify_ring_str, >identify_stairs_down_str, >identify_scroll_str
    .byte >identify_A_str, >identify_B_str, >identify_C_str, >identify_D_str, >identify_E_str, >identify_F_str, >identify_G_str, >identify_H_str, >identify_I_str, >identify_J_str
    .byte >identify_K_str, >identify_L_str, >identify_M_str, >identify_O_str, >identify_P_str, >identify_Q_str, >identify_R_str, >identify_S_str, >identify_T_str, >identify_U_str
    .byte >identify_V_str, >identify_W_str, >identify_X_str, >identify_Y_str
    .byte >identify_hard_armor_str, >identify_hafted_weapon_str, >identify_misc_armor_str, >identify_trap_str
    .byte >identify_a_str, >identify_b_str, >identify_c_str, >identify_d_str, >identify_e_str, >identify_f_str, >identify_g_str, >identify_h_str, >identify_i_str, >identify_j_str
    .byte >identify_k_str, >identify_l_str, >identify_m_str, >identify_n_str, >identify_o_str, >identify_p_str, >identify_q_str, >identify_r_str, >identify_s_str, >identify_t_str
    .byte >identify_w_str, >identify_y_str, >identify_z_str
    .byte >identify_missile_str, >identify_sword_str, >identify_bow_str, >identify_misc_item_str

identify_space_str:         .text "  - An open pit." ; .byte 0
identify_potion_str:        .text "! - A potion or flask." ; .byte 0
identify_amulet_str:        .byte $22 ; .text " - An amulet, periapt, or necklace." ; .byte 0
identify_wall_str:          .text "# - A stone wall." ; .byte 0
identify_treasure_str:      .text "$ - Treasure." ; .byte 0
identify_chest_str:         .text "& - Treasure chest." ; .byte 0
identify_open_door_str:     .text "' - An open door." ; .byte 0
identify_soft_armor_str:    .text "( - Soft armor." ; .byte 0
identify_shield_str:        .text ") - A shield." ; .byte 0
identify_gems_str:          .text "* - A light source." ; .byte 0
identify_closed_door_str:   .text "+ - A closed door." ; .byte 0
identify_food_str:          .text ", - Food or mushroom patch." ; .byte 0
identify_wand_str:          .text "- - A wand." ; .byte 0
identify_floor_str:         .text ". - Floor." ; .byte 0
identify_polearm_str:       .text "/ - A weapon or staff." ; .byte 0
identify_store_1_str:       .text "1 - Entrance to General Store." ; .byte 0
identify_store_2_str:       .text "2 - Entrance to Armory." ; .byte 0
identify_store_3_str:       .text "3 - Entrance to Weaponsmith." ; .byte 0
identify_store_4_str:       .text "4 - Entrance to Temple." ; .byte 0
identify_store_5_str:       .text "5 - Entrance to Alchemy shop." ; .byte 0
identify_store_6_str:       .text "6 - Entrance to Magic-Users store." ; .byte 0
identify_store_7_str:       .text "7 - Entrance to Black Market." ; .byte 0
identify_store_8_str:       .text "8 - Entrance to Home." ; .byte 0
identify_rubble_str:        .text ": - Rubble." ; .byte 0
identify_loose_rock_str:    .text "; - A loose rock." ; .byte 0
identify_stairs_up_str:     .text "< - An up staircase." ; .byte 0
identify_ring_str:          .text "= - A ring." ; .byte 0
identify_stairs_down_str:   .text "> - A down staircase." ; .byte 0
identify_scroll_str:        .text "? - A scroll or book." ; .byte 0
identify_A_str:             .text "A - Giant Ant Lion." ; .byte 0
identify_B_str:             .text "B - The Balrog." ; .byte 0
identify_C_str:             .text "C - Gelentanious Cube." ; .byte 0
identify_D_str:             .text "D - An Ancient Dragon (Beware)." ; .byte 0
identify_E_str:             .text "E - Elemental." ; .byte 0
identify_F_str:             .text "F - Giant Fly." ; .byte 0
identify_G_str:             .text "G - Ghost." ; .byte 0
identify_H_str:             .text "H - Hobgoblin." ; .byte 0
identify_I_str:             .text "I - Invisible Stalker." ; .byte 0
identify_J_str:             .text "J - Jelly." ; .byte 0
identify_K_str:             .text "K - Killer Beetle." ; .byte 0
identify_L_str:             .text "L - Lich." ; .byte 0
identify_M_str:             .text "M - Mummy." ; .byte 0
identify_O_str:             .text "O - Ooze." ; .byte 0
identify_P_str:             .text "P - Giant humanoid." ; .byte 0
identify_Q_str:             .text "Q - Quylthulg (Pulsing Flesh Mound)." ; .byte 0
identify_R_str:             .text "R - Reptile." ; .byte 0
identify_S_str:             .text "S - Giant Scorpion." ; .byte 0
identify_T_str:             .text "T - Troll." ; .byte 0
identify_U_str:             .text "U - Umber Hulk." ; .byte 0
identify_V_str:             .text "V - Vampire." ; .byte 0
identify_W_str:             .text "W - Wight or Wraith." ; .byte 0
identify_X_str:             .text "X - Xorn." ; .byte 0
identify_Y_str:             .text "Y - Yeti." ; .byte 0
identify_hard_armor_str:    .text "[ - Hard armor." ; .byte 0
identify_hafted_weapon_str: .text "\\ - A digging tool." ; .byte 0
identify_misc_armor_str:    .text "] - Misc. armor." ; .byte 0
identify_trap_str:          .text "^ - A trap." ; .byte 0
identify_a_str:             .text "a - Giant Ant." ; .byte 0
identify_b_str:             .text "b - Giant Bat." ; .byte 0
identify_c_str:             .text "c - Giant Centipede." ; .byte 0
identify_d_str:             .text "d - Dragon." ; .byte 0
identify_e_str:             .text "e - Floating Eye." ; .byte 0
identify_f_str:             .text "f - Giant Frog." ; .byte 0
identify_g_str:             .text "g - Golem." ; .byte 0
identify_h_str:             .text "h - Harpy." ; .byte 0
identify_i_str:             .text "i - Icky Thing." ; .byte 0
identify_j_str:             .text "j - Jackal." ; .byte 0
identify_k_str:             .text "k - Kobold." ; .byte 0
identify_l_str:             .text "l - Giant Lice." ; .byte 0
identify_m_str:             .text "m - Mold." ; .byte 0
identify_n_str:             .text "n - Naga." ; .byte 0
identify_o_str:             .text "o - Orc or Ogre." ; .byte 0
identify_p_str:             .text "p - Person (Humanoid)." ; .byte 0
identify_q_str:             .text "q - Quasit." ; .byte 0
identify_r_str:             .text "r - Rodent." ; .byte 0
identify_s_str:             .text "s - Skeleton." ; .byte 0
identify_t_str:             .text "t - Gaint tick." ; .byte 0
identify_w_str:             .text "w - Worm(s)." ; .byte 0
identify_y_str:             .text "y - Yeek." ; .byte 0
identify_z_str:             .text "z - Zombie." ; .byte 0
identify_missile_str:       .text "{ - Arrow, bolt, or bullet." ; .byte 0
identify_sword_str:         .text "| - A sword or dagger." ; .byte 0
identify_bow_str:           .text "} - Bow, crossbow, or sling." ; .byte 0
identify_misc_item_str:     .text "~ - Miscellaneous item." ; .byte 0
identify_not_used_str:      .text "Not Used." ; .byte 0
