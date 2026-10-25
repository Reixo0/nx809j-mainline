#!/bin/bash
# Build the AudioReach topology (audio/topology/Nubia-NX809J.m4) with the
# m4 library of tools/dl/infiniti-tplg (github infiniti-mainline/audioreach-topology).
# SD_LINE picks the primary MI2S data line of the speakers (SD0 or SD1).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB=$ROOT/tools/dl/infiniti-tplg
SD_LINE=${SD_LINE:-SD1}
OUT=$ROOT/out/audio/qcom/kaanapali
mkdir -p "$OUT"
m4 -I "$LIB" -D NX809J_SPK_SD_LINE=SD_LINE_IDX_I2S_$SD_LINE \
	"$ROOT/audio/topology/Nubia-NX809J.m4" > "$OUT/Nubia-NX809J.conf"
alsatplg -c "$OUT/Nubia-NX809J.conf" -o "$OUT/Nubia-NX809J-tplg.bin"
echo "$OUT/Nubia-NX809J-tplg.bin ($SD_LINE)"
