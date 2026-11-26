#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CTOOLS_COMMIT="946fb34b99384af09451eb153131830b5c1b33db"
DEFAULT_CTOOLS_URL="https://github.com/mist64/ctools/archive/${DEFAULT_CTOOLS_COMMIT}.tar.gz"
DEFAULT_CTOOLS_TARBALL_SHA256="317f84c4231169bc7ea7dc44fc089d09637b1f87496a3d2e0939a44666343485"

custom=0
if [ "${1:-}" = "--custom" ]; then
    custom=1
    shift
fi

if [ "$#" -gt 3 ]; then
    echo "usage: $0 [--custom] [ctools_dir] [ctools_bin] [cformat_bin]" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
ctools_dir="${1:-$script_dir/ctools}"
default_ctools="$ctools_dir/ctools"
default_cformat="$ctools_dir/cformat"

if [ "$#" -ge 2 ]; then
    ctools_bin="$2"
elif [ -n "${CTOOLS:-}" ]; then
    ctools_bin="$CTOOLS"
else
    ctools_bin="$default_ctools"
fi

if [ "$#" -eq 3 ]; then
    cformat_bin="$3"
elif [ -n "${CFORMAT:-}" ]; then
    cformat_bin="$CFORMAT"
else
    cformat_bin="$default_cformat"
fi

