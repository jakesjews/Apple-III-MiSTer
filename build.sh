#!/bin/zsh
# Build the Apple-III MiSTer core with Quartus 17.0 running under CrossOver.
# Usage: ./build.sh [map|compile|clean]   (default: compile)
#   map     - synthesis only (fast syntax/elaboration check)
#   compile - full flow (map, fit, asm, sta) -> output_files/Apple-III.rbf
set -e
cd "$(dirname "$0")"
CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin
QBIN="C:/intelFPGA_lite/17.0/quartus/bin64"
PROJ=Apple-III
MODE=${1:-compile}
LOG=build_${MODE}.log
run_q() { "$CX/wine" --bottle Quartus --workdir "$PWD" --cx-app "$QBIN/$1" "${@:2}"; }

prepare_rom() {
  local rom=${APPLE3_ROM:-research/roms/apple3.rom}
  local generated=rtl/rom/apple3.rom.hex
  local low=rtl/rom/apple3-low.mif
  local high=rtl/rom/apple3-high.mif
  local bytes
  local temporary
  local low_hex
  local high_hex
  local low_mif
  local high_mif

  if [[ ! -f "$rom" ]]; then
    print -u2 "Apple /// ROM not found: $rom"
    print -u2 "Set APPLE3_ROM to a 4096- or 8192-byte ROM image."
    exit 1
  fi

  bytes=$(wc -c < "$rom" | tr -d ' ')
  if [[ "$bytes" != 4096 && "$bytes" != 8192 ]]; then
    print -u2 "Apple /// ROM must be 4096 or 8192 bytes (got $bytes): $rom"
    exit 1
  fi

  mkdir -p rtl/rom
  temporary=$(mktemp "${TMPDIR:-/tmp}/apple3-rom.XXXXXX")
  if [[ "$bytes" == 4096 ]]; then
    (xxd -p -c 1 "$rom"; xxd -p -c 1 "$rom") > "$temporary"
  else
    xxd -p -c 1 "$rom" > "$temporary"
  fi

  low_hex=$(mktemp "${TMPDIR:-/tmp}/apple3-rom-low-hex.XXXXXX")
  high_hex=$(mktemp "${TMPDIR:-/tmp}/apple3-rom-high-hex.XXXXXX")
  low_mif=$(mktemp "${TMPDIR:-/tmp}/apple3-rom-low-mif.XXXXXX")
  high_mif=$(mktemp "${TMPDIR:-/tmp}/apple3-rom-high-mif.XXXXXX")
  sed -n '1,4096p' "$temporary" > "$low_hex"
  sed -n '4097,8192p' "$temporary" > "$high_hex"
  awk 'BEGIN { print "WIDTH=8;\nDEPTH=4096;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN" } { printf "%03X : %s;\n", NR-1, $1 } END { print "END;" }' "$low_hex" > "$low_mif"
  awk 'BEGIN { print "WIDTH=8;\nDEPTH=4096;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN" } { printf "%03X : %s;\n", NR-1, $1 } END { print "END;" }' "$high_hex" > "$high_mif"
  rm "$low_hex" "$high_hex"
  mv "$low_mif" "$low"
  mv "$high_mif" "$high"
  mv "$temporary" "$generated"
  print "Prepared Apple /// ROM banks from $rom ($bytes bytes)"
}

prepare_build_id() {
  print -r -- "\`define BUILD_DATE \"$(date +%y%m%d)\"" > build_id.v
}

case "$MODE" in
  clean)
    rm -rf db incremental_db output_files *.qws *.rpt *.summary *.smsg *.done *.jdi *.pin *.sld c5_pin_model_dump.txt build_*.log
    ;;
  map)
    prepare_rom
    prepare_build_id
    run_q quartus_map.exe --read_settings_files=on --write_settings_files=off $PROJ -c $PROJ 2>&1 | tee "$LOG" >/dev/null
    rc=$pipestatus[1]
    grep -E "Error|Warning \(1[0-9]{4}\).*(undeclared|not declared|undefined|mismatch)|successful|Info \(144001\)" "$LOG" || true
    grep -E "Error \(|Error:" "$LOG" | head -40 || true
    (( rc == 0 )) || exit $rc
    ;;
  compile)
    prepare_rom
    prepare_build_id
    run_q quartus_sh.exe --flow compile $PROJ 2>&1 | tee "$LOG" >/dev/null
    rc=$pipestatus[1]
    grep -E "^Error|Critical Warning|Full Compilation|successful|Fmax|Timing Analyzer:.*(slack|violat)" "$LOG" || true
    grep -E "^Error" "$LOG" | head -40 || true
    ls -la output_files/$PROJ.rbf 2>/dev/null || true
    (( rc == 0 )) || exit $rc
	if grep -q "Timing requirements not met" "$LOG"; then
		print -u2 "Quartus generated an RBF, but timing requirements were not met."
		exit 2
	fi
    ;;
  *)
    echo "unknown mode $MODE"; exit 1;;
esac
