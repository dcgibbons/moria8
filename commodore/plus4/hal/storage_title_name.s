#importonce
// Plus/4 title-art filename. PETSCII bytes for KERNAL LOAD.
// The Plus/4 port currently reuses the C64 title asset.

hal_storage_title_name:
    .byte $54, $36, $34                         // "T64"
.label hal_storage_title_name_len = * - hal_storage_title_name
