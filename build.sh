#!/bin/zsh
# Build the Apple-III MiSTer core with Quartus Prime 17.0 running under
# CrossOver on macOS.  On Windows or Linux open Apple-III.qpf in Quartus instead.
# Usage: ./build.sh [map|compile|clean]   (default: compile)
#   map     - synthesis only (fast syntax/elaboration check)
#   compile - full flow (map, fit, asm, sta) -> output_files/Apple-III.rbf
set -e
cd "$(dirname "$0")"
CX=${CROSSOVER_BIN:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin}
BOTTLE=${QUARTUS_BOTTLE:-Quartus}
QBIN="C:/intelFPGA_lite/17.0/quartus/bin64"
PROJ=Apple-III
MODE=${1:-compile}
LOG=build_${MODE}.log
run_q() { "$CX/wine" --bottle "$BOTTLE" --workdir "$PWD" --cx-app "$QBIN/$1" "${@:2}"; }

# quartus_map alone does not run the framework's pre-flow script, so the
# build date module is written here as well.
prepare_build_id() {
  print -r -- "\`define BUILD_DATE \"$(date +%y%m%d)\"" > build_id.v
}

case "$MODE" in
  clean)
    rm -rf db incremental_db output_files *.qws *.rpt *.summary *.smsg *.done *.jdi *.pin *.sld c5_pin_model_dump.txt build_*.log
    ;;
  map)
    prepare_build_id
    run_q quartus_map.exe --read_settings_files=on --write_settings_files=off $PROJ -c $PROJ 2>&1 | tee "$LOG" >/dev/null
    rc=$pipestatus[1]
    grep -E "Error|Warning \(1[0-9]{4}\).*(undeclared|not declared|undefined|mismatch)|successful|Info \(144001\)" "$LOG" || true
    grep -E "Error \(|Error:" "$LOG" | head -40 || true
    (( rc == 0 )) || exit $rc
    ;;
  compile)
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
