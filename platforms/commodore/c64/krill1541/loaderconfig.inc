; Krill's Loader r194 compact runtime installer for 1541-compatible drives.
; Keep in sync with ../krill/loaderconfig.inc except for the drive-type gate.

DECOMPRESSOR                    = DECOMPRESSORS::NONE

.define LOAD_COMPD_API            0
.define LOAD_RAW_API              1
.define NTSC_COMPATIBILITY        1
.define PREFER_SPEED_OVER_SIZE    0
.define UNINSTALL_API             1

.define FILE_EXISTS_API           0
.define LOAD_UNDER_D000_DFFF      0
.define ALLOW_2_MHZ_ON_C128       0
.define MEM_DECOMP_API            0
.define MEM_DECOMP_TO_API         0
.define LOAD_TO_API               0
.define END_ADDRESS_API           0
.define BOUNDED_LOAD_API          0
.define LOAD_VIA_KERNAL_FALLBACK  0
.define CLOSE_FILE_API            0

.define DIRTRACK                 18
.define DIRTRACK81               40
.define FILENAME_MAXLENGTH       16

.define ONLY_1541_AND_COMPATIBLE  1
