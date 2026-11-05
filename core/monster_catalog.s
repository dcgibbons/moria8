#importonce
#if HAL_PLATFORM_MONSTER_CATALOG
// monster_catalog.s — The VMS Moria monster catalog in far memory
// (prototype, docs/MONSTER_CATALOG_DESIGN.md; HAL_PLATFORM_MONSTER_CATALOG).
//
// The whole catalog (tools/build_catalog.py --engine-out) lives in platform
// far memory in the engine's field encoding. Dungeon creature slots
// 0..CAT_SLOTS-1 hold the species met on this level: a pick that names a
// species not yet loaded fetches its fields into a free slot, and decodes its
// Huffman-coded name (the names' own tree) into that slot's entry of the name
// pool. A slot is free when it is empty or no live monster uses it.
// monster_spawn_level empties every slot. The fetch decodes through
// hd_decode_buf: no pick_creature_type caller holds a decoded string across
// the pick (spawn level, special rooms, chest and spell summons, polymorph).
//
// Picks follow VMS 4.8 alloc_monster (misc.inc): 1 in MON_NASTY is out of
// depth, at level dlvl + |randnor(0,4)| + 1 (at most MAX_MONS_LEVEL), with
// VMS's base that lacks + m_level[0]; an out-of-depth pick of a creature this
// port leaves out falls back to the normal pick. The normal pick is uniform
// over the playable creatures of levels 1..dlvl (1..MAX_MONS_LEVEL deeper).
//
// Platform (platforms/shared/catalog/*.s placed by the port's HAL file):
// - catalog_index.s resident, or mapped by :CatalogMap() while picking;
// - catalog_fields.s read by :CatalogFieldRead() = A <- (zp_ptr0),y;
// - catalog_names.s read through the Huffman reads (:HuffDbReadPtr1());
// - the name pool CATALOG_NAME_POOL_BASE, written by :CatalogPoolWrite()
//   = A -> (zp_ptr1),y (A, X, Y kept);
// - :CatalogMap() / :CatalogUnmap() around each pick, fetch or refetch.

.const CAT_SLOTS     = MAX_MONSTERS
.const CAT_NAME_SIZE = 32            // A pool entry: the name and its 0
.const CAT_MON_NASTY = 50            // VMS mon_nasty
.const CAT_WIN_LEVEL = 50            // VMS win_mon_appear
.const CAT_MAX_SIGHT = 20            // VMS max_sight
.const CAT_LEVELS    = CATALOG_MAX_MONS_LEVEL + 1

.assert "Catalog slots fit the dungeon creature rows", CAT_SLOTS <= MAX_DUNGEON_CREATURES, true
.assert "Catalog slots cover every live monster", CAT_SLOTS >= MAX_MONSTERS, true
.assert "Catalog name pool holds one name per slot", CAT_SLOTS * CAT_NAME_SIZE <= CATALOG_NAME_POOL_END - CATALOG_NAME_POOL_BASE + 1, true
.assert "Catalog names fit a pool entry", CATALOG_NAME_MAX < CAT_NAME_SIZE, true
.assert "Catalog town ids end on an availability byte", CATALOG_TOWN_COUNT & 7, 0
.assert "Catalog playable counts follow the raw counts", cat_level_playable, cat_level_raw + CAT_LEVELS
.assert "Catalog fields are the engine's tier fields", CATALOG_SOA_FIELDS, NUM_SOA_FIELDS - 2
.assert "Catalog ids fit 9 bits", CATALOG_COUNT <= 512, true

// Species table: the catalog id in each slot; id hi $FF = empty. Saved as
// one block (save.s door-state table), so the two arrays stay adjacent.
cat_slot_id_lo: .fill CAT_SLOTS, 0
cat_slot_id_hi: .fill CAT_SLOTS, $ff
cat_slot_id_end:
cat_id_lo:  .byte 0
cat_id_hi:  .byte 0
cat_slot:   .byte 0
cat_tmp:    .byte 0
cat_level:  .byte 0

