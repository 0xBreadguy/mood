#!/usr/bin/env bash
# Run the plugin in a hidden Omabox desktop, drive it, and keep captures.
#
#   tools/box-check.sh [OUT_DIR]        default OUT_DIR: scratch/box-check
#   MOOD_SURFACE=<id> tools/box-check.sh [OUT_DIR]     the same checks under another surface
#
# Without MOOD_SURFACE it checks the default look, tine.
#
# It starts a box of its own with Omarchy's stock look and a speaker nobody
# hears, loads the plugin from this checkout, plays real tracks over the
# network, and checks each behaviour, printing one line per check. It never
# touches the real desktop and makes no audible sound. The box is taken down
# at the end. Needs omabox, jq and ImageMagick; exits non-zero if a check fails.
#
# Three states cannot be reached honestly on demand, so the box gets two
# stand-ins, in its own HOME only: a `python3` that can refuse the fetcher its
# connections or stall it, and an `mpv` that can refuse to start.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/scratch/box-check}
ID=0xbreadguy.mood
SURFACE=${MOOD_SURFACE:-tine}
mkdir -p "$OUT"
fails=0

BOX=$(omabox up --new --stock --audio --plugin "$ROOT" 2>"$OUT/up.log" | tail -1)
[ -n "$BOX" ] || { cat "$OUT/up.log"; echo "could not start a box"; exit 2; }
trap 'omabox down -b "$BOX" >/dev/null 2>&1' EXIT
HOME_DIR=$(omabox path -b "$BOX" --home 2>/dev/null)

box() { omabox -b "$BOX" "$@"; }
inbox() { box run -- sh -c "$1" 2>/dev/null; }
ipc() { inbox "omarchy-shell mood $*"; }
field() { inbox "omarchy-shell mood status | jq -r '$1'"; }
pause_for() { box wait for "$1" >/dev/null 2>&1; }
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (wanted $3, got $2)"; fi; }
# Wait until the state is $1, up to $2 seconds.
until_state() {
  local i
  for i in $(seq 1 $(( ${2:-15} * 4 ))); do
    [ "$(field .state)" = "$1" ] && return 0
    pause_for 250ms
  done
  return 1
}
expect_state() { if until_state "$2" "${3:-15}"; then ok "$1"; else bad "$1 (state is $(field .state))"; fi; }

mkdir -p "$HOME_DIR/.local/bin"
cat > "$HOME_DIR/.local/bin/python3" <<'EOF'
#!/bin/sh
# Stand-in for the check: ~/offline refuses the fetcher's connections, ~/slow stalls it.
if [ -e "$HOME/offline" ]; then export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9; fi
if [ -e "$HOME/slow" ]; then sleep 20; fi
exec /usr/bin/python3 "$@"
EOF
cat > "$HOME_DIR/.local/bin/mpv" <<'EOF'
#!/bin/sh
# Stand-in for the check: ~/noplayer makes the player fail to start.
if [ -e "$HOME/noplayer" ]; then exit 3; fi
exec /usr/bin/mpv "$@"
EOF
chmod +x "$HOME_DIR/.local/bin/python3" "$HOME_DIR/.local/bin/mpv"
box restart-shell >/dev/null 2>&1
box dnd on >/dev/null 2>&1
# The checks are about behaviour, so they hold under any surface. Pick it before
# the item is measured: each surface has its own width.
inbox "omarchy bar set $ID surface '$SURFACE'" >/dev/null; pause_for 800ms

X=$(inbox "omarchy-shell shell debugBarGeometry | jq -r '.[] | select(.id==\"$ID\") | .x'")
W=$(inbox "omarchy-shell shell debugBarGeometry | jq -r '.[] | select(.id==\"$ID\") | .width'")
CX=$((X + W / 2)); CY=13
away() { box pointer -- move 900 500 >/dev/null 2>&1; }
shot() { box shot -g "$((X - 150)),0 $((W + 190))x30" --zoom 4 --no-pointer -o "$OUT/$1.png" >/dev/null 2>&1; }
setting() { inbox "omarchy bar set $ID $1 '$2'" >/dev/null; }

