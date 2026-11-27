#!/usr/bin/env bash
# Patches a boot image with Magisk on the phone, flashes it to boot_a and waits for Android.
#
#   tools/flash-boot.sh <boot.img>   # e.g. out/docker/boot-docker.img
#
# Needs the phone booted with adb, and Magisk's boot_patch.sh plus its arm64 binaries in
# /data/local/tmp/mp (unpacked from the Magisk APK: assets/boot_patch.sh, util_functions.sh,
# lib/arm64-v8a/lib{magiskinit,magisk,magiskboot,init-ld,busybox}.so without "lib"/".so").
# Uses fastboot from platform-tools r33 (FASTBOOT): newer fastboot hangs on this
# bootloader trying to fetch "super". If the kernel does not boot, see tools/rescue.sh.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
image=$(realpath "${1:?usage: flash-boot.sh <boot.img>}")
patched=${image%.img}-magisk.img
adb=${ADB:-adb}
fastboot=${FASTBOOT:-$root/out/pt33/platform-tools/fastboot.exe}
export MSYS_NO_PATHCONV=1

"$adb" push -q "$(cygpath -w "$image")" /data/local/tmp/mp/boot.img
"$adb" shell 'cd /data/local/tmp/mp && rm -f new-boot.img && ./busybox sh boot_patch.sh boot.img >/dev/null 2>&1 && test -s new-boot.img'
"$adb" pull -q /data/local/tmp/mp/new-boot.img "$(cygpath -w "$patched")"

"$adb" reboot bootloader
until "$fastboot" devices | grep -q fastboot; do sleep 2; done
"$fastboot" flash boot_a "$(cygpath -w "$patched")"
"$fastboot" reboot

"$adb" wait-for-device
"$adb" shell 'until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done; uname -r'
