// services.s - Commander X16 platform service contracts

#import "hal/lifecycle_policy.s"
#import "../../core/platform_services_api.s"

.const CX16_HAL_STATUS_OK = 0
.const CX16_HAL_STATUS_ERR_UNSUPPORTED = 7

.label hal_sound_init = cx16_service_ok
.label hal_sound_stop = cx16_service_ok
.label hal_sound_update = cx16_service_ok
.label hal_sound_play = cx16_service_ok

.label hal_storage_require_program_media = cx16_service_ok
.label hal_storage_init_selected_drive = cx16_service_ok
.label hal_storage_require_save_media = cx16_service_unsupported
.label hal_storage_save_record = cx16_service_unsupported
.label hal_storage_load_record = cx16_service_unsupported

cx16_services_install:
    lda #$4c
    sta platform_main_loop_begin_api
    sta platform_vector_reassert_api
    sta platform_runtime_resync_api
    lda #<cx16_service_ok
    sta platform_main_loop_begin_api + 1
    sta platform_vector_reassert_api + 1
    sta platform_runtime_resync_api + 1
    lda #>cx16_service_ok
    sta platform_main_loop_begin_api + 2
    sta platform_vector_reassert_api + 2
    sta platform_runtime_resync_api + 2
    jmp platform_services_mark_installed

cx16_service_ok:
    clc
    lda #CX16_HAL_STATUS_OK
    rts

cx16_service_unsupported:
    sec
    lda #CX16_HAL_STATUS_ERR_UNSUPPORTED
    ldx #0
    ldy #0
    rts
