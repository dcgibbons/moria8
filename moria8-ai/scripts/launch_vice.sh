#!/bin/bash
# Launch VICE x64sc with binary monitor enabled for AI bridge.
#
# Usage:
#   ./scripts/launch_vice.sh [port]
#
# Defaults to port 6502. VICE runs in warp mode with sound off.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PORT="${1:-6502}"

# Find VICE binary
if command -v x64sc &>/dev/null; then
    VICE_BIN="x64sc"
elif [ -x "/Applications/VICE/bin/x64sc" ]; then
    VICE_BIN="/Applications/VICE/bin/x64sc"
else
    echo "ERROR: x64sc not found. Install VICE or add to PATH." >&2
    exit 1
fi

# Build if needed
PRG="$PROJECT_ROOT/commodore/c64/out/moria8.prg"
if [ ! -f "$PRG" ]; then
    echo "Building moria8.prg..."
    make -C "$PROJECT_ROOT" build
fi

echo "Launching VICE on port $PORT..."
echo "  Binary: $VICE_BIN"
echo "  PRG:    $PRG"

exec "$VICE_BIN" \
    -binarymonitor \
    -binarymonitoraddress "127.0.0.1:$PORT" \
    -warp \
    -sound 0 \
    -autostartprgmode 1 \
    -autostart "$PRG"
