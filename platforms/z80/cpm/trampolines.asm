; trampolines.asm — 6-byte inline-descriptor overlay dispatcher and resident tramp_* stubs.
;
; Included once by resident main.asm.
; Authority: docs/CPM_MEMORY_CONTRACT.md (§4.2).
; Assembled with sjasmplus v1.24.0 (pure 0xNN hex syntax).
;
; Protocol (exact 6-byte stub, matching CPM_MEMORY_CONTRACT.md §4.2):
;   tramp_foo:
;       CALL overlay_trampoline
;       DB   OVL_<ID>
;       DW   OVL_WINDOW_BASE + <offset>
;
; overlay_trampoline consumes desc_ptr from (SP), leaving caller_ret on (SP)
; so the overlay target returns directly to caller_ret.
; Preserves ALL caller registers (AF, BC, DE, HL, IX, IY) into the target
; and preserves ALL target return registers (AF, BC, DE, HL, IX, IY) back
; to the caller across overlay reload.

    IFNDEF CPM_TRAMPOLINES_ASM
    DEFINE CPM_TRAMPOLINES_ASM 1

; Fixed overlay vector entry addresses (OVL_WINDOW_BASE + 3 * idx) so main.asm
; has zero build/symbol dependency on ovl_*.sym and zero cross-overlay leaks.
OVL_ENTRY_VEC_0         EQU OVL_WINDOW_BASE + 0
OVL_ENTRY_VEC_1         EQU OVL_WINDOW_BASE + 3
OVL_ENTRY_VEC_2         EQU OVL_WINDOW_BASE + 6
OVL_ENTRY_VEC_3         EQU OVL_WINDOW_BASE + 9
OVL_ENTRY_VEC_4         EQU OVL_WINDOW_BASE + 12
OVL_ENTRY_VEC_5         EQU OVL_WINDOW_BASE + 15
OVL_ENTRY_VEC_6         EQU OVL_WINDOW_BASE + 18
OVL_ENTRY_VEC_7         EQU OVL_WINDOW_BASE + 21
OVL_ENTRY_VEC_8         EQU OVL_WINDOW_BASE + 24
OVL_ENTRY_VEC_9         EQU OVL_WINDOW_BASE + 27
OVL_ENTRY_VEC_10        EQU OVL_WINDOW_BASE + 30
OVL_ENTRY_VEC_11        EQU OVL_WINDOW_BASE + 33

    EXPORT overlay_trampoline
    EXPORT tramp_title_menu
    EXPORT tramp_legal_viewer
    EXPORT tramp_legal_sysinfo
    EXPORT tramp_player_create
    EXPORT tramp_init_new_world
    EXPORT tramp_gen_town
    EXPORT tramp_gen_dungeon
    EXPORT tramp_store_enter
    EXPORT tramp_town_restock_all
    EXPORT tramp_home_enter
    EXPORT tramp_save_game
    EXPORT tramp_load_menu
    EXPORT tramp_disk_setup
    EXPORT tramp_hiscore_load
    EXPORT tramp_hiscore_save
    EXPORT tramp_actions_open
    EXPORT tramp_actions_close
    EXPORT tramp_actions_search
    EXPORT tramp_actions_disarm
    EXPORT tramp_actions_bash
    EXPORT tramp_actions_tunnel
    EXPORT tramp_actions_trigger_trap
    EXPORT tramp_actions_jam
    EXPORT tramp_chest_open
    EXPORT tramp_chest_disarm
    EXPORT tramp_chest_search
    EXPORT tramp_chest_fulfill_loot
    EXPORT tramp_chest_pick_item
    EXPORT tramp_modal_recalc_equipment
    EXPORT tramp_modal_run_init
    EXPORT tramp_modal_calc_dig
    EXPORT tramp_modal_exchange_weapon
    EXPORT tramp_modal_direction_prompt
    EXPORT tramp_ui_character
    EXPORT tramp_ui_inventory
    EXPORT tramp_ui_equipment
    EXPORT tramp_ui_look
    EXPORT tramp_ui_identify_sym
    EXPORT tramp_ui_select_display
    EXPORT tramp_ui_msg_history
    EXPORT tramp_help_screen
    EXPORT tramp_help_wizard
    EXPORT tramp_death_screen
    EXPORT tramp_death_hiscores
    EXPORT tramp_death_recall
    EXPORT tramp_death_royal
    ; M4 OVL_MODAL (+15..+33)
    EXPORT tramp_modal_player_attack
    EXPORT tramp_modal_kill_monster
    EXPORT tramp_modal_populate_town
    EXPORT tramp_modal_populate_dungeon
    EXPORT tramp_modal_place_wanderer
    EXPORT tramp_modal_award_xp
    EXPORT tramp_modal_run_area_affect
    ; M4 OVL_MON_EXT (18)
    EXPORT tramp_mon_ext_attack
    EXPORT tramp_mon_ext_cast
    EXPORT tramp_mon_ext_acid_armour
    ; M4 OVL_ITEM_MGT (19)
    EXPORT tramp_item_mgt_pickup
    EXPORT tramp_item_mgt_wear
    EXPORT tramp_item_mgt_takeoff
    EXPORT tramp_item_mgt_drop
    EXPORT tramp_item_mgt_eat
    EXPORT tramp_item_mgt_refuel
    EXPORT tramp_item_mgt_fire
    EXPORT tramp_item_mgt_throw
    EXPORT tramp_item_mgt_roll_enchant
    EXPORT tramp_item_mgt_select_inv
    ; M4 OVL_ITEMS (7)
    EXPORT tramp_items_quaff
    EXPORT tramp_items_read
    EXPORT tramp_items_aim
    EXPORT tramp_items_use
    EXPORT tramp_items_pseudo_id
    EXPORT tramp_items_eat_ext
    EXPORT tramp_items_world_cold
    ; M4 OVL_ITEMS_EFF (15)
    EXPORT tramp_items_eff_scroll
    EXPORT tramp_items_eff_wand
    EXPORT tramp_items_eff_staff
    EXPORT tramp_items_eff_spawn_level
    EXPORT tramp_items_eff_identify
    EXPORT tramp_items_eff_teleport
    EXPORT tramp_items_eff_summon_many
    ; M4 OVL_SPELL (8)
    EXPORT tramp_spell_cast
    EXPORT tramp_spell_pray
    EXPORT tramp_spell_gain
    EXPORT tramp_spell_recalc_levelup
    ; M4 OVL_SPELL_EFF (16)
    EXPORT tramp_spell_eff_execute
    EXPORT tramp_spell_eff_bolt
    EXPORT tramp_spell_eff_ball
    EXPORT tramp_spell_eff_poly
    EXPORT tramp_spell_eff_area

