#importonce
// monster_catalog4.s — Plus/4 monster catalog placement
// (docs/MONSTER_CATALOG_DESIGN.md, core/monster_catalog.s,
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

#import "../common/catalog_fetch.s"
