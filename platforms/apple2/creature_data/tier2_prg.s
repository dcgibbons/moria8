// tier2_prg.s — Apple IIe standalone tier 2 payload for MLI loading.
// Links at the shared overlay/tier window base; converted to BIN with
// auxtype $A200 by tools/prg_to_bin.py.

.encoding "screencode_mixed"
.pc = $A400 "Tier Data"

#import "../../commodore/c64/creature_data/tier2.s"
