// tier3_prg.s — Standalone tier 3 PRG for disk loading
// Assembles to a PRG with load address $E000 (RAM under KERNAL ROM).

.encoding "screencode_upper"
.pc = $E000 "Tier Data"

#import "tier3.s"
