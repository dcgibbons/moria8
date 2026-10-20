#!/bin/sh
# Convert an emulator gameplay capture (VICE "Save/Record media", MAME
# -aviwrite, or a macOS screen recording) into an optimized looping GIF for
# the website.
#
# Usage: make_gameplay_gif.sh INPUT OUTPUT [START] [DURATION] [WIDTH]
#   INPUT     .avi/.mov/.gif capture
#   OUTPUT    .gif path
#   START     start offset in seconds (default 0)
#   DURATION  seconds to include (default: whole input)
#   WIDTH     output width in px (default: keep source width)
# Environment: FPS output frame rate (default 12), COLORS palette size (default 128),
#              DITHER paletteuse dither mode (default bayer; "none" suits flat text screens)
set -eu

if [ "$#" -lt 2 ]; then
    echo "usage: make_gameplay_gif.sh INPUT OUTPUT [START] [DURATION] [WIDTH]" >&2
    exit 2
fi

input=$1
output=$2
start=${3:-0}
duration=${4:-}
width=${5:--1}

trim=""
if [ -n "$duration" ]; then
    trim="-t $duration"
fi

scale="scale=${width}:-1:flags=lanczos"
if [ "$width" = "-1" ]; then
    scale="null"
fi

palette=$(mktemp -t gameplay_pal).png
trap 'rm -f "$palette"' EXIT

# Pass 1: generate a palette from the actual frames.
# shellcheck disable=SC2086
ffmpeg -hide_banner -loglevel error -ss "$start" $trim -i "$input" \
    -vf "fps=${FPS:-12},${scale},palettegen=max_colors=${COLORS:-128}:stats_mode=diff" \
    -y "$palette"

# Pass 2: map frames through the palette.
# shellcheck disable=SC2086
ffmpeg -hide_banner -loglevel error -ss "$start" $trim -i "$input" -i "$palette" \
    -lavfi "fps=${FPS:-12},${scale} [x]; [x][1:v] paletteuse=dither=${DITHER:-bayer}:bayer_scale=5:diff_mode=rectangle" \
    -loop 0 -y "$output"

ls -la "$output"
