#!/bin/bash
# Compare battery power and temperatures while playing a video with software
# and hardware (iris) decoding. Runs on the phone, on battery, with the
# screen on and untouched: brightness, network and apps should stay the same
# for every run.
#
# Usage: video-power-test.sh CLIP [seconds per run]   (default 180)
#   Runs, in order: idle (a still frame of the clip), software decode,
#   hardware decode. Each run waits 30 s to settle, then samples every 2 s.
#   Results go to /var/tmp/video-power-<time>/ (samples + summary.txt).
set -euo pipefail
CLIP=${1:?usage: $0 CLIP [seconds]}
SECS=${2:-180}
BAT=/sys/class/power_supply/qcom-battmgr-bat
OUT=/var/tmp/video-power-$(date +%H%M)
mkdir -p "$OUT"
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 SDL_VIDEODRIVER=wayland

[[ $(cat $BAT/status) == Discharging ]] || { echo "unplug the charger first" >&2; exit 1; }

zone() {	# highest temperature (milli-degrees) of the zones matching $1
	local best=0 z t
	for z in /sys/class/thermal/thermal_zone*; do
		[[ $(cat "$z/type") == $1 ]] || continue
		t=$(cat "$z/temp" 2>/dev/null) || continue
		(( t > best )) && best=$t
	done
	echo $best
}

cpu_busy() {	# jiffies busy and total, from /proc/stat
	read -r _ u n s i w x y z _ < /proc/stat
	echo $((u + n + s + x + y + z)) $((u + n + s + i + w + x + y + z))
}

run() {	# name, then the player command (or nothing for idle)
	local name=$1; shift
	local pid= f=$OUT/$name.csv
	if (($#)); then "$@" >/dev/null 2>&1 & pid=$!; fi
	sleep 30
	echo "uw,bat_mc,cpu_mc,gpu_mc,cpu_pct" > "$f"
	read -r b0 t0 < <(cpu_busy)
	local end=$((SECONDS + SECS))
	while ((SECONDS < end)); do
		sleep 2
		read -r b1 t1 < <(cpu_busy)
		echo "$(cat $BAT/power_now),$(cat $BAT/temp)00,$(zone 'cpu*'),$(zone 'gpuss*'),$(( 100 * (b1 - b0) / (t1 - t0 + 1) ))" >> "$f"
		b0=$b1 t0=$t1
	done
	[[ -n $pid ]] && kill "$pid" 2>/dev/null; wait 2>/dev/null || true
	awk -F, -v n="$name" 'NR > 1 { w += ($1 < 0 ? -$1 : $1); c++; if ($2 > b) b = $2; if ($3 > p) p = $3; if ($4 > g) g = $4; u += $5 }
		END { printf "%-9s %5.0f mW  battery max %4.1f C  cpu max %4.1f C  gpu max %4.1f C  cpu %3.0f%%\n",
			n, w / c / 1000, b / 1000, p / 1000, g / 1000, u / c }' "$f" | tee -a "$OUT/summary.txt"
	sleep 20	# let things cool a little before the next run
}

echo "brightness $(cat /sys/class/backlight/*/brightness), decoder $(cat /sys/bus/platform/devices/2000000.video-codec/power/runtime_status 2>/dev/null || echo absent)" | tee "$OUT/summary.txt"
# A still frame of the clip keeps the screen on (ffplay holds an idle
# inhibitor) with the same picture: shown once, not looped, so nothing decodes.
# The clip must last longer than 30 s + the run: hardware decoding stops after
# a seek (ffplay -loop), so nothing loops
STILL=$OUT/still.png
ffmpeg -hide_banner -loglevel error -y -ss 5 -i "$CLIP" -frames:v 1 "$STILL"
run idle ffplay -hide_banner -loglevel error -fs -an "$STILL"
run software ffplay -hide_banner -loglevel error -fs -an "$CLIP"
run hardware ffplay -hide_banner -loglevel error -fs -an -vcodec h264_v4l2m2m "$CLIP"
echo "results in $OUT"
