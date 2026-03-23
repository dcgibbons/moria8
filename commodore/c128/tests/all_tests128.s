#importonce
// all_tests128.s — Master test module to reduce JVM overhead

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_entry)

.pc = $3000 "Master Test Entry"
test_entry:
    sei
    // This file will be used to run individual tests by jumping
    // to their specific namespaces via monitor.
    jmp *

// Individual test suites wrapped in namespaces
.filenamespace minimal128
#import "test_minimal128.s"

.filenamespace config128
#import "test_config128.s"

.filenamespace memory128
#import "test_memory128.s"

.filenamespace db128
#import "test_db128.s"

.filenamespace tier128
#import "test_tier128.s"

.filenamespace input128
#import "test_input128.s"

.filenamespace main_loop128
#import "test_main_loop128.s"

.filenamespace msg_prompt128
#import "test_msg_prompt128.s"

.filenamespace vdc_attr128
#import "test_vdc_attr128.s"

.filenamespace vdc_scroll_delta128
#import "test_vdc_scroll_delta128.s"

.filenamespace status_coherence128
#import "test_status_coherence128.s"

.filenamespace dungeon128
#import "test_dungeon128.s"

.filenamespace soak128
#import "test_soak128.s"

.filenamespace monster128
#import "test_monster128.s"
