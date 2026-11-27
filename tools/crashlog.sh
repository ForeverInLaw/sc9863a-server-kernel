#!/usr/bin/env bash
# Shows why the last kernel panic happened, from a phone booted back into rooted Android.
#
#   tools/crashlog.sh
#
# On a panic the Unisoc bootloader saves a minidump to the sysdumpdb partition: the
# kernel banner, the exception type and the backtrace stay readable, the dmesg part is
# compressed. Raw copies go to out/crashlog/.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
dest=$root/out/crashlog
mkdir -p "$dest"

for part in sysdumpdb uboot_log; do
  MSYS_NO_PATHCONV=1 adb exec-out "su -c 'cat /dev/block/by-name/$part'" > "$dest/$part.bin"
done

strings -n 8 "$dest/sysdumpdb.bin" | awk '
  /^Linux version/ { print; header = 5; next }
  header > 0       { print; header--; next }
  /^\[<.*>\] /     { print }'
