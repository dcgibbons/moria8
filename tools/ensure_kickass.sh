#!/usr/bin/env bash
set -euo pipefail

DEFAULT_KICKASS_URL="https://theweb.dk/KickAssembler/KickAssembler.zip"
DEFAULT_KICKASS_JAR_SHA256="9592a39336e73a1db8b4a7749256d62d29b113b1c7f0f6c86ea43870ebd9ae1f"

custom=0
if [ "${1:-}" = "--custom" ]; then
    custom=1
    shift
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "usage: $0 [--custom] <kickass_dir> [kickass_jar]" >&2
    exit 2
fi

kickass_dir="$1"
kickass_jar="${2:-$kickass_dir/KickAss.jar}"

if [ "$custom" -eq 1 ]; then
    if [ ! -f "$kickass_jar" ]; then
        echo "ERROR: custom KICKASS path does not exist: $kickass_jar" >&2
        exit 1
    fi
    exit 0
fi

KICKASS_URL="${KICKASS_URL:-$DEFAULT_KICKASS_URL}"
KICKASS_JAR_SHA256="${KICKASS_JAR_SHA256:-$DEFAULT_KICKASS_JAR_SHA256}"

if [ -n "${SHA256:-}" ]; then
    read -r -a sha_cmd <<< "$SHA256"
elif [ -n "${SHASUM:-}" ]; then
    sha_cmd=("$SHASUM" -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
    sha_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
    sha_cmd=(shasum -a 256)
else
    echo "ERROR: sha256sum or shasum is required to verify KickAss.jar" >&2
    exit 1
fi

verify_jar() {
    local jar_path="$1"
    if printf '%s  %s\n' "$KICKASS_JAR_SHA256" "$jar_path" | "${sha_cmd[@]}" -c - >/dev/null 2>&1; then
        return 0
    fi
    local actual=""
    actual="$("${sha_cmd[@]}" "$jar_path" 2>/dev/null | awk '{print $1}')" || actual="unknown"
    echo "ERROR: KickAss.jar SHA-256 mismatch at $jar_path" >&2
    echo "  expected: $KICKASS_JAR_SHA256" >&2
    echo "  actual:   $actual" >&2
    echo "  override with KICKASS=/path/to/KickAss.jar or KICKASS_JAR_SHA256=..." >&2
    return 1
}

if [ -f "$kickass_jar" ]; then
    verify_jar "$kickass_jar"
    exit 0
fi

mkdir -p "$kickass_dir"
stage="$kickass_dir/.stage.$$"
mkdir -p "$stage/unpacked"
trap 'rm -rf "$stage"' EXIT

echo "Downloading KickAssembler..."
if ! curl -fsSL "$KICKASS_URL" -o "$stage/KickAssembler.zip"; then
    echo "ERROR: failed to download KickAssembler from $KICKASS_URL" >&2
    exit 1
fi

if ! unzip -qo "$stage/KickAssembler.zip" -d "$stage/unpacked"; then
    echo "ERROR: failed to unpack KickAssembler archive" >&2
    exit 1
fi

staged_jar="$stage/unpacked/KickAss.jar"
if [ ! -f "$staged_jar" ]; then
    echo "ERROR: KickAss.jar not found in downloaded KickAssembler archive" >&2
    exit 1
fi

verify_jar "$staged_jar"

for entry in "$stage/unpacked"/*; do
    base="$(basename "$entry")"
    if [ "$base" = "KickAss.jar" ]; then
        continue
    fi
    rm -rf "$kickass_dir/$base"
    cp -R "$entry" "$kickass_dir/$base"
done

mkdir -p "$(dirname "$kickass_jar")"
mv -f "$staged_jar" "$kickass_jar"

if [ ! -f "$kickass_jar" ]; then
    echo "ERROR: KickAss.jar not found after install at $kickass_jar" >&2
    exit 1
fi

echo "KickAssembler ready at $kickass_jar"