// catalog_reset_slots — Empty every species slot (a new level).
// Clobbers: A, X
catalog_reset_slots:
    ldx #CAT_SLOTS - 1
    lda #$ff
!crs_loop:
    sta cat_slot_id_hi,x
    dex
    bpl !crs_loop-
    lda #0
    sta active_dungeon_count
    rts

// pick_creature_type — Pick a creature for the current dungeon level.
// Output: A = creature slot (0 in town)
// Clobbers: X, Y, zp_temp3, zp_temp4
pick_creature_type:
    lda zp_player_dlvl
    bne !pct_dungeon+
    rts
!pct_dungeon:
    jsr cat_save_zp
    :CatalogMap()
    jsr cat_pick_id
    jmp cat_slot_mapped

// catalog_slot_for_id — The slot of catalog creature cat_id_lo/hi, fetched
// on first use (the win creatures, wizard summons).
// Output: A = creature slot
// Clobbers: X, Y, zp_temp3, zp_temp4
catalog_slot_for_id:
    jsr cat_save_zp
    :CatalogMap()
cat_slot_mapped:
    jsr cat_find_slot           // X = slot; C = 1: the species must be fetched
    stx cat_slot
    bcc !csm_done+
    jsr cat_fetch
    :CatalogUnmap()
    // A new species in the slot: forget the old one's recall.
    lda #0
    ldx cat_slot
    :AuxWriteX(recall_kills)
    :AuxWriteX(recall_deaths)
    :AuxWriteX(recall_attacks)
    :AuxWriteX(recall_spells)
    jmp !csm_restore+
!csm_done:
    :CatalogUnmap()
!csm_restore:
    pla
    sta zp_ptr1_hi
    pla
    sta zp_ptr1
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    pla
    sta zp_temp2
    pla
    sta zp_temp1
    pla
    sta zp_temp0
    lda cat_slot
    rts

// cat_save_zp — Push the zero page the catalog routines use beyond the
// picker contract (zp_temp0-2, zp_ptr0, zp_ptr1) under the caller's return.
// Clobbers: A, X
cat_save_zp:
    pla
    tax                         // Own return address lo
    pla
    sta cat_tmp                 // Own return address hi
    lda zp_temp0
    pha
    lda zp_temp1
    pha
    lda zp_temp2
    pha
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    lda zp_ptr1
    pha
    lda zp_ptr1_hi
    pha
    lda cat_tmp
    pha
    txa
    pha
    rts

// catalog_refetch_slots — Reload every occupied slot's species (after a
// saved game restores the species table). Recall is kept: it was saved.
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
catalog_refetch_slots:
    lda #0
    sta active_dungeon_count
    :CatalogMap()
    ldx #0
!crf_loop:
    stx cat_slot
    lda cat_slot_id_hi,x
    bmi !crf_next+
    sta cat_id_hi
    lda cat_slot_id_lo,x
    sta cat_id_lo
    jsr cat_fetch
!crf_next:
    ldx cat_slot
    inx
    cpx #CAT_SLOTS
    bcc !crf_loop-
    :CatalogUnmap()
    rts

// cat_find_slot — The slot holding cat_id, else a free one.
// Output: X = slot; C = 0 loaded, C = 1 free (fetch needed)
// Clobbers: A, Y, zp_ptr0
cat_find_slot:
    ldx #CAT_SLOTS - 1
!cfs_loop:
    lda cat_slot_id_lo,x
    cmp cat_id_lo
    bne !cfs_next+
    lda cat_slot_id_hi,x
    cmp cat_id_hi
    beq !cfs_loaded+
!cfs_next:
    dex
    bpl !cfs_loop-
    inx                         // X = 0
!cfs_free:
    lda cat_slot_id_hi,x
    bmi !cfs_fresh+             // Empty
    jsr cat_slot_in_use
    bcc !cfs_fresh+
    inx
    cpx #CAT_SLOTS
    bcc !cfs_free-
    // Every slot holds a live species, so all MAX_MONSTERS rows are live and
    // the spawn will find the table full. Reuse slot 0 untouched.
    ldx #0
