#importonce
// item_pickup_cache.s — Active-level ITEM.CAT weight + decoded-string RAM cache
//
// Module ownership:
//   owner: Hot lookup/insert + cursor BSS live in Resident Default (< MAP_BASE,
//     asserted by item_pickup_cache_hot_end <= MAP_BASE) on 64 KB Commodore disk
//     ports defining HAL_PLATFORM_ITEM_PICKUP_CACHE (!C64_CARTRIDGE and
//     !PLUS4_CARTRIDGE); prewarm routines (item_pickup_cache_warm_floor /
//     item_pickup_cache_prewarm) default to Default or route via optional
//     ItemPickupCachePrewarmSegment (e.g. RuntimeBanked on ports whose banked
//     RAM stays visible across KERNAL wrappers). Backing storage lives in
//     port-supplied ITEM_PICKUP_CACHE_BASE..+SIZE-1 (470 B hidden RAM on C64,
//     432 B low RAM $0600-$07AF on Plus/4). Excluded (0 B) on C128, cartridge builds, and
//     non-Commodore ports.
//   lifetime: Active level and session read-through cache; invalidated via
//     item_pickup_cache_invalidate before generation scratch reuse and reset +
//     pre-warmed on level entry / save resume via item_pickup_cache_prewarm, with
//     incremental floor-only warm on chest/monster drops via item_pickup_cache_warm_floor.
//   callers: item_get_weight_x (core/item_tables.s), item_cat_decode_entry_at_dst
//     (core/item_catalog.s), game_new_start / load_resume_game /
//     level_change_generate_current (core/game_loop.s), chest_fulfill_loot
//     (core/chest_loot.s), and port generation invalidation hooks. Hot lookup/
//     insert callers may arrive with any overlay at $E000 or from banked runtime
//     at $F000, so hot code and cursor BSS stay resident below MAP_BASE.
//
// Unified packed record pool in [ITEM_PICKUP_CACHE_BASE, ipc_end):
//   byte 0: rec_len (5 for weight; 3 + char_len for string)
//   byte 1: key_lo  (slot_lo for weight; icat_str_id_lo for string)
//   byte 2: key_hi  ($80 | page_bit for weight; icat_str_id_hi $00..$02 for string)
//   byte 3..rec_len-1: [weight_lo, weight_hi] or decoded characters
// Zero new zero-page bytes ($02-$8F untouched).

#if HAL_PLATFORM_ITEM_PICKUP_CACHE

.const IPC_POOL_END = ITEM_PICKUP_CACHE_BASE + ITEM_PICKUP_CACHE_SIZE

.assert "Item pickup cache sits above page 1", ITEM_PICKUP_CACHE_BASE >= $0200, true
// Each port names its floor (C64 464 B; Plus/4 432 B, all it has between its
// KERNAL workspaces): a smaller pool falls back to ITEM.CAT reads sooner.
.assert "Item pickup cache size meets the port's minimum", ITEM_PICKUP_CACHE_SIZE >= ITEM_PICKUP_CACHE_MIN_SIZE, true
.assert "Item pickup cache fits within non-wrapping 16-bit span", IPC_POOL_END <= $ff00, true
.assert "item_name_decode_buf does not overlap item pickup cache", (item_name_decode_buf + ITEM_NAME_DECODE_BUF_SIZE <= ITEM_PICKUP_CACHE_BASE) || (item_name_decode_buf >= IPC_POOL_END), true

// Resident cache state (10 bytes BSS, zero ZP)
ipc_end_lo:        .byte <ITEM_PICKUP_CACHE_BASE
ipc_end_hi:        .byte >ITEM_PICKUP_CACHE_BASE
ipc_key_lo:        .byte 0
ipc_key_hi:        .byte 0
ipc_rec_len:       .byte 0
ipc_pool_overflow: .byte 0
ipc_save_x:        .byte 0
ipc_warm_idx:      .byte 0
ipc_warm_id:       .byte 0
ipc_warm_ego:      .byte 0

// item_pickup_cache_invalidate — Reset resident cache cursors without touching
// ITEM_PICKUP_CACHE_BASE. Safe during generation scratch reuse.
// Preserves: A, X, Y, processor flags (P).
item_pickup_cache_invalidate:
    php
    pha
    lda #0
    sta ipc_pool_overflow
    lda #<ITEM_PICKUP_CACHE_BASE
    sta ipc_end_lo
    lda #>ITEM_PICKUP_CACHE_BASE
    sta ipc_end_hi
    pla
    plp
    rts

