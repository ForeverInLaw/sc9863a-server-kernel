#!/usr/bin/env bash
# Patches a boot image with Magisk on the phone, writes it to boot_a and waits for Android.
#
#   tools/flash-boot.sh <boot.img>   # e.g. out/docker/boot-docker.img
#
# Works over USB or Wi-Fi adb (pick the device with ANDROID_SERIAL). Needs root (Magisk)
# and Magisk's boot_patch.sh plus its arm64 binaries in /data/local/tmp/mp (unpacked from
# the Magisk APK: assets/boot_patch.sh, util_functions.sh,
# lib/arm64-v8a/lib{magiskinit,magisk,magiskboot,init-ld,busybox}.so without "lib"/".so").
# If the new kernel does not boot, see tools/rescue.sh.
set -euo pipefail

image=$(realpath "${1:?usage: flash-boot.sh <boot.img>}")
patched=${image%.img}-magisk.img
adb=${ADB:-adb}
export MSYS_NO_PATHCONV=1

"$adb" push -q "$(cygpath -w "$image")" /data/local/tmp/mp/boot.img
"$adb" shell 'cd /data/local/tmp/mp && rm -f new-boot.img && ./busybox sh boot_patch.sh boot.img >/dev/null 2>&1 && test -s new-boot.img'
"$adb" pull -q /data/local/tmp/mp/new-boot.img "$(cygpath -w "$patched")"

"$adb" shell 'su -c "dd if=/data/local/tmp/mp/new-boot.img of=/dev/block/by-name/boot_a bs=4M conv=fsync && sync"'
"$adb" reboot || true
sleep 20 # let the old system go down before waiting for the new one

# adb over Wi-Fi drops on reboot and does not reconnect by itself.
case ${ANDROID_SERIAL:-} in *:*) until "$adb" connect "$ANDROID_SERIAL" | grep -q 'connected to'; do sleep 5; done ;; esac
"$adb" wait-for-device
"$adb" shell 'until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done; uname -rv'
