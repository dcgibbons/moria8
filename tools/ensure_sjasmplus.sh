#!/usr/bin/env bash
set -euo pipefail

DEFAULT_SJASMPLUS_VERSION="1.24.0"
DEFAULT_SJASMPLUS_URL="https://github.com/z00m128/sjasmplus/archive/refs/tags/v${DEFAULT_SJASMPLUS_VERSION}.tar.gz"
DEFAULT_SJASMPLUS_TARBALL_SHA256="88a94cc4586c391306201e572352e1f6c391a74fef2c9e1ae7cd55d5bfb8839b"

custom=0
if [ "${1:-}" = "--custom" ]; then
    custom=1
    shift
fi

if [ "$#" -gt 2 ]; then
    echo "usage: $0 [--custom] [sjasmplus_dir] [sjasmplus_bin]" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
sjasmplus_dir="${1:-$script_dir/sjasmplus}"
default_bin="$sjasmplus_dir/sjasmplus"

if [ "$#" -eq 2 ]; then
    sjasmplus_bin="$2"
elif [ -n "${SJASMPLUS:-}" ]; then
    sjasmplus_bin="$SJASMPLUS"
else
    sjasmplus_bin="$default_bin"
fi

check_custom_bin() {
    local bin_path="$1"
    if [ -x "$bin_path" ]; then
        return 0
    fi
    if [[ "$bin_path" != */* ]] && command -v "$bin_path" >/dev/null 2>&1; then
        return 0
    fi
    echo "ERROR: custom SJASMPLUS binary does not exist or is not executable: $bin_path" >&2
    return 1
}

if [ "$custom" -eq 1 ]; then
    check_custom_bin "$sjasmplus_bin"
    exit 0
fi

if [ -n "${SJASMPLUS:-}" ] && [ "$sjasmplus_bin" != "$default_bin" ]; then
    check_custom_bin "$sjasmplus_bin"
    exit 0
fi

SJASMPLUS_URL="${SJASMPLUS_URL:-$DEFAULT_SJASMPLUS_URL}"
SJASMPLUS_TARBALL_SHA256="${SJASMPLUS_TARBALL_SHA256:-$DEFAULT_SJASMPLUS_TARBALL_SHA256}"

if [ -n "${SHA256:-}" ]; then
    read -r -a sha_cmd <<< "$SHA256"
elif [ -n "${SHASUM:-}" ]; then
    sha_cmd=("$SHASUM" -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
    sha_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
    sha_cmd=(shasum -a 256)
else
    echo "ERROR: sha256sum or shasum is required to verify sjasmplus tarball" >&2
    exit 1
fi

verify_tarball() {
    local tarball_path="$1"
    if printf '%s  %s\n' "$SJASMPLUS_TARBALL_SHA256" "$tarball_path" | "${sha_cmd[@]}" -c - >/dev/null 2>&1; then
        return 0
    fi
    local actual=""
    actual="$("${sha_cmd[@]}" "$tarball_path" 2>/dev/null | awk '{print $1}')" || actual="unknown"
    echo "ERROR: sjasmplus tarball SHA-256 mismatch" >&2
    echo "  expected: $SJASMPLUS_TARBALL_SHA256" >&2
    echo "  actual:   $actual" >&2
    echo "  override with SJASMPLUS=/path/to/sjasmplus or SJASMPLUS_TARBALL_SHA256=..." >&2
    return 1
}

bin_dir="$(dirname "$sjasmplus_bin")"
stamp_file="$bin_dir/.sjasmplus.sha256"
host_os="$(uname -s 2>/dev/null || echo unknown)"
host_arch="$(uname -m 2>/dev/null || echo unknown)"
host_id="${host_os}-${host_arch}"
expected_stamp="${SJASMPLUS_TARBALL_SHA256} ${host_id}"

bin_matches_host_os() {
    local bin_path="$1"
    local magic=""
    magic="$(dd if="$bin_path" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n\r\t')"
    case "$magic" in
        2321*) return 0 ;; # shebang wrapper script
    esac
    case "$host_os" in
        Linux) [ "$magic" = "7f454c46" ] ;;
        Darwin)
            case "$magic" in
                cffaedfe|cefaedfe|feedfacf|feedface|cafebabe|bebafeca) return 0 ;;
                *) return 1 ;;
            esac
            ;;
        *) return 0 ;;
    esac
}

if [ -x "$sjasmplus_bin" ] && bin_matches_host_os "$sjasmplus_bin"; then
    if [ -f "$stamp_file" ]; then
        installed_sha="$(cat "$stamp_file" 2>/dev/null || true)"
        if [ "$installed_sha" = "$expected_stamp" ]; then
            exit 0
        elif [ "$installed_sha" = "$SJASMPLUS_TARBALL_SHA256" ]; then
            printf '%s\n' "$expected_stamp" > "$stamp_file"
            exit 0
        fi
    else
        exit 0
    fi
fi

mkdir -p "$sjasmplus_dir" "$bin_dir"
stage="$sjasmplus_dir/.stage.$$"
mkdir -p "$stage/src"
trap 'rm -rf "$stage"' EXIT

echo "Downloading sjasmplus v${DEFAULT_SJASMPLUS_VERSION}..."
if ! curl -fsSL "$SJASMPLUS_URL" -o "$stage/sjasmplus.tar.gz"; then
    echo "ERROR: failed to download sjasmplus from $SJASMPLUS_URL" >&2
    exit 1
fi

verify_tarball "$stage/sjasmplus.tar.gz"

if ! tar -xzf "$stage/sjasmplus.tar.gz" -C "$stage/src"; then
    echo "ERROR: failed to unpack sjasmplus archive" >&2
    exit 1
fi

src_dir=""
for entry in "$stage/src"/*; do
    if [ -d "$entry" ] && [ -f "$entry/Makefile" ]; then
        src_dir="$entry"
        break
    fi
done

if [ -z "$src_dir" ]; then
    echo "ERROR: unpacked sjasmplus source directory not found" >&2
    exit 1
fi

jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
cxx_bin="${CXX:-g++}"
cc_bin="${CC:-gcc}"

echo "Building sjasmplus v${DEFAULT_SJASMPLUS_VERSION}..."
if ! make -C "$src_dir" -j"$jobs" CC="$cc_bin" CXX="$cxx_bin" USE_LUA=0; then
    echo "ERROR: failed to build sjasmplus" >&2
    exit 1
fi

built_bin="$src_dir/sjasmplus"
if [ ! -x "$built_bin" ]; then
    echo "ERROR: built sjasmplus binary not found at $built_bin" >&2
    exit 1
fi

cp -f "$built_bin" "$stage/sjasmplus.new"
chmod 755 "$stage/sjasmplus.new"
mv -f "$stage/sjasmplus.new" "$sjasmplus_bin"
if [ -f "$src_dir/LICENSE.md" ]; then
    cp -f "$src_dir/LICENSE.md" "$bin_dir/LICENSE.md"
fi
printf '%s\n' "$expected_stamp" > "$stamp_file"

if [ ! -x "$sjasmplus_bin" ]; then
    echo "ERROR: sjasmplus not found after install at $sjasmplus_bin" >&2
    exit 1
fi

echo "sjasmplus ready at $sjasmplus_bin"