echo "box $BOX, plugin at x=$X, width $W, surface $SURFACE"
away

# ---- loading and the catalog
check "the plugin loads and plays nothing by itself" "$(field .state)" stopped
check "thirteen moods" "$(field .mood.of)" 13
check "451 tracks in the catalog" "$(field .catalog.tracks)" 451
check "no player process while stopped" "$(inbox 'pgrep -c -x mpv')" 0
shot state-stopped

# ---- first-open bar controls highlight
check "the popup opens on first use" "$(ipc popup)" ok
pause_for 500ms
box tree --layer omarchy-keyboard-panel > "$OUT/popup-first-open-tree.txt" 2>&1
if grep -q 'current mood.*focused' "$OUT/popup-first-open-tree.txt"; then ok "first open still focuses the current mood"; else bad "first open did not focus the current mood"; fi
if grep -q 'Dismiss bar controls guide' "$OUT/popup-first-open-tree.txt" && grep -q 'Click: Play or pause' "$OUT/popup-first-open-tree.txt"; then
  ok "first open shows the dismissible bar controls highlight"
else
  bad "first open lacked the bar controls highlight"
fi
box shot -g "$((X - 330)),0 $((W + 370))x640" --no-pointer -o "$OUT/popup-first-open.png" >/dev/null 2>&1
box keys Escape >/dev/null 2>&1; pause_for 350ms
check "closing without dismissing keeps the guide for later" "$(inbox 'jq -r ".guideDismissed // false" ~/.local/state/mood/state.json 2>/dev/null || echo false')" false

# ---- both kinds of location, end to end
ipc "set late-night" >/dev/null
box audio 6 > "$OUT/audio.txt" 2>&1 &
ipc play >/dev/null
expect_state "a track from inside the Open Lo-Fi ZIP plays" playing
pause_for 2500ms
check "it is an Open Lo-Fi track" "$(field '.track.id | split(":")[0]')" open-lofi
check "its checksum matched" "$(field .data.lastTrackVerified)" true
check "features are published while it plays" "$(field .features.available)" true
wait
if grep -q '^sound' "$OUT/audio.txt"; then ok "the box's speaker carried sound: $(cat "$OUT/audio.txt")"; else bad "no sound in the box: $(cat "$OUT/audio.txt")"; fi
shot state-playing
ipc "set lo-fi" >/dev/null
expect_state "a direct link from the Internet Archive plays" playing
pause_for 2500ms
check "it is an Internet Archive track" "$(field '.track.id | split(":")[0]')" ia
check "its checksum matched" "$(field .data.lastTrackVerified)" true

# ---- pause, skip, back
ipc pause >/dev/null; expect_state "pause" paused 5; shot state-paused
ipc toggle >/dev/null; expect_state "resume" playing 5
first=$(field .track.id)
check "back with nothing earlier is refused" "$(ipc back)" refused
check "and the track is unchanged" "$(field .track.id)" "$first"
for _ in 1 2 3 4; do ipc skip >/dev/null; done
expect_state "four quick skips settle on one track" playing
pause_for 1s
check "back returns to the track that was heard" "$(ipc back >/dev/null; until_state playing 15; field .track.id)" "$first"

# ---- moods wrap
ipc "set chillhop" >/dev/null
ipc "step -1" >/dev/null
check "stepping back from the first mood wraps to the last" "$(field .mood.index)" 12
shot name-moment
ipc "step 1" >/dev/null
check "stepping on from the last wraps to the first" "$(field .mood.index)" 0
pause_for 1500ms
check "the last mood is written to the state file" "$(inbox 'jq -r .mood ~/.local/state/mood/state.json')" chillhop
expect_state "playing in the new mood" playing

