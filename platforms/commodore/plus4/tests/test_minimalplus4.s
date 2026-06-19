// Minimal Plus/4 monitor-harness smoke test.

.pc = $1000 "Plus/4 minimal test"

test_start:
    lda #$2a
    cmp #$2a
    beq test_pass

test_fail:
    brk

test_pass:
    nop
    jmp test_pass
