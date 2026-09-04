#!/bin/zsh
# Copy the built core to the MiSTer and launch it.
# Usage: ./deploy.sh [path-to-rbf] [path-to-nib]
# The optional NIB uses the reset-then-mount hardware-test MGL.
set -e
cd "$(dirname "$0")"
RBF=${1:-output_files/Apple-III.rbf}
NIB=${2:-}
HOST=root@mister
PW=1
STAMP=$(date +%Y%m%d)

if [[ ! -f "$RBF" ]]; then
	print -u2 "RBF not found: $RBF"
	exit 1
fi

if [[ -n "$NIB" ]]; then
	if [[ ! -f "$NIB" ]]; then
		print -u2 "NIB not found: $NIB"
		exit 1
	fi
	if [[ $(stat -f %z "$NIB") -ne 232960 ]]; then
		print -u2 "NIB must be exactly 232960 bytes: $NIB"
		exit 1
	fi
fi

# Use the development host's date: many MiSTer installations boot without a
# valid RTC/network time and would otherwise archive the core as 19700101.
sshpass -p "$PW" ssh -o StrictHostKeyChecking=no "$HOST" \
	'mkdir -p /media/fat/games/Apple-III /media/fat/_Computer'
sshpass -p "$PW" scp -o StrictHostKeyChecking=no "$RBF" \
	"$HOST:/media/fat/Apple-III.rbf"
sshpass -p "$PW" ssh -o StrictHostKeyChecking=no "$HOST" \
	"cp /media/fat/Apple-III.rbf /media/fat/_Computer/Apple-III_${STAMP}.rbf"
if [[ -n "$NIB" ]]; then
	sshpass -p "$PW" scp -o StrictHostKeyChecking=no "$NIB" \
		"$HOST:/media/fat/games/Apple-III/system.nib"
	sshpass -p "$PW" scp -o StrictHostKeyChecking=no \
		sim/Apple-III-Hardware-Test.mgl "$HOST:/media/fat/Apple-III-Hardware-Test.mgl"
	sshpass -p "$PW" ssh -o StrictHostKeyChecking=no "$HOST" \
		"echo 'load_core /media/fat/Apple-III-Hardware-Test.mgl' > /dev/MiSTer_cmd"
	print "Deployed Apple-III_${STAMP}.rbf and launched $NIB"
else
	sshpass -p "$PW" ssh -o StrictHostKeyChecking=no "$HOST" \
		"echo 'load_core /media/fat/Apple-III.rbf' > /dev/MiSTer_cmd"
	print "Deployed and launched Apple-III_${STAMP}.rbf"
fi