# ---- gestures on the bar item
box click "$CX" "$CY" >/dev/null 2>&1; expect_state "click pauses" paused 5
box click "$CX" "$CY" >/dev/null 2>&1; expect_state "click plays" playing 5
t=$(field .track.id)
box scroll "$CX" "$CY" 15 --source wheel >/dev/null 2>&1; pause_for 500ms; until_state playing 15
if [ "$(field .track.id)" != "$t" ]; then ok "a wheel notch down skips"; else bad "a wheel notch down skips"; fi
check "a bar scroll gesture retires the first-open guide" "$(inbox 'jq -r .guideDismissed ~/.local/state/mood/state.json')" true
box scroll "$CX" "$CY" -15 --source wheel >/dev/null 2>&1; pause_for 500ms; until_state playing 15
check "a wheel notch up goes back" "$(field .track.id)" "$t"
box scroll "$CX" "$CY" 400 --source finger >/dev/null 2>&1; pause_for 500ms; until_state playing 15
if [ "$(field .track.id)" != "$t" ]; then ok "a trackpad swipe down skips"; else bad "a trackpad swipe down skips"; fi
m=$(field .mood.index)
box scroll "$CX" "$CY" 0 15 --source wheel >/dev/null 2>&1; pause_for 400ms
check "a sideways notch steps the mood" "$(field .mood.index)" $((m + 1))
box scroll "$CX" "$CY" 0 -800 --source finger >/dev/null 2>&1; pause_for 400ms
check "one long sideways swipe the other way is exactly one step back" "$(field .mood.index)" "$m"
until_state playing 15; t0=$(field .track.id); m0=$(field .mood.index)
box scroll "$CX" "$CY" 500 300 --source finger >/dev/null 2>&1; pause_for 600ms
m1=$(field .mood.index); t1=$(field .track.id); d=$(( (m1 - m0 + 13) % 13 ))
if [ "$d" = 1 ] || { [ "$d" = 0 ] && [ "$t1" != "$t0" ]; }; then ok "a slanted swipe did one thing: $([ "$d" = 1 ] && echo 'a mood step' || echo 'a skip')"
else bad "a slanted swipe: mood moved by $d, track $t0 -> $t1"; fi
m=$(field .mood.index)
box pointer -- move "$CX" "$CY" down right sleep 150ms scroll 15 sleep 150ms up right >/dev/null 2>&1; pause_for 500ms
check "right button held and a wheel notch steps the mood" "$(field .mood.index)" $((m + 1))
check "and does not open the popup" "$(box hyprctl layers | grep -c 'keyboard-panel,')" 0
away

# ---- the popup, by keyboard
check "the popup opens on request" "$(ipc popup)" ok
pause_for 600ms
box tree --layer omarchy-keyboard-panel > "$OUT/popup-tree.txt" 2>&1
if grep -q 'current mood.*focused' "$OUT/popup-tree.txt"; then ok "it opens with the current mood focused and named"; else bad "the current mood is not focused"; fi
if grep -q 'Dismiss bar controls guide' "$OUT/popup-tree.txt"; then bad "first-open highlight stayed after dismissal"; else ok "the top highlight is gone after dismissal"; fi
box shot -g "$((X - 330)),0 $((W + 370))x640" --no-pointer -o "$OUT/popup.png" >/dev/null 2>&1
m=$(field .mood.index)
box keys Down >/dev/null 2>&1; box keys Return >/dev/null 2>&1; pause_for 500ms
check "Down and Enter choose the next mood" "$(field .mood.index)" $(( (m + 1) % 13 ))
check "and close the popup" "$(box hyprctl layers | grep -c 'keyboard-panel,')" 0
ipc popup >/dev/null; pause_for 500ms
for _ in $(seq 1 16); do
  box tree --layer omarchy-keyboard-panel --find focused 2>/dev/null | grep -q 'Manual controls' && break
  box keys Down >/dev/null 2>&1