; ---------------------------------------------------------------------------
; overlay_trampoline — 6-byte inline-descriptor overlay dispatcher.
; Stack at entry: [desc_ptr, caller_ret]
; ---------------------------------------------------------------------------
overlay_trampoline:
    ; Save caller registers above [desc_ptr, caller_ret].
    ; Stack layout relative to SP after pushes:
    ;   SP+0..1  : orig_HL
    ;   SP+2..3  : orig_DE
    ;   SP+4..5  : orig_BC
    ;   SP+6..7  : orig_AF
    ;   SP+8..9  : desc_ptr (overwritten in-place with target_addr!)
    ;   SP+10..11: caller_ret
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    LD   HL, 8
    ADD  HL, SP
    LD   E, (HL)
    INC  HL
    LD   D, (HL)                ; DE = desc_ptr; HL = &SP+9
    EX   DE, HL                 ; HL = desc_ptr, DE = &SP+9
    LD   C, (HL)                ; C = target_ovl_id
    INC  HL
    LD   B, (HL)                ; B = target_addr lo
    INC  HL
    LD   A, (HL)                ; A = target_addr hi
    EX   DE, HL                 ; HL = &SP+9
    LD   (HL), A                ; SP+9 = target_addr hi
    DEC  HL
    LD   (HL), B                ; SP+8 = target_addr lo (desc_ptr consumed!)

    ; Same-overlay fast path: zero disk I/O and zero ovl_stack push
    LD   A, (abi_current_overlay)
    CP   C
    JR   NZ, .cross_overlay

    POP  HL
    POP  DE
    POP  BC
    POP  AF
    RET                         ; pops target_addr into PC, leaving [caller_ret]

