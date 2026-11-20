#importonce
// monster_catalog_a2.s — Apple IIe monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/monster_catalog.s;
// docs/APPLE2_MEMORY_POLICY.md and cache_layout.s own the aux spans).
//
// The fields (A2.CATALOG) load into aux RAM at A2_AUX_CATALOG with the boot
// pack; the Huffman-coded names ride after the corpus in A2.HUFFDATA
// (main.s), decoded through the corpus's aux reads. The level index is
// resident. The fetch reads the fields one byte at a time through the
// zero-page aux-read thunk and writes each name into the main-RAM name pool,
// so no banking state needs saving: the catalog maps nothing.

.segment A2Catalog
#import "../shared/catalog/catalog_fields.s"
.segment Default
#import "../shared/catalog/catalog_index.s"

.assert "Catalog fields start their aux span", catalog_fields, A2_AUX_CATALOG
.assert "Catalog fields fit below the UI cache slot", catalog_fields_end <= A2_AUX_CACHE_UI, true

.const CATALOG_NAME_POOL_BASE = PLATFORM_TIER_NAME_POOL_BASE
.const CATALOG_NAME_POOL_END  = PLATFORM_TIER_NAME_POOL_END

// The win creature and the turn's wanderer (catalog_place_far) live in the
// play slot: the resident image has no room. Level generation and the turn
// both run with the play slot loaded (game_loop.s lives there).
.macro CatalogWinBegin() {
    .segment A2PlaySlot
}
.macro CatalogWinEnd() {
    .segment Default
}
.macro CatalogMap() {
}
.macro CatalogUnmap() {
}
.macro CatalogFieldRead() {
    jsr mmu_safe_map_read_ptr0      // A = aux (zp_ptr0),y; X and Y kept
}
.macro CatalogPoolWrite() {
    sta (zp_ptr1),y
}

// ============================================================
// Phase 5 Extended Monster Catalog (A2.CATEXT in Aux LC Bank 2 $D000-$D8B7)
//   279 x 8-byte contiguous per-species rows preloaded at cold boot.
//   catalog_fetch_ext reads 8 bytes from Aux LC Bank 2 ($D000 + id * 8)
//   into cat_ext_record[0..7] via SEI, ZP-free a2_aux_lc_bounce_xfer.
// ============================================================
.const CATALOG_EXT_RECORD_SIZE = A2_CATEXT_RECORD_SIZE
.assert "A2.CATEXT Aux LC Bank 2 base is page-aligned", <A2_LC_CATEXT_BASE, 0
.assert "A2.CATEXT size matches CATALOG_COUNT * 8", A2_CATEXT_SIZE, CATALOG_COUNT * CATALOG_EXT_RECORD_SIZE
.assert "A2.CATEXT fits in Aux LC Bank 2 ($D000-$DFFF)", A2_LC_CATEXT_BASE + A2_CATEXT_SIZE - 1 <= $dfff, true
.assert "A2.CATEXT row fits Aux LC bounce buffer", CATALOG_EXT_RECORD_SIZE <= 16, true

cat_ext_record:
    .fill CATALOG_EXT_RECORD_SIZE, 0

// catalog_fetch_ext — Read creature cat_id_lo/hi's 8 extended Phase 5 bytes
// from Aux LC Bank 2 ($D000 + id * 8) into cat_ext_record[0..7].
// Zero ZP bytes read or written; IRQ-safe via a2_aux_lc_bounce_xfer.
// Clobbers: A, X, Y.
catalog_fetch_ext:
    lda cat_id_hi                   // $00 or $01 (0..278)
    sta A2_LC_CALLER_X              // Main $02F4 hi-byte shift scratch
    lda cat_id_lo
    asl
    rol A2_LC_CALLER_X              // * 2
    asl
    rol A2_LC_CALLER_X              // * 4
    asl
    rol A2_LC_CALLER_X              // * 8 -> A = lo(id * 8), A2_LC_CALLER_X = hi(id * 8)
    tax                             // X = lo($D000 + id * 8) (<A2_LC_CATEXT_BASE == $00)
    lda A2_LC_CALLER_X
    clc
    adc #>A2_LC_CATEXT_BASE         // + $D0 -> $D0..$D8
    tay                             // Y = hi($D000 + id * 8)
    lda #A2_LC_BANK2
    sta A2_LC_ARG_BANK
    lda #A2_LC_DIR_READ
    sta A2_LC_ARG_DIR
    lda #CATALOG_EXT_RECORD_SIZE
    jsr a2_aux_lc_bounce_xfer
    ldx #CATALOG_EXT_RECORD_SIZE - 1
!cfe_copy:
    lda A2_LC_BOUNCE,x
    sta cat_ext_record,x
    dex
    bpl !cfe_copy-
    rts
