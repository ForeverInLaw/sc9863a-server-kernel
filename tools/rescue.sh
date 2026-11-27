#!/usr/bin/env bash
# Restores boot_a when a kernel does not boot. The phone has no key combo for fastboot
# and recovery uses the same boot_a kernel, so this goes through the boot ROM's download
# mode. Start this first, then: phone off, hold Volume-Down, plug USB (it waits ~10 s).
#
#   tools/rescue.sh [boot image]   # default: out/magisk/boot-magisk.img (stock + Magisk)
#
# Afterwards tools/crashlog.sh shows why the kernel died. The loaders cannot read RAM
# (read_mem is unsupported under FDL1 and FDL2), so the log comes from the minidump the
# bootloader saves instead. The session always ends with reset: killing spd_dump
# mid-session leaves the phone stuck in the loader until the battery drains.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tools=${SPD_DIR:-$root/tools/unlock/itel_vision3}
image=$(realpath "${1:-$root/out/magisk/boot-magisk.img}")

# spd_dump needs Channel9.dll / Channel.ini from its own directory.
cd "$tools"
MSYS_NO_PATHCONV=1 ./spd_dump.exe --wait "${WAIT:-600}" \
  exec_addr 0x4ee8 \
  fdl "$(cygpath -w "$tools/fdl1-dl.bin")" 0x5000 \
  fdl "$(cygpath -w "$tools/fdl2-dl.bin")" 0x9efffe00 exec \
  w boot_a "$(cygpath -w "$image")" \
  reset 2>&1 | grep -vE '^CurTime' | tail -8