.cross_overlay:
    LD   A, (abi_overlay_depth)
    CP   OVL_STACK_MAX
    JR   C, .depth_ok

    ; Nested overlay stack overflow: panic cleanly via BDOS 9 + BDOS 0
    LD   C, BDOS_PRTSTR
    LD   DE, .str_ovl_overflow
    CALL bdos_call
    LD   C, BDOS_TERM
    LD   DE, 0
    JP   bdos_call

.depth_ok:
    ; Push previous abi_current_overlay onto ovl_stack[depth] and increment depth
    LD   E, A
    LD   D, 0
    LD   HL, ovl_stack
    ADD  HL, DE
    LD   A, (abi_current_overlay)
    LD   (HL), A
    LD   A, E
    INC  A
    LD   (abi_overlay_depth), A

    ; Stream target overlay into OVL_WINDOW_BASE (0x5600..0x69FF)
    LD   A, C
    CALL overlay_load
    JR   C, .load_failed

    ; Insert .after_target return address between target_addr and caller_ret
    ; by copying the 8 saved register bytes down 2 bytes on the stack.
    PUSH HL                     ; allocate 2 bytes at SP+0..1
    LD   HL, 0
    ADD  HL, SP
    LD   E, L
    LD   D, H                   ; DE = SP+0
    INC  HL
    INC  HL                     ; HL = SP+2 (orig_HL)
    LD   BC, 8
    LDIR                        ; SP+0..7 = orig_HL..orig_AF; DE=SP+8, HL=SP+10
    LDI                         ; SP+8 = target_lo
    LDI                         ; SP+9 = target_hi; HL = SP+12
    DEC  HL
    LD   (HL), HIGH(.after_target)
    DEC  HL
    LD   (HL), LOW(.after_target)

    POP  HL
    POP  DE
    POP  BC
    POP  AF
    RET                         ; enters target_addr with [.after_target, caller_ret]

.after_target:
    ; Preserve target return registers across caller overlay reload
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    LD   A, (abi_overlay_depth)
    DEC  A
    LD   (abi_overlay_depth), A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_stack
    ADD  HL, DE
    LD   A, (HL)                ; A = previous overlay ID
    OR   A
    JR   Z, .prev_is_none

    CALL overlay_load
    JR   C, .reload_failed
    JR   .restore_ret

.prev_is_none:
    XOR  A
    LD   (abi_current_overlay), A

.restore_ret:
    POP  HL
    POP  DE
    POP  BC
    POP  AF
    RET                         ; returns directly to caller_ret

.load_failed:
    ; Unwind ovl_stack depth and ensure abi_current_overlay = OVL_NONE
    XOR  A
    LD   (abi_current_overlay), A
    LD   A, (abi_overlay_depth)
    DEC  A
    LD   (abi_overlay_depth), A
    LD   E, A
    LD   D, 0
    LD   HL, ovl_stack
    ADD  HL, DE
    LD   A, (HL)                ; A = previous overlay ID
    OR   A
    JR   Z, .fail_to_resident

    ; Caller was inside an overlay whose 0x5600 window may be dirty -> restore it
    CALL overlay_load
    JR   C, .reload_failed

.fail_to_resident:
    POP  HL
    POP  DE
    POP  BC
    POP  AF
    INC  SP                     ; discard target_addr slot without clobbering AF
    INC  SP
    SCF
    RET                         ; returns to caller_ret with CF=1

.reload_failed:
    LD   C, BDOS_PRTSTR
    LD   DE, .str_ovl_reload_err
    CALL bdos_call
    LD   C, BDOS_TERM
    LD   DE, 0
    JP   bdos_call

.str_ovl_overflow:
    DB   "Overlay stack overflow.", 0x0D, 0x0A, "$"
.str_ovl_reload_err:
    DB   "Overlay reload failed.", 0x0D, 0x0A, "$"

; ============================================================
; Public 6-Byte Resident Overlay Trampoline Stubs
; ============================================================

tramp_title_menu:
    CALL overlay_trampoline
    DB   OVL_TITLE
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_title_menu) == 6

tramp_legal_viewer:
    CALL overlay_trampoline
    DB   OVL_LEGAL
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_legal_viewer) == 6

