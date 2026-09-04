#!/bin/zsh
# Copy the built core to the MiSTer and launch it.
# Usage: ./deploy.sh [path-to-rbf]   (default: output_files/Apple-III.rbf)
set -e
cd "$(dirname "$0")"
RBF=${1:-output_files/Apple-III.rbf}
HOST=root@mister
PW=1
sshpass -p $PW scp -o StrictHostKeyChecking=no "$RBF" $HOST:/media/fat/Apple-III.rbf
sshpass -p $PW ssh -o StrictHostKeyChecking=no $HOST 'mkdir -p /media/fat/games/Apple-III /media/fat/_Computer; cp /media/fat/Apple-III.rbf "/media/fat/_Computer/Apple-III_$(date +%Y%m%d).rbf"; echo "load_core /media/fat/Apple-III.rbf" > /dev/MiSTer_cmd; echo launched'
