// test_minimal128.s — Minimal monitor harness sanity test

.pc = $0801 "BASIC Stub"
:BasicUpstart2(test_start)

.pc = $3000 "Test Code"

test_start:
    sei
    jmp test_pass

test_fail:
    jmp test_fail

test_pass:
    jmp test_pass
