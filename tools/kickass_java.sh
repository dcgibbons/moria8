#!/bin/bash
# kickass_java.sh — java wrapper for KickAssembler product builds.
# KickAssembler exits 0 even when .assert directives fail, so memory
# boundary violations can pass silently. This wrapper preserves the
# assembler output but exits nonzero when any assertion failure fires.
set -u

log="$(mktemp "${TMPDIR:-/tmp}/kickass_assert.XXXXXX")"
trap 'rm -f "$log"' EXIT

if ! java "$@" >"$log" 2>&1; then
    cat "$log"
    exit 1
fi
cat "$log"
if grep -q "ERROR IN ASSERTION" "$log"; then
    echo "error: assembler assertions failed (see output above)" >&2
    exit 1
fi