!cfs_loaded:
    clc
    rts
!cfs_fresh:
    sec
    rts

// cat_slot_in_use — C = 1 when a live monster is of slot X.
// Clobbers: A, Y, zp_ptr0 (X preserved)
cat_slot_in_use:
    stx cat_tmp
    ldx #MAX_MONSTERS - 1
!csiu_loop:
    jsr monster_get_ptr
    ldy #MX_TYPE
    lda (zp_ptr0),y
    cmp cat_tmp
    beq !csiu_used+
    dex
    bpl !csiu_loop-
    ldx cat_tmp
    clc
    rts
!csiu_used:
    ldx cat_tmp
    sec
    rts

// cat_fetch — Copy catalog creature cat_id into slot cat_slot, and decode
// its name into the slot's pool entry (cr_name_lo/hi point there).
// Clobbers: A, X, Y, zp_ptr0, zp_ptr1
cat_fetch:
    ldx cat_slot
    lda cat_id_lo
    sta cat_slot_id_lo,x
    lda cat_id_hi
    sta cat_slot_id_hi,x
    inx
    cpx active_dungeon_count
    bcc !cf_count_ok+
    stx active_dungeon_count
!cf_count_ok:
    clc                         // Field 0 of creature cat_id
    lda #<catalog_fields
    adc cat_id_lo
    sta zp_ptr0
    lda #>catalog_fields
    adc cat_id_hi
    sta zp_ptr0_hi
    ldx #0
!cf_field:
    lda ltb_dst_lo,x
    sta zp_ptr1
    lda ltb_dst_hi,x
    sta zp_ptr1_hi
    ldy #0
    :CatalogFieldRead()
    ldy cat_slot
    sta (zp_ptr1),y
    clc                         // The creature's next field
    lda zp_ptr0
    adc #<CATALOG_COUNT
    sta zp_ptr0
    lda zp_ptr0_hi
    adc #>CATALOG_COUNT
    sta zp_ptr0_hi
    inx
    cpx #CATALOG_SOA_FIELDS
    bne !cf_field-

    // The name: its stream from cat_name_lo/hi[id], decoded with the names' tree.
    clc
    lda #<cat_name_lo
    adc cat_id_lo
    sta zp_ptr1
    lda #>cat_name_lo
    adc cat_id_hi
    sta zp_ptr1_hi
    ldy #0
    :HuffDbReadPtr1()
    pha                         // Stream lo
    clc
    lda zp_ptr1
    adc #<CATALOG_COUNT
    sta zp_ptr1
    lda zp_ptr1_hi
    adc #>CATALOG_COUNT
    sta zp_ptr1_hi
    :HuffDbReadPtr1()
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    ldx #3
!cf_tree:
    lda cat_names_tree,x
    sta hd_tree_left_ptr,x
    dex
    bpl !cf_tree-
    jsr huff_decode_from_ptr    // hd_decode_buf
    ldx #3
!cf_corpus:
    lda cat_corpus_tree,x
    sta hd_tree_left_ptr,x
    dex
    bpl !cf_corpus-

    // Pool entry: CATALOG_NAME_POOL_BASE + slot * 32.
    lda cat_slot
    lsr
    lsr
    lsr
    sta zp_ptr1_hi
    lda cat_slot
    asl
    asl
    asl
    asl
    asl
    clc
    adc #<CATALOG_NAME_POOL_BASE
    sta zp_ptr1
    ldx cat_slot
    sta cr_name_lo,x
    lda zp_ptr1_hi
    adc #>CATALOG_NAME_POOL_BASE
    sta zp_ptr1_hi
    sta cr_name_hi,x
    ldy #$ff
!cf_name:
    iny
    lda hd_decode_buf,y
    :CatalogPoolWrite()
    lda hd_decode_buf,y
    bne !cf_name-
    rts
