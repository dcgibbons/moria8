#importonce
// platform_services_api.s — shared runtime-service shims for platform-owned
// repair hooks needed by common gameplay/orchestration code.
//
// Unlike optional shims such as generation_busy_api, these services are
// correctness-critical on C128. Their defaults therefore fail loudly if they
// are reached before startup installs the real platform handlers.

.const PLATFORM_RUNTIME_SERVICES_READY = $a5

platform_runtime_services_ready: .byte 0

platform_services_mark_installed:
    lda #PLATFORM_RUNTIME_SERVICES_READY
    sta platform_runtime_services_ready
    rts

platform_services_assert_installed:
    lda platform_runtime_services_ready
    cmp #PLATFORM_RUNTIME_SERVICES_READY
    beq !done+
    brk
!done:
    rts

platform_services_missing_required:
    brk
    rts

platform_main_loop_begin_api:
    jmp platform_services_missing_required

platform_vector_reassert_api:
    jmp platform_services_missing_required

platform_runtime_resync_api:
    jmp platform_services_missing_required
