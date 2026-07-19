#importonce
// Shared room-center lookups; platforms may choose the owning code segment.

conn_room_center_to_start:
    ldy room_type,x
    lda room_slot_center_x,y
    sta dg_cx1
    lda room_slot_center_y,y
    sta dg_cy1
    rts

conn_room_center_to_target:
    ldy room_type,x
    lda room_slot_center_x,y
    sta dg_cx2
    lda room_slot_center_y,y
    sta dg_cy2
    rts
