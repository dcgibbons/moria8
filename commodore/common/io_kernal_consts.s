#importonce
// io_kernal_consts.s — Shared KERNAL constants

.const SAVE_DEVICE    = 8       // Device 8 = first disk drive

.const KERNAL_SETNAM = $ffbd
.const KERNAL_SETLFS = $ffba
.const KERNAL_OPEN   = $ffc0
.const KERNAL_CLOSE  = $ffc3
.const KERNAL_CHKOUT = $ffc9
.const KERNAL_CHKIN  = $ffc6
.const KERNAL_CLRCHN = $ffcc
.const KERNAL_CHROUT = $ffd2
.const KERNAL_CHRIN  = $ffcf
.const KERNAL_READST = $ffb7
.const KERNAL_LOAD   = $ffd5
