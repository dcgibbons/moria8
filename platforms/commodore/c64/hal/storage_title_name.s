#importonce
// C64 title-art filename. PETSCII bytes for KERNAL LOAD.
// Trailing zero (excluded from the length) lets Krill's Loader use the
// same table as a 0-terminated filename.

hal_storage_title_name:
    .byte $54, $36, $34                         // "T64"
.label hal_storage_title_name_len = * - hal_storage_title_name
    .byte 0
