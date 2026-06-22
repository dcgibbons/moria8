// services.s - Commander X16 platform service contracts

#import "hal/lifecycle_policy.s"
#import "hal/entropy_consts.s"
#import "../../core/platform_services_api.s"

.const CX16_HAL_STATUS_OK = 0

// Shared semantic sound IDs. CX16 sound is silent for now, but shared gameplay
// still references the effect constants.
.const SFX_NONE = $ff
.const SFX_BUMP = $00
.const SFX_HIT = $01
.const SFX_MISS = $02
.const SFX_PICKUP = $03
.const SFX_DEATH = $04
.const SFX_LEVELUP = $05
.const SFX_SPELL = $06
.const SFX_SPELL_FAIL = $07
.const SFX_HUNGER_WARN = $08
.const SFX_HUNGER_FAINT = $09

.label hal_sound_init = cx16_service_ok
.label hal_sound_stop = cx16_service_ok
.label hal_sound_update = cx16_service_ok
.label hal_sound_play = cx16_service_ok

.label hal_storage_require_program_media = cx16_service_ok
.label hal_storage_init_selected_drive = cx16_service_ok
.label hal_asset_close_channel = cx16_asset_close_channel
.label hal_asset_load_prg_header = cx16_asset_load_prg_header
.label hal_storage_require_save_media = cx16_service_ok
.label hal_storage_save_record = cx16_hal_storage_save_record
.label hal_storage_load_record = cx16_hal_storage_load_record

cx16_asset_load_addr_lo: .byte 0
cx16_asset_load_addr_hi: .byte 0

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

// Input: A = filename length, X/Y = filename pointer. Uses the PRG header load
// address expected by the caller in cx16_asset_load_addr_lo/hi. Carry mirrors
// KERNAL LOAD status.
cx16_asset_load_prg_header:
    jsr KERNAL_SETNAM
    lda #2
    ldx #8
    ldy #0
    jsr KERNAL_SETLFS
    ldx cx16_asset_load_addr_lo
    ldy cx16_asset_load_addr_hi
    lda #0
    jsr KERNAL_LOAD
    php
    jsr cx16_asset_close_channel
    plp
    rts

cx16_asset_close_channel:
    lda #2
    jsr KERNAL_CLOSE
    jmp KERNAL_CLRCHN
