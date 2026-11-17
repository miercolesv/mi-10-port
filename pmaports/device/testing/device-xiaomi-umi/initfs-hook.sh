#!/bin/sh
# Make the Mi 10 panel visible during early boot.
#
# 1. On some boots the panel IC misses the on-sequence even though the DSI
#    link is fine. The panel driver exposes "repower" to send it again; it is
#    idempotent and does not touch brightness. The DSI link must be up, so
#    unblank the framebuffer first.
# 2. The panel driver starts at brightness 1 of 2047, and this AMOLED stays
#    black up to roughly 400. Raise it to 1500, the value the mainline
#    bring-up settled on.

panel=/sys/bus/mipi-dsi/devices/ae94000.dsi.0

echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
if [ -w "$panel/repower" ]; then
	echo 1 > "$panel/repower" 2>/dev/null
fi

for bl in /sys/class/backlight/*; do
	[ -w "$bl/brightness" ] || continue
	max="$(cat "$bl/max_brightness" 2>/dev/null)"
	level=1500
	if [ -n "$max" ] && [ "$level" -gt "$max" ]; then
		level="$max"
	fi
	# A write only reaches the panel when the value changes
	echo 0 > "$bl/brightness" 2>/dev/null
	sleep 0.2
	echo "$level" > "$bl/brightness" 2>/dev/null
done
