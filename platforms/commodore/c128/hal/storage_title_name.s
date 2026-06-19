#importonce
// C128 title-art filename. PETSCII bytes for KERNAL LOAD.

hal_storage_title_name:
    .byte $54, $31, $32, $38                    // "T128"
.label hal_storage_title_name_len = * - hal_storage_title_name