tramp_legal_sysinfo:
    CALL overlay_trampoline
    DB   OVL_LEGAL
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_legal_sysinfo) == 6

tramp_player_create:
    CALL overlay_trampoline
    DB   OVL_START
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_player_create) == 6

tramp_init_new_world:
    CALL overlay_trampoline
    DB   OVL_START
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_init_new_world) == 6

tramp_gen_town:
    CALL overlay_trampoline
    DB   OVL_GEN
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_gen_town) == 6

tramp_gen_dungeon:
    CALL overlay_trampoline
    DB   OVL_GEN
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_gen_dungeon) == 6

tramp_store_enter:
    CALL overlay_trampoline
    DB   OVL_TOWN
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_store_enter) == 6

tramp_town_restock_all:
    CALL overlay_trampoline
    DB   OVL_TOWN
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_town_restock_all) == 6

tramp_home_enter:
    CALL overlay_trampoline
    DB   OVL_HOME
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_home_enter) == 6

tramp_save_game:
    CALL overlay_trampoline
    DB   OVL_STORAGE
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_save_game) == 6

tramp_load_menu:
    CALL overlay_trampoline
    DB   OVL_STORAGE
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_load_menu) == 6

tramp_disk_setup:
    CALL overlay_trampoline
    DB   OVL_STORAGE
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_disk_setup) == 6

tramp_hiscore_load:
    CALL overlay_trampoline
    DB   OVL_STORAGE
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_hiscore_load) == 6

tramp_hiscore_save:
    CALL overlay_trampoline
    DB   OVL_STORAGE
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_hiscore_save) == 6

; M3 Overlay Dispatchers: OVL_ACTIONS (17), OVL_CHEST (10), OVL_MODAL (9),
;                         OVL_UI (6), OVL_HELP (5), OVL_DEATH (3)
tramp_actions_open:
    CALL overlay_trampoline
    DB   OVL_ACTIONS
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_actions_open) == 6

tramp_actions_close:
    CALL overlay_trampoline
    DB   OVL_ACTIONS
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_actions_close) == 6

tramp_actions_search:
    CALL overlay_trampoline
    DB   OVL_ACTIONS
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_actions_search) == 6

tramp_actions_disarm:
    CALL overlay_trampoline
    DB   OVL_ACTIONS
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_actions_disarm) == 6

tramp_actions_bash:
    CALL overlay_trampoline
    DB   OVL_ACTIONS
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_actions_bash) == 6

tramp_actions_tunnel:
    CALL overlay_trampoline
    DB   OVL_ACTIONS
    DW   OVL_ENTRY_VEC_5
    ASSERT ($ - tramp_actions_tunnel) == 6

tramp_actions_trigger_trap:
    CALL overlay_trampoline
    DB   OVL_ACTIONS
    DW   OVL_ENTRY_VEC_6
    ASSERT ($ - tramp_actions_trigger_trap) == 6

tramp_actions_jam:
    CALL overlay_trampoline
    DB   OVL_ACTIONS
    DW   OVL_ENTRY_VEC_7
    ASSERT ($ - tramp_actions_jam) == 6

tramp_chest_open:
    CALL overlay_trampoline
    DB   OVL_CHEST
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_chest_open) == 6

tramp_chest_disarm:
    CALL overlay_trampoline
    DB   OVL_CHEST
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_chest_disarm) == 6

tramp_chest_search:
    CALL overlay_trampoline
    DB   OVL_CHEST
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_chest_search) == 6

tramp_chest_fulfill_loot:
    CALL overlay_trampoline
    DB   OVL_CHEST
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_chest_fulfill_loot) == 6

tramp_chest_pick_item:
    CALL overlay_trampoline
    DB   OVL_CHEST
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_chest_pick_item) == 6

tramp_modal_recalc_equipment:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_modal_recalc_equipment) == 6

tramp_modal_run_init:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_modal_run_init) == 6

tramp_modal_calc_dig:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_modal_calc_dig) == 6

tramp_modal_exchange_weapon:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_modal_exchange_weapon) == 6

tramp_modal_direction_prompt:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_modal_direction_prompt) == 6

