// chest.s — Classic Moria chest interactions (open/disarm/bash).
//
// Overlay-resident (docs/CHEST_DESIGN.md): chest code is cold, so it lives in
// the chest-only OVL_CHEST window segment. Resident code routes here through
// the platform chest handoffs once chest_find_at_df_target identifies a chest
// at the command target.
//
// This file currently provides the routing shell only; trap/open/disarm/bash
// gameplay lands in the Chest Design implementation steps 7-13.
//
// Entry contract (all three handlers):
//   Input:  df_target_x/df_target_y hold the resolved command target tile.
//   Output: carry set = turn consumed, carry clear = no turn (mirrors
//           door_try_open / bash_command / disarm_command).

chest_open_command:
chest_bash_command:
chest_disarm_command:
    clc
    rts