.assert "Catalog slot name entries are 32 bytes", CAT_NAME_SIZE, 32
.assert "hd_tree_right_ptr follows hd_tree_left_ptr", hd_tree_right_ptr, hd_tree_left_ptr + 2

// The decoder's tree pointers: the names' tree, then the corpus's back.
cat_names_tree:  .word catn_tree_left, catn_tree_right
cat_corpus_tree: .word huff_tree_left, huff_tree_right

// cat_pick_id — VMS alloc_monster's creature for zp_player_dlvl > 0.
// Fields bank mapped. Output: cat_id_lo/hi
// Clobbers: A, X, Y, zp_temp0-zp_temp4
cat_pick_id:
    lda zp_player_dlvl
    cmp #CAT_LEVELS
    bcc !cpi_in_range+
    lda #CATALOG_MAX_MONS_LEVEL     // Deeper than the catalog: no out-of-depth roll
    sta cat_level
    bne !cpi_normal+
!cpi_in_range:
    sta cat_level
    lda #CAT_MON_NASTY
    jsr rng_range
    bne !cpi_normal+
    // Out of depth: T = dlvl + |randnor(0,4)| + 1. The sum of four rolls of
    // 0-6 less 12 has mean 0 and standard deviation 4.
    lda #<-12
    sta cat_tmp
    ldy #4
!cpi_nor:
    lda #7
    jsr rng_range               // Preserves Y
    clc
    adc cat_tmp
    sta cat_tmp
    dey
    bne !cpi_nor-
    lda cat_tmp
    bpl !cpi_abs+
    eor #$ff
    clc
    adc #1
!cpi_abs:
    sec                         // + 1
    adc cat_level
    cmp #CAT_LEVELS
    bcc !cpi_t_ok+
    lda #CATALOG_MAX_MONS_LEVEL
!cpi_t_ok:
    sta cat_tmp                 // T
    // id = base + randint(count[T]), base = m_level[T-1] as VMS sums it:
    // the town count for T = 1, else levels 1..T-1 without the town (VMS
    // misc.inc alloc_monster lacks + m_level[0]).
    tay
    dey
    ldx #0
    jsr cat_sum_levels          // zp_temp0/1 = raw count of levels 1..T-1
    lda cat_tmp
    cmp #1
    bne !cpi_base+
    lda #CATALOG_TOWN_COUNT
    sta zp_temp0
!cpi_base:
    ldx cat_tmp
    lda cat_level_raw,x
    jsr rng_range
    clc
    adc zp_temp0
    sta cat_id_lo
    lda zp_temp1
    adc #0
    sta cat_id_hi
    // Playable? (id / 8 is at most 34; the bit is recall_spell_bit[id & 7])
    lsr
    lda cat_id_lo
    ror
    lsr
    lsr
    tax
    lda cat_id_lo
    and #7
    tay
    lda cat_available,x
    and recall_spell_bit,y
    beq !cpi_normal+
    rts
!cpi_normal:
    // The r-th playable creature of levels 1..L, walking ids up from the town.
    ldx #CAT_LEVELS             // The playable counts
    ldy cat_level
    jsr cat_sum_levels
    jsr rng_range_word          // zp_temp2/3 = r
    lda #CATALOG_TOWN_COUNT
    sta cat_id_lo
    lda #0
    sta cat_id_hi
    lda #1
    sta cat_tmp                 // Availability bit of cat_id
    ldx #CATALOG_TOWN_COUNT / 8
!cpi_walk:
    lda cat_available,x
    and cat_tmp
    beq !cpi_next+
    lda zp_temp2
    ora zp_temp3
    beq !cpi_done+
    lda zp_temp2
    bne !cpi_dec_lo+
    dec zp_temp3
!cpi_dec_lo:
    dec zp_temp2
!cpi_next:
    inc cat_id_lo
    bne !cpi_id_ok+
    inc cat_id_hi