done
# Open the manual controls, walk past them to Settings, open that too.
box keys Return >/dev/null 2>&1; box keys Down Down Down Down >/dev/null 2>&1; box keys Return >/dev/null 2>&1; pause_for 400ms
box tree --layer omarchy-keyboard-panel > "$OUT/popup-open-tree.txt" 2>&1
for name in 'Manual controls, expanded' 'Settings, expanded' 'Highlight: Theme' 'Media keys: On' '"Skip"' 'Click: Play or pause' 'Sideways: Change mood, or right-click + scroll'; do
  if grep -q "$name" "$OUT/popup-open-tree.txt"; then ok "the popup names $name"; else bad "the popup lacks $name"; fi
done
box shot -g "$((X - 330)),0 $((W + 370))x1000" --no-pointer -o "$OUT/popup-open.png" >/dev/null 2>&1

# ---- eyedropper: pick a custom highlight color from the screen
# Move from Settings header to Highlight, switch to Custom, move to the swatch,
# activate it, click a desktop pixel in hyprpicker, and check the adopted color.
box keys Down Right Down >/dev/null 2>&1; pause_for 350ms
box tree --layer omarchy-keyboard-panel > "$OUT/popup-custom-tree.txt" 2>&1
if grep -q 'Pick color from screen.*focused' "$OUT/popup-custom-tree.txt"; then
  ok "custom highlight exposes and focuses the screen-pick color swatch"
else
  bad "custom highlight swatch was not focused"
