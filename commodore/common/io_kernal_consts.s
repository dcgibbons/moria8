#importonce
// io_kernal_consts.s — Shared disk I/O and KERNAL constants

.const SAVE_FILE_NUM  = 2       // Logical file number for save/load data
.const CHECK_FILE_NUM = 3       // Separate file number for check_savefile_exists
.const SAVE_DEVICE    = 8       // Device 8 = first disk drive
.const SAVE_SEC_ADDR  = 2       // Secondary address for write (1541 channel 2)
.const LOAD_SEC_ADDR  = 2       // Secondary address for read (1541 channel 2) — same as write
.const CHECK_SEC_ADDR = 6       // Secondary address for existence check (1541 channel 6)
.const CMD_CHANNEL    = 15      // Command channel file number

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
