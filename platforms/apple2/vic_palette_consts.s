#importonce
// vic_palette_consts.s — Apple IIe logical color constants.
//
// The Apple IIe text screen is colorless; these are logical IDs consumed by
// core/color.s. screen_a2.s records the logical color and maps only the
// title reverse-space attribute to inverse video. Values match the Commodore
// palette so shared color logic is unchanged.

.const COL_BLACK    = $00
.const COL_WHITE    = $01
.const COL_RED      = $02
.const COL_CYAN     = $03
.const COL_PURPLE   = $04
.const COL_GREEN    = $05
.const COL_BLUE     = $06
.const COL_YELLOW   = $07
.const COL_ORANGE   = $08
.const COL_BROWN    = $09
.const COL_LRED     = $0a
.const COL_DGREY    = $0b
.const COL_GREY     = $0c
.const COL_LGREEN   = $0d
.const COL_LBLUE    = $0e
.const COL_LGREY    = $0f
