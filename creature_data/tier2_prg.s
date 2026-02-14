// tier2_prg.s — Standalone tier 2 PRG for disk loading
// Assembles to a PRG with load address $E000 (RAM under KERNAL ROM).

.encoding "screencode_upper"
.pc = $E000 "Tier Data"

#import "tier2.s"