tramp_ui_character:
    CALL overlay_trampoline
    DB   OVL_UI
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_ui_character) == 6

tramp_ui_inventory:
    CALL overlay_trampoline
    DB   OVL_UI
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_ui_inventory) == 6

tramp_ui_equipment:
    CALL overlay_trampoline
    DB   OVL_UI
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_ui_equipment) == 6

tramp_ui_look:
    CALL overlay_trampoline
    DB   OVL_UI
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_ui_look) == 6

tramp_ui_identify_sym:
    CALL overlay_trampoline
    DB   OVL_UI
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_ui_identify_sym) == 6

tramp_ui_select_display:
    CALL overlay_trampoline
    DB   OVL_UI
    DW   OVL_ENTRY_VEC_5
    ASSERT ($ - tramp_ui_select_display) == 6

tramp_ui_msg_history:
    CALL overlay_trampoline
    DB   OVL_UI
    DW   OVL_ENTRY_VEC_6
    ASSERT ($ - tramp_ui_msg_history) == 6

tramp_help_screen:
    CALL overlay_trampoline
    DB   OVL_HELP
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_help_screen) == 6

tramp_help_wizard:
    CALL overlay_trampoline
    DB   OVL_HELP
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_help_wizard) == 6

tramp_death_screen:
    CALL overlay_trampoline
    DB   OVL_DEATH
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_death_screen) == 6

tramp_death_hiscores:
    CALL overlay_trampoline
    DB   OVL_DEATH
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_death_hiscores) == 6

tramp_death_recall:
    CALL overlay_trampoline
    DB   OVL_DEATH
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_death_recall) == 6

tramp_death_royal:
    CALL overlay_trampoline
    DB   OVL_DEATH
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_death_royal) == 6

; M4 Overlay Dispatchers:
;   OVL_MODAL (9, +15..+30), OVL_MON_EXT (18), OVL_ITEM_MGT (19),
;   OVL_ITEMS (7), OVL_ITEMS_EFF (15), OVL_SPELL (8), OVL_SPELL_EFF (16)
tramp_modal_player_attack:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_5
    ASSERT ($ - tramp_modal_player_attack) == 6

tramp_modal_kill_monster:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_6
    ASSERT ($ - tramp_modal_kill_monster) == 6

tramp_modal_populate_town:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_7
    ASSERT ($ - tramp_modal_populate_town) == 6

tramp_modal_populate_dungeon:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_8
    ASSERT ($ - tramp_modal_populate_dungeon) == 6

tramp_modal_place_wanderer:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_9
    ASSERT ($ - tramp_modal_place_wanderer) == 6

tramp_modal_award_xp:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_10
    ASSERT ($ - tramp_modal_award_xp) == 6

tramp_modal_run_area_affect:
    CALL overlay_trampoline
    DB   OVL_MODAL
    DW   OVL_ENTRY_VEC_11
    ASSERT ($ - tramp_modal_run_area_affect) == 6

tramp_mon_ext_attack:
    CALL overlay_trampoline
    DB   OVL_MON_EXT
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_mon_ext_attack) == 6

tramp_mon_ext_cast:
    CALL overlay_trampoline
    DB   OVL_MON_EXT
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_mon_ext_cast) == 6

tramp_mon_ext_acid_armour:
    CALL overlay_trampoline
    DB   OVL_MON_EXT
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_mon_ext_acid_armour) == 6

tramp_item_mgt_pickup:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_item_mgt_pickup) == 6

tramp_item_mgt_wear:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_item_mgt_wear) == 6

tramp_item_mgt_takeoff:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_item_mgt_takeoff) == 6

tramp_item_mgt_drop:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_item_mgt_drop) == 6

tramp_item_mgt_eat:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_item_mgt_eat) == 6

tramp_item_mgt_refuel:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_5
    ASSERT ($ - tramp_item_mgt_refuel) == 6

tramp_item_mgt_fire:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_6
    ASSERT ($ - tramp_item_mgt_fire) == 6

tramp_item_mgt_throw:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_7
    ASSERT ($ - tramp_item_mgt_throw) == 6

tramp_item_mgt_roll_enchant:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_8
    ASSERT ($ - tramp_item_mgt_roll_enchant) == 6

