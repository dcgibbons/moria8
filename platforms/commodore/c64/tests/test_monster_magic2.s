// test_monster_magic2.s — tests 23-42 of test_monster_magic.s (the saving
// throw values, the paralysis touch save, Hold Person and Free Action, the
// Multi-Hued spell choice and breath by element): one suite split in two so
// that every module it links fits below MAP_BASE, loaded and executable.
//
// Results at $0400-$0429: tests 23-42 in bytes 22-41 ($01 = pass); bytes
// 0-21 stay $ff (they are test_monster_magic.s's).
#define MONSTER_MAGIC_PART2
#import "test_monster_magic.s"