!cpi_id_ok:
    asl cat_tmp
    bcc !cpi_walk-
    rol cat_tmp                 // Bit 0 of the next byte
    inx
    bne !cpi_walk-
!cpi_done:
    rts

// cat_sum_levels — zp_temp0/1 = sum of cat_level_raw[X+1 .. X+Y].
// Clobbers: A, X, Y
cat_sum_levels:
    lda #0
    sta zp_temp0
    sta zp_temp1
    cpy #0
    beq !csl_done+
!csl_loop:
    inx
    lda cat_level_raw,x
    clc
    adc zp_temp0
    sta zp_temp0
    bcc !csl_next+
    inc zp_temp1
!csl_next:
    dey
    bne !csl_loop-
!csl_done:
    rts

// catalog_population — VMS's monster count for a new level:
// randint(8) + 14 + alloc_level, alloc_level = dlvl / 3 within 2..10.
// VMS's map is this port's 198x66, so no area scale applies.
// Output: A = count
// Clobbers: X, Y, zp_temp3, zp_temp4, zp_math_a/b
catalog_population:
    lda zp_player_dlvl
    sta zp_math_a
    lda #0
    sta zp_math_b
    ldx #3
    jsr math_div_16x8
    lda zp_math_a
    cmp #2
    bcs !cp_lo_ok+
    lda #2
!cp_lo_ok:
    cmp #11
    bcc !cp_hi_ok+
    lda #10
!cp_hi_ok:
    sta cat_tmp
    lda #8
    jsr rng_range
    sec                         // randint(8) = rng_range(8) + 1
    adc #14
    adc cat_tmp
    rts
.assert "Catalog population matches VMS's map size", MAP_COLS * MAP_ROWS, 198 * 66

// catalog_place_win_creature — From VMS win_mon_appear on, until the game is
// won, an awake Evil Iggy or Balrog lands beyond sight of the player (VMS
// misc.inc place_win_monster).
// Clobbers: everything
catalog_place_win_creature:
    lda zp_player_dlvl
    cmp #CAT_WIN_LEVEL
    bcc !cpw_done+
    lda zp_game_flags
    and #GAME_FLAG_WINNER
    bne !cpw_done+
    lda #32
    sta cat_level               // Placement tries
!cpw_try:
    jsr find_monster_floor
    bcc !cpw_retry+
    lda ms_spawn_x
    sec
    sbc zp_player_x
    bcs !cpw_dx+
    eor #$ff
    adc #1
!cpw_dx:
    cmp #CAT_MAX_SIGHT + 1
    bcs !cpw_place+
    lda ms_spawn_y
    sec
    sbc zp_player_y
    bcs !cpw_dy+
    eor #$ff
    adc #1
!cpw_dy:
    cmp #CAT_MAX_SIGHT + 1
    bcs !cpw_place+
!cpw_retry:
    dec cat_level
    bne !cpw_try-
!cpw_done:
    rts
!cpw_place:
    lda #2
    jsr rng_range
    clc
    adc #<CATALOG_IGGY_ID
    sta cat_id_lo
    lda #>CATALOG_IGGY_ID
    sta cat_id_hi
    jsr catalog_slot_for_id
    jsr monster_spawn_one
    bcc !cpw_done-
    jmp monster_wake
.assert "Catalog win creatures are adjacent", CATALOG_BALROG_ID, CATALOG_IGGY_ID + 1
.assert "Catalog win ids share a high byte", >CATALOG_IGGY_ID, >CATALOG_BALROG_ID

// catalog_slot_is_balrog — Z = 1 when slot X holds the Balrog.
// Clobbers: A
catalog_slot_is_balrog:
    cpx #CAT_SLOTS
    bcs !csib_no+
    lda cat_slot_id_lo,x
    cmp #<CATALOG_BALROG_ID
    bne !csib_no+
    lda cat_slot_id_hi,x
    cmp #>CATALOG_BALROG_ID
    rts
!csib_no:
    lda #1                      // Z = 0
    rts
#endif