// item_pickup_cache_get_weight_x — Cached item_get_weight_x for (item_cur_page, X).
// Output: icat_weight_lo/hi loaded, A = icat_weight_lo.
// Preserves: X, Y, and all zero-page.
item_pickup_cache_get_weight_x:
    stx ipc_save_x
    sty it_save_y
    lda zp_ptr0
    pha
    lda zp_ptr0_hi
    pha
    stx ipc_key_lo
    lda item_cur_page
    and #ITEM_PAGE_BIT
    ora #$80
    sta ipc_key_hi
    jsr ipc_lookup
    bne !ipcw_done+
    ldx ipc_save_x
    txa
    jsr item_cat_select_id
    jsr item_cat_get_weight
    lda #5
    jsr ipc_insert
!ipcw_done:
    pla
    sta zp_ptr0_hi
    pla
    sta zp_ptr0
    ldx ipc_save_x
    ldy it_save_y
    lda icat_weight_lo
    rts

// item_pickup_cache_decode_entry_at_dst — Cached item_cat_decode_entry_at_dst
// keyed by immutable 16-bit icat_str_id (0..360 item, 361..415 ego, 416..589 flavour).
// Output: zp_ptr0/hi -> item_name_decode_buf (NUL-terminated). Preserves: X.
item_pickup_cache_decode_entry_at_dst:
    ldy item_name_dst_idx
    bne !ipcd_uncached+
    stx ipc_save_x
    lda icat_str_id_lo
    sta ipc_key_lo
    lda icat_str_id_hi
    sta ipc_key_hi
    jsr ipc_lookup
    bne !ipcd_done+
    ldx ipc_save_x
    jsr item_cat_decode_entry_uncached
    lda item_name_dst_idx
    clc
    adc #3
    jsr ipc_insert
!ipcd_done:
    lda #<item_name_decode_buf
    sta zp_ptr0
    lda #>item_name_decode_buf
    sta zp_ptr0_hi
    ldx ipc_save_x
    rts
!ipcd_uncached:
    jmp item_cat_decode_entry_uncached

// ipc_lookup — Scan [ITEM_PICKUP_CACHE_BASE, ipc_end) for (ipc_key_lo, ipc_key_hi).
// On hit: populates icat_weight_lo/hi (key_hi bit 7 = 1) or item_name_decode_buf +
//         item_name_dst_idx (key_hi bit 7 = 0), returns Z = 0 (A = $FF).
// On miss: returns Z = 1 (A = 0).
ipc_lookup:
    lda #<ITEM_PICKUP_CACHE_BASE
    sta zp_ptr0
    lda #>ITEM_PICKUP_CACHE_BASE
    sta zp_ptr0_hi
    ldx #0
    :ItemPickupCacheMap()
!ipcl_loop:
    lda zp_ptr0
    cmp ipc_end_lo
    bne !ipcl_chk+
    lda zp_ptr0_hi
    cmp ipc_end_hi
    beq !ipcl_unmap+
!ipcl_chk:
    ldy #1
    lda (zp_ptr0),y
    cmp ipc_key_lo
    bne !ipcl_step+
    iny
    lda (zp_ptr0),y
    cmp ipc_key_hi
    beq !ipcl_hit+
!ipcl_step:
    ldy #0
    lda (zp_ptr0),y
    beq !ipcl_unmap+
    clc
    adc zp_ptr0
    sta zp_ptr0
    bcc !ipcl_loop-
    inc zp_ptr0_hi
    bne !ipcl_loop-

!ipcl_hit:
    ldy #0
    lda (zp_ptr0),y
    sta ipc_rec_len
    ldy #3
    bit ipc_key_hi
    bpl !ipcl_copy_str+
    lda (zp_ptr0),y
    sta icat_weight_lo
    iny
    lda (zp_ptr0),y
    sta icat_weight_hi
    dex
    bmi !ipcl_unmap+
!ipcl_copy_str:
    cpy ipc_rec_len
    bcs !ipcl_str_done+
    lda (zp_ptr0),y
    sta item_name_decode_buf,x
    inx
    iny
    bne !ipcl_copy_str-
!ipcl_str_done:
    lda #0
    sta item_name_decode_buf,x
    stx item_name_dst_idx
    ldx #$ff
!ipcl_unmap:
    :ItemPickupCacheUnmap()
    txa
    rts

// ipc_insert — Append record of total length A with (ipc_key_lo, ipc_key_hi) if room.
ipc_insert:
    sta ipc_rec_len
    clc
    adc ipc_end_lo
    tay
    lda ipc_end_hi
    adc #0
    cmp #>IPC_POOL_END
    bcc !ipci_fits+
    bne !ipci_full+
    cpy #<IPC_POOL_END
    beq !ipci_fits+
    bcs !ipci_full+
