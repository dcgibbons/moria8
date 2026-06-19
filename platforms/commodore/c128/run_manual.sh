#!/bin/bash
source run_tests128.sh > /dev/null 2>&1
build_real_boot_diag_assets
abs_d64="$(cd out && pwd)/moria128_realdiag.d64"
mon_file="/tmp/test128_real_boot_crash_harness.mon"
log_file="/tmp/test128_real_boot_crash_harness.log"
: > "$log_file"

{
    echo "g"
    cat <<'MON_EOF'
r
bt
x
MON_EOF
} > "$mon_file"

$VICE -console -nativemonitor -warp -80col -autostart "$abs_d64" \
    -keybuf $'NAA\rA\rA L>' -keybuf-delay 8 \
    -moncommands "$mon_file" -monlog -monlogname "$log_file" \
    -limitcycles 20000000 +sound -sounddev dummy \
    +remotemonitor +binarymonitor >/dev/null 2>&1

cat "$log_file" | tail -n 50