check_custom_bin() {
    local name="$1"
    local bin_path="$2"
    if [ -x "$bin_path" ]; then
        return 0
    fi
    if [[ "$bin_path" != */* ]] && command -v "$bin_path" >/dev/null 2>&1; then
        return 0
    fi
    echo "ERROR: custom $name binary does not exist or is not executable: $bin_path" >&2
    return 1
}

has_custom_ctools=0
has_custom_cformat=0
if [ "$ctools_bin" != "$default_ctools" ]; then
    has_custom_ctools=1
fi
if [ "$cformat_bin" != "$default_cformat" ]; then
    has_custom_cformat=1
fi

if [ "$custom" -eq 1 ]; then
    check_custom_bin "CTOOLS" "$ctools_bin"
    check_custom_bin "CFORMAT" "$cformat_bin"
    exit 0
fi

if [ "$has_custom_ctools" -eq 1 ]; then
    check_custom_bin "CTOOLS" "$ctools_bin"
fi
if [ "$has_custom_cformat" -eq 1 ]; then
    check_custom_bin "CFORMAT" "$cformat_bin"
fi
if [ "$has_custom_ctools" -eq 1 ] && [ "$has_custom_cformat" -eq 1 ]; then
    exit 0
fi

CTOOLS_URL="${CTOOLS_URL:-$DEFAULT_CTOOLS_URL}"
CTOOLS_TARBALL_SHA256="${CTOOLS_TARBALL_SHA256:-$DEFAULT_CTOOLS_TARBALL_SHA256}"

if [ -n "${SHA256:-}" ]; then
    read -r -a sha_cmd <<< "$SHA256"
elif [ -n "${SHASUM:-}" ]; then
    sha_cmd=("$SHASUM" -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
    sha_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
    sha_cmd=(shasum -a 256)
else
    echo "ERROR: sha256sum or shasum is required to verify ctools tarball" >&2
    exit 1
fi

verify_tarball() {
    local tarball_path="$1"
    if printf '%s  %s\n' "$CTOOLS_TARBALL_SHA256" "$tarball_path" | "${sha_cmd[@]}" -c - >/dev/null 2>&1; then
        return 0
    fi
    local actual=""
    actual="$("${sha_cmd[@]}" "$tarball_path" 2>/dev/null | awk '{print $1}')" || actual="unknown"
    echo "ERROR: ctools tarball SHA-256 mismatch" >&2
    echo "  expected: $CTOOLS_TARBALL_SHA256" >&2
    echo "  actual:   $actual" >&2
    echo "  override with CTOOLS=/path/to/ctools CFORMAT=/path/to/cformat or CTOOLS_TARBALL_SHA256=..." >&2
    return 1
}

bin_dir="$(dirname "$ctools_bin")"
cformat_dir="$(dirname "$cformat_bin")"
stamp_file="$ctools_dir/.ctools.sha256"
host_os="$(uname -s 2>/dev/null || echo unknown)"
host_arch="$(uname -m 2>/dev/null || echo unknown)"
host_id="${host_os}-${host_arch}"
expected_stamp="${CTOOLS_TARBALL_SHA256} ${host_id}"

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

ctools_host_ok=1
if [ "$has_custom_ctools" -eq 0 ] && [ -x "$ctools_bin" ] && ! bin_matches_host_os "$ctools_bin"; then
    ctools_host_ok=0
fi
if [ "$has_custom_cformat" -eq 0 ] && [ -x "$cformat_bin" ] && ! bin_matches_host_os "$cformat_bin"; then
    ctools_host_ok=0
fi

if [ "$ctools_host_ok" -eq 1 ] && [ -x "$ctools_bin" ] && [ -x "$cformat_bin" ]; then
    if [ "$has_custom_ctools" -eq 1 ] && [ "$has_custom_cformat" -eq 1 ]; then
        exit 0
    elif [ -f "$stamp_file" ]; then
        installed_sha="$(cat "$stamp_file" 2>/dev/null || true)"
        if [ "$installed_sha" = "$expected_stamp" ]; then
            exit 0
        elif [ "$installed_sha" = "$CTOOLS_TARBALL_SHA256" ]; then
            printf '%s\n' "$expected_stamp" > "$stamp_file"
            exit 0
        fi
    else
        exit 0
    fi
fi

mkdir -p "$ctools_dir" "$bin_dir" "$cformat_dir"
stage="$ctools_dir/.stage.$$"
mkdir -p "$stage/src"
trap 'rm -rf "$stage"' EXIT

echo "Downloading ctools (${DEFAULT_CTOOLS_COMMIT:0:12})..."
if ! curl -fsSL "$CTOOLS_URL" -o "$stage/ctools.tar.gz"; then
    echo "ERROR: failed to download ctools from $CTOOLS_URL" >&2
    exit 1
fi

verify_tarball "$stage/ctools.tar.gz"

if ! tar -xzf "$stage/ctools.tar.gz" -C "$stage/src"; then
    echo "ERROR: failed to unpack ctools archive" >&2
    exit 1
fi

src_dir=""
make_dir=""
for entry in "$stage/src"/*; do
    if [ -d "$entry" ] && [ -f "$entry/Makefile" ]; then
        src_dir="$entry"
        make_dir="$entry"
        break
    elif [ -d "$entry/src" ] && [ -f "$entry/src/Makefile" ]; then
        src_dir="$entry"
        make_dir="$entry/src"
        break
    fi
done

if [ -z "$make_dir" ]; then
    echo "ERROR: unpacked ctools source directory with Makefile not found" >&2
    exit 1
fi

jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
cxx_bin="${CXX:-g++}"

echo "Building ctools..."
if ! make -C "$make_dir" -j"$jobs" CC="$cxx_bin" CXX="$cxx_bin"; then
    echo "ERROR: failed to build ctools" >&2
    exit 1
fi

built_ctools="$(find "$src_dir" -type f -name ctools -perm -111 | head -n 1 || true)"
built_cformat="$(find "$src_dir" -type f -name cformat -perm -111 | head -n 1 || true)"

if [ -z "$built_ctools" ] || [ ! -x "$built_ctools" ]; then
    echo "ERROR: built ctools binary not found under $src_dir" >&2
    exit 1
fi
if [ -z "$built_cformat" ] || [ ! -x "$built_cformat" ]; then
    echo "ERROR: built cformat binary not found under $src_dir" >&2
    exit 1
fi

if [ "$has_custom_ctools" -eq 0 ]; then
    cp -f "$built_ctools" "$stage/ctools.new"
    chmod 755 "$stage/ctools.new"
    mv -f "$stage/ctools.new" "$ctools_bin"
fi

if [ "$has_custom_cformat" -eq 0 ]; then
    cp -f "$built_cformat" "$stage/cformat.new"
    chmod 755 "$stage/cformat.new"
    mv -f "$stage/cformat.new" "$cformat_bin"
fi

for lic in LICENSE LICENSE.txt LICENSE.md COPYING README.md; do
    if [ -f "$src_dir/$lic" ]; then
        cp -f "$src_dir/$lic" "$bin_dir/$lic"
    fi
done

printf '%s\n' "$expected_stamp" > "$stamp_file"

if [ ! -x "$ctools_bin" ] || [ ! -x "$cformat_bin" ]; then
    echo "ERROR: ctools/cformat not found after install at $ctools_bin / $cformat_bin" >&2
    exit 1
fi

echo "ctools ready at $ctools_bin and $cformat_bin"
