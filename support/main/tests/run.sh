#!/usr/bin/env bash
# Host tests for the companion Main's Apple III storage code. Builds the real
# support/apple3 and support/a2 sources from a Main checkout (MAIN_DIR, default
# ../Main_MiSTer-AppleIII next to this repository) with file and SPI shims.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
main=${MAIN_DIR:-$here/../../../../Main_MiSTer-AppleIII}
out=${APPLE3_TEST_OUT:-/tmp/mister-apple3-tests}
mkdir -p "$out"
${CXX:-c++} -std=c++14 -O1 -g -Wall -Wextra -fsanitize=address,undefined \
  -include "$here/compat.h" -I"$main" "$here/storage_test.cpp" \
  "$main"/support/a2/iigs_disk.cpp "$main"/support/a2/iigs_fmt.cpp \
  "$main"/support/apple3/apple3_disk.cpp "$main"/support/apple3/apple3_woz.cpp \
  -o "$out/storage_test"
"$out/storage_test" "$@"
