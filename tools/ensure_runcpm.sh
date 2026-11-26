#!/usr/bin/env bash
set -euo pipefail

DEFAULT_RUNCPM_COMMIT="12fc57a1784b8fc97dae30eb5dffedccf098bbd5"
DEFAULT_RUNCPM_URL="https://github.com/MockbaTheBorg/RunCPM/archive/${DEFAULT_RUNCPM_COMMIT}.tar.gz"
DEFAULT_RUNCPM_TARBALL_SHA256="829d6f444aa343c104715c6c22ccd2dfa0eb4716132400832d34c6e3ca330a96"

custom=0
if [ "${1:-}" = "--custom" ]; then
    custom=1
    shift
fi

if [ "$#" -gt 2 ]; then
    echo "usage: $0 [--custom] [runcpm_dir] [runcpm_bin]" >&2
    exit 2
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
runcpm_dir="${1:-$script_dir/runcpm}"
default_bin="$runcpm_dir/RunCPM"

if [ "$#" -eq 2 ]; then
    runcpm_bin="$2"
elif [ -n "${RUNCPM:-}" ]; then
    runcpm_bin="$RUNCPM"
else
    runcpm_bin="$default_bin"
fi

check_custom_bin() {
    local bin_path="$1"
    if [ -x "$bin_path" ]; then
        return 0
    fi
    if [[ "$bin_path" != */* ]] && command -v "$bin_path" >/dev/null 2>&1; then
        return 0
    fi
    echo "ERROR: custom RUNCPM binary does not exist or is not executable: $bin_path" >&2
    return 1
}

if [ "$custom" -eq 1 ]; then
    check_custom_bin "$runcpm_bin"
    exit 0
fi

if [ -n "${RUNCPM:-}" ] && [ "$runcpm_bin" != "$default_bin" ]; then
    check_custom_bin "$runcpm_bin"
    exit 0
fi

RUNCPM_URL="${RUNCPM_URL:-$DEFAULT_RUNCPM_URL}"
RUNCPM_TARBALL_SHA256="${RUNCPM_TARBALL_SHA256:-$DEFAULT_RUNCPM_TARBALL_SHA256}"

if [ -n "${SHA256:-}" ]; then
    read -r -a sha_cmd <<< "$SHA256"
elif [ -n "${SHASUM:-}" ]; then
    sha_cmd=("$SHASUM" -a 256)
elif command -v sha256sum >/dev/null 2>&1; then
    sha_cmd=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
    sha_cmd=(shasum -a 256)
else
    echo "ERROR: sha256sum or shasum is required to verify RunCPM tarball" >&2
    exit 1
fi

verify_tarball() {
    local tarball_path="$1"
    if printf '%s  %s\n' "$RUNCPM_TARBALL_SHA256" "$tarball_path" | "${sha_cmd[@]}" -c - >/dev/null 2>&1; then
        return 0
    fi
    local actual=""
    actual="$("${sha_cmd[@]}" "$tarball_path" 2>/dev/null | awk '{print $1}')" || actual="unknown"
    echo "ERROR: RunCPM tarball SHA-256 mismatch" >&2
    echo "  expected: $RUNCPM_TARBALL_SHA256" >&2
    echo "  actual:   $actual" >&2
    echo "  override with RUNCPM=/path/to/RunCPM or RUNCPM_TARBALL_SHA256=..." >&2
    return 1
}

bin_dir="$(dirname "$runcpm_bin")"
stamp_file="$bin_dir/.runcpm.sha256"
host_os="$(uname -s 2>/dev/null || echo unknown)"
host_arch="$(uname -m 2>/dev/null || echo unknown)"
host_id="${host_os}-${host_arch}"
expected_stamp="${RUNCPM_TARBALL_SHA256} ${host_id}"

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

if [ -x "$runcpm_bin" ] && bin_matches_host_os "$runcpm_bin"; then
    if [ -f "$stamp_file" ]; then
        installed_sha="$(cat "$stamp_file" 2>/dev/null || true)"
        if [ "$installed_sha" = "$expected_stamp" ]; then
            exit 0
        elif [ "$installed_sha" = "$RUNCPM_TARBALL_SHA256" ]; then
            printf '%s\n' "$expected_stamp" > "$stamp_file"
            exit 0
        fi
    else
        exit 0
    fi
fi

mkdir -p "$runcpm_dir" "$bin_dir"
stage="$runcpm_dir/.stage.$$"
mkdir -p "$stage/src"
trap 'rm -rf "$stage"' EXIT

echo "Downloading RunCPM (${DEFAULT_RUNCPM_COMMIT:0:12})..."
if ! curl -fsSL "$RUNCPM_URL" -o "$stage/runcpm.tar.gz"; then
    echo "ERROR: failed to download RunCPM from $RUNCPM_URL" >&2
    exit 1
fi

verify_tarball "$stage/runcpm.tar.gz"

if ! tar -xzf "$stage/runcpm.tar.gz" -C "$stage/src"; then
    echo "ERROR: failed to unpack RunCPM archive" >&2
    exit 1
fi

src_dir=""
for entry in "$stage/src"/*; do
    if [ -d "$entry/RunCPM" ] && [ -f "$entry/RunCPM/Makefile" ]; then
        src_dir="$entry"
        break
    fi
done

if [ -z "$src_dir" ]; then
    echo "ERROR: unpacked RunCPM source directory not found" >&2
    exit 1
fi

jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
cc_bin="${CC:-gcc}"

echo "Building RunCPM (POSIX)..."
if ! make -C "$src_dir/RunCPM" -j"$jobs" CC="$cc_bin" posix build; then
    echo "ERROR: failed to build RunCPM" >&2
    exit 1
fi

built_bin="$src_dir/RunCPM/RunCPM"
if [ ! -x "$built_bin" ]; then
    echo "ERROR: built RunCPM binary not found at $built_bin" >&2
    exit 1
fi

cp -f "$built_bin" "$stage/RunCPM.new"
chmod 755 "$stage/RunCPM.new"
mv -f "$stage/RunCPM.new" "$runcpm_bin"
if [ -f "$src_dir/LICENSE" ]; then
    cp -f "$src_dir/LICENSE" "$bin_dir/LICENSE"
fi
printf '%s\n' "$expected_stamp" > "$stamp_file"

if [ ! -x "$runcpm_bin" ]; then
    echo "ERROR: RunCPM not found after install at $runcpm_bin" >&2
    exit 1
fi

echo "RunCPM ready at $runcpm_bin"