tramp_item_mgt_select_inv:
    CALL overlay_trampoline
    DB   OVL_ITEM_MGT
    DW   OVL_ENTRY_VEC_9
    ASSERT ($ - tramp_item_mgt_select_inv) == 6

tramp_items_quaff:
    CALL overlay_trampoline
    DB   OVL_ITEMS
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_items_quaff) == 6

tramp_items_read:
    CALL overlay_trampoline
    DB   OVL_ITEMS
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_items_read) == 6

tramp_items_aim:
    CALL overlay_trampoline
    DB   OVL_ITEMS
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_items_aim) == 6

tramp_items_use:
    CALL overlay_trampoline
    DB   OVL_ITEMS
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_items_use) == 6

tramp_items_pseudo_id:
    CALL overlay_trampoline
    DB   OVL_ITEMS
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_items_pseudo_id) == 6

tramp_items_eat_ext:
    CALL overlay_trampoline
    DB   OVL_ITEMS
    DW   OVL_ENTRY_VEC_5
    ASSERT ($ - tramp_items_eat_ext) == 6

tramp_items_world_cold:
    CALL overlay_trampoline
    DB   OVL_ITEMS
    DW   OVL_ENTRY_VEC_6
    ASSERT ($ - tramp_items_world_cold) == 6

tramp_items_eff_scroll:
    CALL overlay_trampoline
    DB   OVL_ITEMS_EFF
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_items_eff_scroll) == 6

tramp_items_eff_wand:
    CALL overlay_trampoline
    DB   OVL_ITEMS_EFF
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_items_eff_wand) == 6

tramp_items_eff_staff:
    CALL overlay_trampoline
    DB   OVL_ITEMS_EFF
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_items_eff_staff) == 6

tramp_items_eff_spawn_level:
    CALL overlay_trampoline
    DB   OVL_ITEMS_EFF
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_items_eff_spawn_level) == 6

tramp_items_eff_identify:
    CALL overlay_trampoline
    DB   OVL_ITEMS_EFF
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_items_eff_identify) == 6

tramp_items_eff_teleport:
    CALL overlay_trampoline
    DB   OVL_ITEMS_EFF
    DW   OVL_ENTRY_VEC_5
    ASSERT ($ - tramp_items_eff_teleport) == 6

tramp_items_eff_summon_many:
    CALL overlay_trampoline
    DB   OVL_ITEMS_EFF
    DW   OVL_ENTRY_VEC_6
    ASSERT ($ - tramp_items_eff_summon_many) == 6

tramp_spell_cast:
    CALL overlay_trampoline
    DB   OVL_SPELL
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_spell_cast) == 6

tramp_spell_pray:
    CALL overlay_trampoline
    DB   OVL_SPELL
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_spell_pray) == 6

tramp_spell_gain:
    CALL overlay_trampoline
    DB   OVL_SPELL
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_spell_gain) == 6

tramp_spell_recalc_levelup:
    CALL overlay_trampoline
    DB   OVL_SPELL
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_spell_recalc_levelup) == 6

tramp_spell_eff_execute:
    CALL overlay_trampoline
    DB   OVL_SPELL_EFF
    DW   OVL_ENTRY_VEC_0
    ASSERT ($ - tramp_spell_eff_execute) == 6

tramp_spell_eff_bolt:
    CALL overlay_trampoline
    DB   OVL_SPELL_EFF
    DW   OVL_ENTRY_VEC_1
    ASSERT ($ - tramp_spell_eff_bolt) == 6

tramp_spell_eff_ball:
    CALL overlay_trampoline
    DB   OVL_SPELL_EFF
    DW   OVL_ENTRY_VEC_2
    ASSERT ($ - tramp_spell_eff_ball) == 6

tramp_spell_eff_poly:
    CALL overlay_trampoline
    DB   OVL_SPELL_EFF
    DW   OVL_ENTRY_VEC_3
    ASSERT ($ - tramp_spell_eff_poly) == 6

tramp_spell_eff_area:
    CALL overlay_trampoline
    DB   OVL_SPELL_EFF
    DW   OVL_ENTRY_VEC_4
    ASSERT ($ - tramp_spell_eff_area) == 6

    ENDIF
