// tier1_prg.s — Standalone tier 1 PRG for disk loading
// Assembles to a PRG with load address $E000 (RAM under KERNAL ROM).
// KERNAL LOAD stores data into RAM; bank out KERNAL to read.

.encoding "screencode_mixed"
.pc = $E000 "Tier Data"

#import "tier1.s"
