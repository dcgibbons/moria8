// tier3_prg.s - CX16 tier 3 bank-window PRG.
// Loads at $A000 into the currently selected CX16 RAM bank.

.encoding "screencode_mixed"
.pc = $A000 "CX16 Tier 3 Data"

#import "../../commodore/c64/creature_data/tier3.s"
