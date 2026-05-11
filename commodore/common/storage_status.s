#importonce

.const HAL_STORAGE_STATUS_OK                 = 0
.const HAL_STORAGE_STATUS_NOT_FOUND          = 1
.const HAL_STORAGE_STATUS_NO_DEVICE          = 2
.const HAL_STORAGE_STATUS_WRITE_PROTECTED    = 3
.const HAL_STORAGE_STATUS_DISK_FULL          = 4
.const HAL_STORAGE_STATUS_WRONG_MEDIA        = 5
.const HAL_STORAGE_STATUS_DEVICE_NOT_READY   = 6
.const HAL_STORAGE_STATUS_UNSUPPORTED        = 7
.const HAL_STORAGE_STATUS_UNKNOWN            = 255

#if STORAGE_STATUS_HELPER
// storage_status_from_dos_digits
// Input: A = first ASCII decimal digit, X = second ASCII decimal digit.
// Output: A = HAL_STORAGE_STATUS_*.
// Clobbers: flags.
storage_status_from_dos_digits:
    cmp #$30                    // 00, OK
    bne !check_26+
    cpx #$30
    bne !unknown+
    lda #HAL_STORAGE_STATUS_OK
    rts
!check_26:
    cmp #$32                    // 26, WRITE PROTECT ON
    bne !check_62+
    cpx #$36
    bne !unknown+
    lda #HAL_STORAGE_STATUS_WRITE_PROTECTED
    rts
!check_62:
    cmp #$36                    // 62, FILE NOT FOUND
    bne !check_72+
    cpx #$32
    bne !unknown+
    lda #HAL_STORAGE_STATUS_NOT_FOUND
    rts
!check_72:
    cmp #$37                    // 72, DISK FULL
    bne !unknown+
    cpx #$32
    beq !disk_full+
    cpx #$34                    // 74, DRIVE NOT READY
    beq !not_ready+
!unknown:
    lda #HAL_STORAGE_STATUS_UNKNOWN
    rts
!disk_full:
    lda #HAL_STORAGE_STATUS_DISK_FULL
    rts
!not_ready:
    lda #HAL_STORAGE_STATUS_DEVICE_NOT_READY
    rts
#endif
