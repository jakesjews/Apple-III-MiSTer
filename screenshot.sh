#!/bin/zsh
# Take a screenshot on the MiSTer and fetch it locally.
# Usage: ./screenshot.sh [out.png]
set -e
OUT=${1:-shot.png}
HOST=root@mister
PW=1
sshpass -p $PW ssh -o StrictHostKeyChecking=no $HOST 'echo screenshot > /dev/MiSTer_cmd; sleep 2; ls -t /media/fat/screenshots/*/*.png | head -1'
F=$(sshpass -p $PW ssh -o StrictHostKeyChecking=no $HOST 'ls -t /media/fat/screenshots/*/*.png | head -1')
sshpass -p $PW scp -o StrictHostKeyChecking=no "$HOST:$F" "$OUT"
echo "saved $OUT (from $F)"
