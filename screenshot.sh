#!/bin/zsh
# Take a screenshot on the MiSTer and fetch it locally.
# Usage: ./screenshot.sh [out.png]
set -e
OUT=${1:-shot.png}
HOST=root@mister
PW=1
SCREENSHOT_GLOB='/media/fat/screenshots/Apple-III/*.png'
sshpass -p $PW ssh -o StrictHostKeyChecking=no $HOST \
	"echo screenshot > /dev/MiSTer_cmd; sleep 2; ls -t $SCREENSHOT_GLOB | head -1"
# Restrict the lookup to this core. MiSTer may boot without a valid RTC, so a
# newer screenshot can otherwise sort behind an old file from another core.
F=$(sshpass -p $PW ssh -o StrictHostKeyChecking=no $HOST \
	"ls -t $SCREENSHOT_GLOB | head -1")
sshpass -p $PW scp -o StrictHostKeyChecking=no "$HOST:$F" "$OUT"
echo "saved $OUT (from $F)"
