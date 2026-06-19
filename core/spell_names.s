// spell_names.s — spell/prayer name tables for the modal spell UI overlay

mage_spell_name_lo:
    .byte <msn_0,  <msn_1,  <msn_2,  <msn_3,  <msn_4,  <msn_5,  <msn_6,  <msn_7
    .byte <msn_8,  <msn_9,  <msn_10, <msn_11, <msn_12, <msn_13, <msn_14, <msn_15
    .byte <msn_16, <msn_17, <msn_18, <msn_19, <msn_20, <msn_21, <msn_22, <msn_23
    .byte <msn_24, <msn_25, <msn_26, <msn_27, <msn_28, <msn_29, <msn_30
mage_spell_name_hi:
    .byte >msn_0,  >msn_1,  >msn_2,  >msn_3,  >msn_4,  >msn_5,  >msn_6,  >msn_7
    .byte >msn_8,  >msn_9,  >msn_10, >msn_11, >msn_12, >msn_13, >msn_14, >msn_15
    .byte >msn_16, >msn_17, >msn_18, >msn_19, >msn_20, >msn_21, >msn_22, >msn_23
    .byte >msn_24, >msn_25, >msn_26, >msn_27, >msn_28, >msn_29, >msn_30

priest_spell_name_lo:
    .byte <psn_0,  <psn_1,  <psn_2,  <psn_3,  <psn_4,  <psn_5,  <psn_6,  <psn_7
    .byte <psn_8,  <psn_9,  <psn_10, <psn_11, <psn_12, <psn_13, <psn_14, <psn_15
    .byte <psn_16, <psn_17, <psn_18, <psn_19, <psn_20, <psn_21, <psn_22, <psn_23
    .byte <psn_24, <psn_25, <psn_26, <psn_27, <psn_28, <psn_29, <psn_30
priest_spell_name_hi:
    .byte >psn_0,  >psn_1,  >psn_2,  >psn_3,  >psn_4,  >psn_5,  >psn_6,  >psn_7
    .byte >psn_8,  >psn_9,  >psn_10, >psn_11, >psn_12, >psn_13, >psn_14, >psn_15
    .byte >psn_16, >psn_17, >psn_18, >psn_19, >psn_20, >psn_21, >psn_22, >psn_23
    .byte >psn_24, >psn_25, >psn_26, >psn_27, >psn_28, >psn_29, >psn_30

msn_0:  .text "Magic Missile" ; .byte 0
.label msn_1 = itok_detect_monsters
msn_2:  .text "Phase Door" ; .byte 0
msn_3:  .text "Light Area" ; .byte 0
.label msn_4 = spell_name_cure_light_wounds
msn_5:  .text "Find Hidden Traps/Doors" ; .byte 0
msn_6:  .text "Stinking Cloud" ; .byte 0
msn_7:  .text "Confusion" ; .byte 0
msn_8:  .text "Lightning Bolt" ; .byte 0
msn_9:  .text "Trap/Door Destruction" ; .byte 0
msn_10: .text "Sleep I" ; .byte 0
msn_11: .text "Cure Poison" ; .byte 0
msn_12: .text "Teleport Self" ; .byte 0
msn_13: .text "Remove Curse" ; .byte 0
msn_14: .text "Frost Bolt" ; .byte 0
msn_15: .text "Turn Stone to Mud" ; .byte 0
msn_16: .text "Create Food" ; .byte 0
msn_17: .text "Recharge Item I" ; .byte 0
msn_18: .text "Sleep II" ; .byte 0
msn_19: .text "Polymorph Other" ; .byte 0
msn_20: .text "Identify" ; .byte 0
msn_21: .text "Sleep III" ; .byte 0
msn_22: .text "Fire Bolt" ; .byte 0
msn_23: .text "Slow Monster" ; .byte 0
msn_24: .text "Frost Ball" ; .byte 0
msn_25: .text "Recharge Item II" ; .byte 0
msn_26: .text "Teleport Other" ; .byte 0
msn_27: .text "Haste Self" ; .byte 0
msn_28: .text "Fire Ball" ; .byte 0
msn_29: .text "Word of Destruction" ; .byte 0
msn_30: .text "Genocide" ; .byte 0

psn_0:  .text "Detect Evil" ; .byte 0
.label psn_1 = spell_name_cure_light_wounds
psn_2:  .text "Bless" ; .byte 0
psn_3:  .text "Remove Fear" ; .byte 0
psn_4:  .text "Call Light" ; .byte 0
psn_5:  .text "Find Traps" ; .byte 0
psn_6:  .text "Detect Doors/Stairs" ; .byte 0
psn_7:  .text "Slow Poison" ; .byte 0
psn_8:  .text "Blind Creature" ; .byte 0
psn_9:  .text "Portal" ; .byte 0
psn_10: .text "Cure Medium Wounds" ; .byte 0
psn_11: .text "Chant" ; .byte 0
psn_12: .text "Sanctuary" ; .byte 0
psn_13: .text "Create Food" ; .byte 0
psn_14: .text "Remove Curse" ; .byte 0
psn_15: .text "Resist Heat and Cold" ; .byte 0
psn_16: .text "Neutralize Poison" ; .byte 0
psn_17: .text "Orb of Draining" ; .byte 0
psn_18: .text "Cure Serious Wounds" ; .byte 0
psn_19: .text "Sense Invisible" ; .byte 0
psn_20: .text "Protection from Evil" ; .byte 0
psn_21: .text "Earthquake" ; .byte 0
psn_22: .text "Sense Surroundings" ; .byte 0
psn_23: .text "Cure Critical Wounds" ; .byte 0
psn_24: .text "Turn Undead" ; .byte 0
psn_25: .text "Prayer" ; .byte 0
psn_26: .text "Dispel Undead" ; .byte 0
psn_27: .text "Heal" ; .byte 0
psn_28: .text "Dispel Evil" ; .byte 0
psn_29: .text "Glyph of Warding" ; .byte 0
psn_30: .text "Holy Word" ; .byte 0

spell_name_cure_light_wounds:
    .text "Cure Light Wounds" ; .byte 0

.assert "Mage names", mage_spell_name_hi - mage_spell_name_lo, SPELL_CATALOG_COUNT
.assert "Priest names", priest_spell_name_hi - priest_spell_name_lo, SPELL_CATALOG_COUNT
