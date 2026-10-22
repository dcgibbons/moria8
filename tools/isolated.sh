#!/bin/bash
# isolated.sh — run a command in a private network namespace.
#
# Emulator harnesses talk to VICE, MAME and x16emu over localhost, several on
# fixed ports (VICE's default monitor port 6510). Two test runs on the same
# machine then drive each other's emulators. Inside a private network
# namespace every run has its own loopback, so ports can never collide.
# No root is needed: an unprivileged user namespace maps the caller to root
# inside it, and files it writes stay owned by the caller.
#
# ISOLATE=auto (default) isolates when the kernel allows it and otherwise runs
# the command as is; ISOLATE=1 requires isolation; ISOLATE=0 disables it.
# The namespace has no network beyond loopback, so tool downloads must happen
# before entering it (the root Makefile's tools-ready targets).
set -u

mode="${ISOLATE:-auto}"
if [ $# -eq 0 ]; then
    echo "usage: tools/isolated.sh command [args...]" >&2
    exit 2
fi
if [ -n "${MORIA8_ISOLATED:-}" ] || [ "$mode" = 0 ]; then
    exec "$@"
fi

if command -v unshare >/dev/null 2>&1 && command -v ip >/dev/null 2>&1 \
        && unshare --user --map-root-user --net true 2>/dev/null; then
    export MORIA8_ISOLATED=1
    exec unshare --user --map-root-user --net \
        sh -c 'ip link set lo up && exec "$@"' isolated "$@"
fi

if [ "$mode" = 1 ]; then
    echo "error: ISOLATE=1 but unprivileged network namespaces are unavailable" >&2
    exit 1
fi
exec "$@"
