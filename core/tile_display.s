#importonce
// tile_display.s - shared tile byte to screen-code/color conversion.

#import "color.s"
#import "dungeon_data.s"

// tile_map_byte_to_char_color - Convert a map byte to display attributes.
// Input:  A = map byte
// Output: A = screen code, X = color
// Clobbers: A, X, zp_temp2
tile_map_byte_to_char_color:
    and #TILE_TYPE_MASK
    lsr
    lsr
    lsr
    lsr
    tax
    lda tile_colors,x
    sta zp_temp2
    lda tile_screen_codes,x
    ldx zp_temp2
    rts