fi
box shot -g "$((X - 330)),0 $((W + 370))x1000" --no-pointer -o "$OUT/popup-swatch-focused.png" >/dev/null 2>&1
# Click the color swatch directly with the pointer, then click a desktop pixel.
swatch_box=$(grep -oE 'button "Pick color from screen".*@[0-9]+,[0-9]+ [0-9]+x[0-9]+' "$OUT/popup-custom-tree.txt" | head -1)
sw_xy=$(echo "$swatch_box" | grep -oE '@[0-9]+,[0-9]+' | tr -d '@')
sw_wh=$(echo "$swatch_box" | grep -oE '[0-9]+x[0-9]+$')
sw_x=$(( ${sw_xy%,*} + ${sw_wh%x*} / 2 ))
sw_y=$(( ${sw_xy#*,} + ${sw_wh#*x} / 2 ))
box click "$sw_x" "$sw_y" >/dev/null 2>&1
# Wait for the popup fade-out + hyprpicker startup, then click the desktop.
for _ in $(seq 1 30); do
  [ "$(inbox 'pgrep -c -x hyprpicker')" -ge 1 ] && break
  pause_for 100ms
done
check "clicking the swatch hides the popup before picking" "$(box hyprctl layers | grep -c 'keyboard-panel,')" 0
check "and launches hyprpicker" "$(inbox 'pgrep -c -x hyprpicker')" 1
pause_for 200ms
box click 500 500 >/dev/null 2>&1
for _ in $(seq 1 30); do
  [ "$(inbox 'pgrep -c -x hyprpicker')" -eq 0 ] && break
  pause_for 100ms
done
pause_for 500ms
picked=$(inbox "jq -r '.. | objects | select(.id? == \"$ID\") | .highlight // empty' ~/.config/omarchy/shell.json | head -1")
if echo "$picked" | grep -qE '^#[0-9a-f]{6}$' && [ "$picked" != "#7aa2f7" ]; then
  ok "clicking the screen adopts the sampled color ($picked)"
else
  bad "expected a sampled hex color different from #7aa2f7, got '$picked'"
fi
check "the popup reopens after picking" "$(box hyprctl layers | grep -c 'keyboard-panel,')" 1
box tree --layer omarchy-keyboard-panel > "$OUT/popup-picked-tree.txt" 2>&1
if grep -q 'Pick color from screen.*focused' "$OUT/popup-picked-tree.txt"; then
  ok "and keeps Settings open with the swatch focused"
else
  bad "popup did not reopen with the swatch focused"
fi
if grep -q "'$picked'" "$OUT/popup-picked-tree.txt"; then
  ok "and updates the hex field to the picked color"
else
  bad "hex field did not update to '$picked'"
fi
box shot -g "$((X - 330)),0 $((W + 370))x1000" --no-pointer -o "$OUT/popup-picked.png" >/dev/null 2>&1
# Keyboard Return on the focused swatch also launches hyprpicker, and Escape cancels cleanly.
box keys Return >/dev/null 2>&1
for _ in $(seq 1 30); do
  [ "$(inbox 'pgrep -c -x hyprpicker')" -ge 1 ] && break
  pause_for 100ms
done
pause_for 200ms
box keys Escape >/dev/null 2>&1
for _ in $(seq 1 30); do
  [ "$(inbox 'pgrep -c -x hyprpicker')" -eq 0 ] && break
  pause_for 100ms
done
pause_for 500ms
after_cancel=$(inbox "jq -r '.. | objects | select(.id? == \"$ID\") | .highlight // empty' ~/.config/omarchy/shell.json | head -1")
check "cancelling hyprpicker with Escape keeps the highlight color unchanged" "$after_cancel" "$picked"
check "and reopens the popup cleanly" "$(box hyprctl layers | grep -c 'keyboard-panel,')" 1
box keys Escape >/dev/null 2>&1; pause_for 400ms
check "Escape closes it" "$(box hyprctl layers | grep -c 'keyboard-panel,')" 0
setting highlight theme; pause_for 300ms

# ---- settings apply live
setting highlight '#e0af68'; pause_for 600ms; shot setting-highlight
setting moodScroll vertical; pause_for 300ms
m=$(field .mood.index)
box scroll "$CX" "$CY" 15 --source wheel >/dev/null 2>&1; pause_for 400ms
check "with the axes swapped, a wheel notch down steps the mood" "$(field .mood.index)" $(( (m + 1) % 13 ))
setting moodScroll sideways
setting animation steady; pause_for 500ms
check "the steady variant stops the measuring" "$(field .features.wanted)" false
setting animation follow; setting highlight theme; away

# ---- media keys, by the route the keys take
until_state playing 15
t=$(field .track.id)
check "the desktop is told the mood's name, not the track's" "$(inbox 'omarchy-shell media status | jq -r .title')" "$(field .mood.label)"
inbox 'omarchy-shell media playPause' >/dev/null; expect_state "the play/pause key pauses" paused 5
# The desktop's media service learns of the pause a moment after the plugin
# does. A second press before then is sent as "pause" again and changes
# nothing: 10 of 24 were lost with no gap, none of 12 with this one.
pause_for 700ms
inbox 'omarchy-shell media playPause' >/dev/null; expect_state "and plays" playing 5
inbox 'omarchy-shell media next' >/dev/null; pause_for 600ms; until_state playing 15
if [ "$(field .track.id)" != "$t" ]; then ok "the next key skips"; else bad "the next key skips"; fi
inbox 'omarchy-shell media previous' >/dev/null; pause_for 600ms; until_state playing 15
check "the previous key goes back" "$(field .track.id)" "$t"

# ---- reduced motion
inbox 'omarchy toggle animations off' >/dev/null; pause_for 1500ms
check "with animations off nothing is measured" "$(field .features.wanted)" false
box shot -g "$X,0 ${W}x26" --no-pointer -o "$OUT/still-a.png" >/dev/null 2>&1; pause_for 500ms
box shot -g "$X,0 ${W}x26" --no-pointer -o "$OUT/still-b.png" >/dev/null 2>&1
if cmp -s "$OUT/still-a.png" "$OUT/still-b.png"; then ok "and the playing mark holds still"; else bad "the playing mark moved with animations off"; fi
rm -f "$OUT/still-a.png" "$OUT/still-b.png"
inbox 'omarchy toggle animations on' >/dev/null; pause_for 1500ms
check "with animations on it is measured again" "$(field .features.wanted)" true

# ---- the network going away, and coming back
inbox 'touch ~/offline'; ipc skip >/dev/null
expect_state "with the network cut, the state is offline" offline 10; shot state-offline
check "it will retry by itself" "$(field '.failure.retryInSeconds > 0')" true
inbox 'rm ~/offline'
expect_state "with the network back, it recovers without being asked" playing 45
inbox 'touch ~/offline'; ipc skip >/dev/null; until_state offline 10; inbox 'rm ~/offline'; ipc toggle >/dev/null
expect_state "a click while offline retries at once" playing 10

# ---- loading and failed, for the captures
ipc stop >/dev/null; inbox 'touch ~/slow'; ipc play >/dev/null; pause_for 1200ms
check "a slow fetch reads as loading, not playing" "$(field .state)" loading; shot state-loading
inbox 'rm ~/slow'; ipc stop >/dev/null
inbox 'touch ~/noplayer'; ipc play >/dev/null
expect_state "a player that will not start reads as failed" failed 10; shot state-failed
inbox 'rm ~/noplayer'; ipc stop >/dev/null
check "stop lets the player go" "$(pause_for 800ms; inbox 'pgrep -c -x mpv')" 0

# ---- the tooltip
ipc play >/dev/null; until_state playing 15
box pointer --steps 8 -- move "$CX" "$CY" >/dev/null 2>&1; pause_for 1500ms
box shot -g "$((X - 250)),0 $((W + 290))x90" -o "$OUT/tooltip.png" >/dev/null 2>&1
away; ipc stop >/dev/null

# ---- playing into nothing, for development
setting audio null; pause_for 300ms
box audio 5 > "$OUT/audio-null.txt" 2>&1 &
ipc play >/dev/null
expect_state "with audio set to null it still plays, in real time" playing
pause_for 3s
if [ "$(field .positionSeconds)" -ge 2 ]; then ok "and the position advances"; else bad "the position did not advance"; fi
wait
if grep -q '^silence' "$OUT/audio-null.txt"; then ok "and the box's speaker stayed silent"; else bad "sound reached the speaker: $(cat "$OUT/audio-null.txt")"; fi
rm -f "$OUT/audio-null.txt"
setting audio auto; ipc stop >/dev/null

# ---- taking the plugin off the bar while it plays
ipc play >/dev/null; until_state playing 15
inbox "omarchy plugin disable $ID" >/dev/null 2>&1; pause_for 1500ms
check "disabling the plugin while it plays stops the player" "$(inbox 'pgrep -c -x mpv')" 0
inbox "omarchy plugin enable $ID" >/dev/null 2>&1; pause_for 1500ms
check "enabling it again starts nothing by itself" "$(field .state)" stopped

( cd "$OUT" && magick montage state-stopped.png state-loading.png state-playing.png state-paused.png \
    state-offline.png state-failed.png name-moment.png setting-highlight.png \
    -tile 2x4 -geometry +4+4 -background '#444' states.png 2>/dev/null \
  && rm -f state-*.png name-moment.png setting-highlight.png )
{ echo "revision: $(git -C "$ROOT" rev-parse --short HEAD)$(git -C "$ROOT" diff --quiet HEAD -- plugin catalog manifest.json || echo ' (with uncommitted changes)')"
  echo "date: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "omarchy: $(omarchy version 2>/dev/null)  quickshell: $(inbox 'quickshell --version' | head -1)  mpv: $(inbox '/usr/bin/mpv --version' | head -1 | cut -d' ' -f1-2)"
} > "$OUT/run.txt"
rm -f "$OUT/up.log"

echo
if [ "$fails" -eq 0 ]; then echo "all checks passed; captures in $OUT"; else echo "$fails checks FAILED; captures in $OUT"; fi
exit "$fails"
