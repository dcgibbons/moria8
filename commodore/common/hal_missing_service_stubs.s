#importonce
#import "../hal/hal_contract.s"
// Opt-in fail-loud stubs for isolated assemblies that have not wired a
// platform HAL yet. Product builds must import platform adapters instead.

hal_platform_init_early:
    lda #1
    jmp hal_missing_service
hal_platform_init_runtime:
    lda #2
    jmp hal_missing_service
hal_platform_runtime_resync:
    lda #3
    jmp hal_missing_service
hal_platform_shutdown:
    lda #4
    jmp hal_missing_service
hal_platform_panic:
    lda #5
    jmp hal_missing_service

hal_memory_enter_os:
    lda #16
    jmp hal_missing_service
hal_memory_exit_os:
    lda #17
    jmp hal_missing_service
hal_memory_restore_runtime:
    lda #18
    jmp hal_missing_service
hal_memory_copy:
    lda #19
    jmp hal_missing_service
hal_memory_read_byte:
    lda #20
    jmp hal_missing_service
hal_memory_write_byte:
    lda #21
    jmp hal_missing_service

hal_irq_install_runtime:
    lda #32
    jmp hal_missing_service
hal_irq_restore_os:
    lda #33
    jmp hal_missing_service
hal_irq_mask:
    lda #34
    jmp hal_missing_service
hal_irq_unmask:
    lda #35
    jmp hal_missing_service
hal_irq_ack:
    lda #36
    jmp hal_missing_service
hal_irq_critical_begin:
    lda #37
    jmp hal_missing_service
hal_irq_critical_end:
    lda #38
    jmp hal_missing_service

hal_screen_init:
    lda #48
    jmp hal_missing_service
hal_screen_clear:
    lda #49
    jmp hal_missing_service
hal_screen_clear_row:
    lda #50
    jmp hal_missing_service
hal_screen_put_char:
    lda #51
    jmp hal_missing_service
hal_screen_put_string:
    lda #52
    jmp hal_missing_service
hal_screen_put_char_at:
    lda #53
    jmp hal_missing_service
hal_screen_set_color:
    lda #54
    jmp hal_missing_service
hal_screen_blank:
    lda #55
    jmp hal_missing_service
hal_screen_unblank:
    lda #56
    jmp hal_missing_service
hal_screen_begin_bulk:
    lda #57
    jmp hal_missing_service
hal_screen_end_bulk:
    lda #58
    jmp hal_missing_service

hal_input_get_key:
    lda #64
    jmp hal_missing_service
hal_input_get_command:
    lda #65
    jmp hal_missing_service
hal_input_get_text_char:
    lda #66
    jmp hal_missing_service
hal_input_wait_release:
    lda #67
    jmp hal_missing_service
hal_input_any_key_held:
    lda #68
    jmp hal_missing_service
hal_input_run_cancel_check:
    lda #69
    jmp hal_missing_service
hal_input_modal_prepare:
    lda #70
    jmp hal_missing_service
hal_input_modal_finish:
    lda #71
    jmp hal_missing_service

hal_sound_init:
    lda #80
    jmp hal_missing_service
hal_sound_play:
    lda #81
    jmp hal_missing_service
hal_sound_stop:
    lda #82
    jmp hal_missing_service
hal_sound_update:
    lda #83
    jmp hal_missing_service

hal_missing_service:
    sta hal_missing_service_id
    sec
    lda #HAL_STATUS_ERR_UNSUPPORTED
    brk
    jmp hal_missing_service

hal_missing_service_id:
    .byte 0
