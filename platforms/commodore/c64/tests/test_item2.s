// test_item2.s — tests 38-74 of test_item.s (item generation by depth, the
// item level scale, base armour AC, the equipment bonus recalculation and
// the rest): one suite split in two so that every module it exercises fits
// below MAP_BASE, loaded and executable.
//
// Results at $0400-$0449: tests 38-74 in bytes 37-73 ($01 = pass); bytes
// 0-36 stay $ff (they are test_item.s's).
#define ITEM_TESTS_PART2
#import "test_item.s"
