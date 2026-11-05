#importonce
// catalog_records.s — The monster catalog's disk records on the C64 and
// Plus/4 (docs/MONSTER_CATALOG_DESIGN.md, "C64 and Plus/4").
//
// tools/catalog_disk.py reads these constants: keep them single-line.
//
// Record (CATALOG_RECORD_SIZE bytes): the catalog id (lo, hi), the
// CATALOG_SOA_FIELDS engine fields in ltb_dst order, then the name in screen
// codes, 0-terminated and 0-padded.
//
// Files MONSTER.CAT1-4: CATALOG_FILE_SECTORS 254-byte sectors each (the last
// file fewer). Each sector holds 2 header bytes, CATALOG_RECORDS_PER_SECTOR
// records and padding, so no record crosses a sector; the first sector's
// header is the PRG load address ($E000), the others' are 0. Record n is in
// global sector n / CATALOG_RECORDS_PER_SECTOR, at byte
// 2 + (n % CATALOG_RECORDS_PER_SECTOR) * CATALOG_RECORD_SIZE of its data.
//
// MONSTER.IDX: the level index (cat_level_raw, cat_level_playable,
// cat_available: catalog_index.s data) then the track of each record sector
// and then its sector number, written after the record files are on the disk;
// a PRG loading at the port's CATALOG_IDX_LOAD (memory.s).

.const CATALOG_RECORD_SIZE        = 49
.const CATALOG_RECORD_NAME        = 23
.const CATALOG_RECORDS_PER_SECTOR = 5
.const CATALOG_FILE_SECTORS       = 16
.const CATALOG_RECORD_SECTORS     = 56
.const CATALOG_RECORD_FILES       = 4
.const CATALOG_SECTOR_HEADER      = 2
.const CATALOG_RECORDS_LOAD       = $e000
