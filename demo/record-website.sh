#!/usr/bin/env bash
# Records the website card animation: demo/website-demo.sh played in
# cool-retro-term on a headless X server, cut to exactly one cycle, and encoded
# as a square looping WebP. The CRT look comes from demo/website-crt-profile.json
# (Default Amber with a darker bezel and amber background glow), tuned to match
# the opcilloscope card on squarewavesystems.com.au.
#
# Usage:
#   demo/record-website.sh [output.webp]
#
# Environment:
#   SQUAREBOX_DEMO_CAPTURE  capture size in px, square (default 540); larger
#                           fits more terminal columns
#   SQUAREBOX_DEMO_SIZE     output size in px, square (default 400)
#   SQUAREBOX_DEMO_FPS      output frame rate (default 14, ~70ms frames)
#   SQUAREBOX_DEMO_QUALITY  WebP quality 0-100 (default 80)
#   SQUAREBOX_DEMO_PROFILE  cool-retro-term profile JSON
#                           (default demo/website-crt-profile.json)
#
# Requires: cool-retro-term, Xvfb, ffmpeg (with libwebp), ffprobe, sqlite3,
#           gum, toilet
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$SCRIPT_DIR/squarebox-retro.webp}"
CAPTURE="${SQUAREBOX_DEMO_CAPTURE:-540}"
SIZE="${SQUAREBOX_DEMO_SIZE:-400}"
FPS="${SQUAREBOX_DEMO_FPS:-14}"
QUALITY="${SQUAREBOX_DEMO_QUALITY:-80}"
PROFILE="${SQUAREBOX_DEMO_PROFILE:-$SCRIPT_DIR/website-crt-profile.json}"

for cmd in cool-retro-term Xvfb ffmpeg ffprobe sqlite3 gum toilet; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done
[ -r "$PROFILE" ] || { echo "Error: profile $PROFILE not readable" >&2; exit 1; }

work="$(mktemp -d)"
pids=()
cleanup() {
    local pid
    for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
    wait 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

# Headless X server; -displayfd picks a free display number.
Xvfb -displayfd 3 -screen 0 "${CAPTURE}x${CAPTURE}x24" -nolisten tcp \
    3>"$work/display" 2>"$work/xvfb.log" &
pids+=($!)
for _ in $(seq 50); do [ -s "$work/display" ] && break; sleep 0.1; done
[ -s "$work/display" ] || { echo "Error: Xvfb did not start" >&2; cat "$work/xvfb.log" >&2; exit 1; }
export DISPLAY=":$(tr -d '[:space:]' < "$work/display")"

# Keep cool-retro-term settings out of the user's real profile. There is no
# window manager, so size the window with Qt's X11 -geometry (not --fullscreen).
export XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache"
export QT_QPA_PLATFORM=xcb
unset WAYLAND_DISPLAY

# Seed cool-retro-term's QML LocalStorage database with the profile as a custom
# profile, then select it by name. The file name is md5("coolretroterm2").
profile_name="squarebox website"
db_dir="$XDG_DATA_HOME/cool-retro-term/cool-retro-term/QML/OfflineStorage/Databases"
db="$db_dir/$(printf coolretroterm2 | md5sum | cut -d' ' -f1)"
mkdir -p "$db_dir"
printf '[General]\nDescription=StorageDatabase\nDriver=QSQLITE\nEstimatedSize=100000\nName=coolretroterm2\nVersion=1.0\n' > "$db.ini"
sqlite3 "$db.sqlite" \
    "CREATE TABLE settings(setting TEXT UNIQUE, value TEXT);
     INSERT INTO settings VALUES ('_CUSTOM_PROFILES', json_array(json_object(
         'text', '$profile_name',
         'obj_string', CAST(readfile('${PROFILE//\'/\'\'}') AS TEXT),
         'builtin', json('false'))));"

marks="$work/marks"
: > "$marks"
SQUAREBOX_DEMO_LOOPS=0 SQUAREBOX_DEMO_MARK="$marks" \
    cool-retro-term -geometry "${CAPTURE}x${CAPTURE}+0+0" --profile "$profile_name" \
    -e bash "$SCRIPT_DIR/website-demo.sh" >"$work/crt.log" 2>&1 &
pids+=($!)

# Timestamps stay wall-clock (-copyts) so the cycle marks map onto frames.
ffmpeg -hide_banner -loglevel error -nostdin \
    -f x11grab -draw_mouse 0 -framerate 30 -video_size "${CAPTURE}x${CAPTURE}" -i "$DISPLAY" \
    -copyts -c:v libx264 -preset ultrafast -qp 0 "$work/raw.mkv" &
ffmpeg_pid=$!
pids+=("$ffmpeg_pid")

# Loop 1 absorbs startup; record loop 2 (between marks 2 and 3).
echo "Recording (two demo cycles, ~25s)..."
for _ in $(seq 600); do
    [ "$(wc -l < "$marks")" -ge 3 ] && break
    kill -0 "$ffmpeg_pid" 2>/dev/null || { echo "Error: ffmpeg exited early" >&2; exit 1; }
    sleep 0.1
done
[ "$(wc -l < "$marks")" -ge 3 ] || { echo "Error: demo did not complete two cycles" >&2; cat "$work/crt.log" >&2; exit 1; }
if grep -q 'selected profile is not valid' "$work/crt.log"; then
    echo "Error: cool-retro-term did not load the seeded profile" >&2
    exit 1
fi
sleep 0.5
kill -INT "$ffmpeg_pid"
wait "$ffmpeg_pid" 2>/dev/null || true

start_ts="$(ffprobe -v error -show_entries format=start_time -of csv=p=0 "$work/raw.mkv")"
read -r m2 m3 < <(sed -n '2p;3p' "$marks" | paste -sd' ')
offset="$(awk -v a="$m2" -v s="$start_ts" 'BEGIN { printf "%.3f", a - s }')"
duration="$(awk -v a="$m2" -v b="$m3" 'BEGIN { printf "%.3f", b - a }')"
echo "Cycle: ${duration}s at +${offset}s"
awk -v o="$offset" 'BEGIN { exit !(o > 0) }' || { echo "Error: cycle marks precede the recording" >&2; exit 1; }

ffmpeg -hide_banner -loglevel error -y \
    -ss "$offset" -t "$duration" -i "$work/raw.mkv" \
    -vf "fps=$FPS,scale=$SIZE:$SIZE:flags=lanczos" \
    -c:v libwebp_anim -lossless 0 -quality "$QUALITY" -compression_level 6 -loop 0 -an \
    "$OUT"

ls -lh "$OUT"
