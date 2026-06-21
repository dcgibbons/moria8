// tier2_prg.s - CX16 tier 2 bank-window PRG.
// Loads at $A000 into the currently selected CX16 RAM bank.

.encoding "screencode_mixed"
.pc = $A000 "CX16 Tier 2 Data"

#import "../../commodore/c64/creature_data/tier2.s"
