; Krill's Loader r194 build configuration for Moria8 C64.
; Consumed via EXTCONFIGPATH when building tools/krill (see platforms/commodore/Makefile).
; Raw-loads only: overlays/tiers/title are small and the resident must fit the
; $F000 banked payload; decompression support is intentionally omitted.
; Full drive-type detection is kept so incompatible devices (1581, FD, SD2IEC,
; VICE without true drive emulation) fail install cleanly and moria8 falls back
; to its stock KERNAL path.

DECOMPRESSOR                    = DECOMPRESSORS::NONE

; basic features

.define LOAD_COMPD_API            0 ; requires DECOMPRESSOR != DECOMPRESSORS::NONE
.define LOAD_RAW_API              1
.define NTSC_COMPATIBILITY        1 ; ship a single resident that is safe on NTSC machines
.define PREFER_SPEED_OVER_SIZE    0
.define UNINSTALL_API             1 ; standard-DOS flows temporarily uninstall the drive code;
                                    ; title context reinstalls it for subsequent reads

; extended features

.define FILE_EXISTS_API           0
.define LOAD_UNDER_D000_DFFF      0 ; resident lives under KERNAL at $F000; $D000 window is I/O-owned
.define ALLOW_2_MHZ_ON_C128       0
.define MEM_DECOMP_API            0 ; requires DECOMPRESSOR != DECOMPRESSORS::NONE
.define MEM_DECOMP_TO_API         0 ; requires MEM_DECOMP_API != 0
.define LOAD_TO_API               0 ; all payload files carry their final PRG load address
.define END_ADDRESS_API           0
.define LOAD_VIA_KERNAL_FALLBACK  0 ; would force the resident below $D000; moria8 keeps its own
                                    ; KERNAL path as graceful degradation on install failure
.define CLOSE_FILE_API            0

; these options change drive-side code

.define DIRTRACK                 18
.define DIRTRACK81               40 ; DIRTRACK/DIRTRACK81 must be 18/40 when LOAD_VIA_KERNAL_FALLBACK != 0

.define FILENAME_MAXLENGTH       16

; this option reduces host-side install code

.define ONLY_1541_AND_COMPATIBLE  0 ; keep full drive detection: incompatible drives must fail
                                    ; install cleanly so the moria8 KERNAL fallback engages
