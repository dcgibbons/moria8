#importonce
// monster_catalog4.s — Plus/4 monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/6502/monster_catalog.s,
// common/catalog_fetch.s; memory.s owns the hidden spans).
//
// The name pool, the level index and the record-sector table are hidden RAM
// at $D800-$DFFF, visible while the game runs (the ROMs banked out); the
// KERNAL wrappers bank the ROMs in around each drive call. Records come from
// the drive.

.macro CatalogWinBegin() {
}
.macro CatalogWinEnd() {
}
.macro CatalogMap() {
}
.macro CatalogUnmap() {
}
.macro CatalogPoolWrite() {
    sta (zp_ptr1),y
}
.macro CatalogKernalIn() {
}
.macro CatalogKernalOut() {
}

#if PLUS4_CARTRIDGE
#import "cartridge_catalog.s"
#else
#define CATALOG_EXT_DISK_ENABLED
#import "../common/catalog_fetch.s"
.assert "Plus/4 catalog filenames stay below $8000 ROM window", cfr_ext_name_end <= $8000 && cfr_record_offset <= $8000, true
#endif