!ipci_fits:
    pha
    tya
    pha
    lda ipc_end_lo
    sta zp_ptr0
    lda ipc_end_hi
    sta zp_ptr0_hi
    :ItemPickupCacheMap()
    ldy #0
    lda ipc_rec_len
    sta (zp_ptr0),y
    iny
    lda ipc_key_lo
    sta (zp_ptr0),y
    iny
    lda ipc_key_hi
    sta (zp_ptr0),y
    iny
    bit ipc_key_hi
    bpl !ipci_str+
    lda icat_weight_lo
    sta (zp_ptr0),y
    iny
    lda icat_weight_hi
    sta (zp_ptr0),y
    jmp !ipci_unmap+
!ipci_str:
    ldx #0
!ipci_str_loop:
    cpy ipc_rec_len
    bcs !ipci_unmap+
    lda item_name_decode_buf,x
    sta (zp_ptr0),y
    inx
    iny
    bne !ipci_str_loop-
!ipci_unmap:
    :ItemPickupCacheUnmap()
    pla
    sta ipc_end_lo
    pla
    sta ipc_end_hi
    rts
!ipci_full:
    lda #1
    sta ipc_pool_overflow
    rts

item_pickup_cache_hot_end:
.assert "Item pickup cache hot code and state stay resident below MAP_BASE", item_pickup_cache_hot_end <= MAP_BASE, true

#if !ITEM_PICKUP_CACHE_PREWARM_SEGMENT_CUSTOM
.macro ItemPickupCachePrewarmSegment() {}
.macro ItemPickupCachePrewarmRestoreSegment() {}
#endif
:ItemPickupCachePrewarmSegment()

// item_pickup_cache_warm_floor — Incremental floor-only warm after chest/monster
// drops (chest_fulfill_loot). Keeps existing cached entries in RAM; falls back to
// full reset + prewarm only if a newly spawned floor entry overflowed the pool.
item_pickup_cache_warm_floor:
    lda #0
    sta ipc_pool_overflow
    jsr ipc_warm_floor_passes
    lda ipc_pool_overflow
    bne item_pickup_cache_prewarm
    rts

// item_pickup_cache_prewarm — Full active-level reset + prioritized 3-pass warm:
//   Pass 1: active floor items (weight + current display name + ego suffix)
//   Pass 2: active floor items' real catalog names (coherence across mid-level ID)
//   Pass 3: carried inventory slots 0..MAX_INV_SLOTS-1 (0-disk item_drop)
item_pickup_cache_prewarm:
    jsr item_pickup_cache_invalidate
    jsr ipc_warm_floor_passes
    ldx #0
!ipcp_inv_loop:
    stx ipc_warm_idx
    ldy inv_ego,x
    lda inv_item_id,x
    jsr ipc_warm_active_ay
    ldx ipc_warm_idx
    inx
    cpx #MAX_INV_SLOTS
    bcc !ipcp_inv_loop-
    rts

ipc_warm_floor_passes:
    ldx #MAX_FLOOR_ITEMS - 1
!ipcf_p1:
    stx ipc_warm_idx
    ldy fi_meta_hi,x
    lda fi_item_id,x
    jsr ipc_warm_active_ay
    ldx ipc_warm_idx
    dex
    bpl !ipcf_p1-

    ldx #MAX_FLOOR_ITEMS - 1
!ipcf_p2:
    stx ipc_warm_idx
    ldy fi_meta_hi,x
    lda fi_item_id,x
    jsr ipc_check_non_gold_ay
    bcc !ipcf_p2_next+
    lda ipc_warm_id
    jsr item_cat_decode_item
!ipcf_p2_next:
    ldx ipc_warm_idx
    dex
    bpl !ipcf_p2-
    rts

ipc_check_non_gold_ay:
    cmp #FI_EMPTY
    beq !ipcc_skip+
    sta ipc_warm_id
    sty ipc_warm_ego
    tya
    and #ITEM_PAGE_BIT
    sta item_cur_page
    bne !ipcc_ok+
    .assert "All 20 gold types occupy Page 0 0..19", ITEM_GOLD_SMALL == 0 && ITEM_GOLD_MITHRIL == 19 && ITEM_PAGE_GOLD_MITHRIL == 0, true
    lda ipc_warm_id
    cmp #(ITEM_SLOT_GOLD_MITHRIL + 1)
    rts
!ipcc_ok:
    sec
    rts
!ipcc_skip:
    clc
    rts

ipc_warm_active_ay:
    jsr ipc_check_non_gold_ay
    bcc !ipca_done+
    ldx ipc_warm_id
    jsr item_get_weight_x       // preserves item_cur_page set by ipc_check_non_gold_ay
    lda ipc_warm_id
    jsr item_get_name_ptr
    lda ipc_warm_ego
    and #EGO_ID_MASK
    beq !ipca_done+
    jmp item_cat_decode_ego
!ipca_done:
    rts

:ItemPickupCachePrewarmRestoreSegment()

#endif
