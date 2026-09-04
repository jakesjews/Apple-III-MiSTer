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

IMAGE_NAME=""
if [[ -n "$NIB" ]]; then
	if [[ ! -f "$NIB" ]]; then
		print -u2 "disk image not found: $NIB"
		exit 1
	fi
	case $(stat -f %z "$NIB") in
		232960) IMAGE_NAME=system.nib ;;
		143360) IMAGE_NAME=system.dsk ;;
		*)
			print -u2 "disk image must be 232960 bytes (NIB) or 143360 bytes (DSK/DO/PO): $NIB"
			exit 1
			;;
	esac
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
		"$HOST:/media/fat/games/Apple-III/$IMAGE_NAME"
	# The MGL names the image, so generate it for whichever format was given.
	# Paths follow the MiSTer rules: rbf relative to the SD root without the
	# extension or date stamp, file relative to the core's games folder.
	sed "s|<file \(.*\)path=\"[^\"]*\"|<file \1path=\"$IMAGE_NAME\"|" \
		sim/Apple-III-Hardware-Test.mgl > /tmp/apple3-launch.mgl
	sshpass -p "$PW" scp -o StrictHostKeyChecking=no \
		/tmp/apple3-launch.mgl "$HOST:/media/fat/Apple-III-Hardware-Test.mgl"
	sshpass -p "$PW" ssh -o StrictHostKeyChecking=no "$HOST" \
		"echo 'load_core /media/fat/Apple-III-Hardware-Test.mgl' > /dev/MiSTer_cmd"
	print "Deployed Apple-III_${STAMP}.rbf and launched $NIB as $IMAGE_NAME"
else
	sshpass -p "$PW" ssh -o StrictHostKeyChecking=no "$HOST" \
		"echo 'load_core /media/fat/Apple-III.rbf' > /dev/MiSTer_cmd"
	print "Deployed and launched Apple-III_${STAMP}.rbf"
fi
