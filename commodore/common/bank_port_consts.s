#importonce
// bank_port_consts.s — shared 6510/8502 processor-port banking aliases

#if PLUS4
.const BANK_ALL_RAM     = $00
.const BANK_ALL_ROM     = $01
.const BANK_NO_BASIC    = $01
.const BANK_NO_KERNAL   = $00
.const BANK_NO_ROMS     = $00
#else
.const BANK_ALL_RAM     = $30  // All RAM, including RAM under $D000-$DFFF
.const BANK_ALL_ROM     = $37  // Default: BASIC + KERNAL + I/O
.const BANK_NO_BASIC    = $36  // KERNAL + I/O, RAM at $A000–$BFFF
.const BANK_NO_KERNAL   = $35  // I/O + RAM everywhere ($A000, $D000=I/O, $E000)
.const BANK_NO_ROMS     = $34  // I/O only, RAM at $A000 and $E000
#endif
