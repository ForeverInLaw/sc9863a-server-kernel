#!/usr/bin/env bash
# Trims rooted Android down to a hardware layer for the container and installs the
# boot scripts from device/android/service.d into Magisk's /data/adb/service.d.
#
#   tools/setup-android.sh   # over USB or Wi-Fi adb (pick the device with ANDROID_SERIAL)
#
# Disables every package in device/android/debloat.list and wipes its data and
# updates (undo one with `pm enable <pkg>`), turns off the modem and Bluetooth but keeps
# Wi-Fi, and lets the screen sleep. Takes effect fully after a reboot.
#
# If a disabled package crashes system_server, Android's RescueParty lands in recovery
# ("Can't load Android system"). Never pick Factory data reset: choose Try again with
# USB plugged in and run `pm enable <pkg>` over adb while the framework is briefly up
# (the crash is in `adb logcat -b crash`). RescueParty also resets global settings, so
# rerun this script, and Magisk's safe mode disables modules: remove
# /data/adb/modules/*/disable to bring Droidspaces back.
set -euo pipefail

src=$(cd "$(dirname "$0")/../device/android" && pwd)
adb=${ADB:-adb}
export MSYS_NO_PATHCONV=1

"$adb" shell 'rm -rf /data/local/tmp/android && mkdir -p /data/local/tmp/android'
"$adb" push -q "$(cygpath -w "$src")/." /data/local/tmp/android/
"$adb" shell 'su -c "cp /data/local/tmp/android/service.d/*.sh /data/adb/service.d/ &&
  chmod 755 /data/adb/service.d/*.sh" && rm -rf /data/local/tmp/android'

grep -v -e '^#' -e '^$' "$src/debloat.list" | tr -d '\r' | while read -r pkg; do
  # As root: the shell user may not disable a few protected packages (NFC). Updates
  # installed over a system app and app data are dropped to free storage.
  "$adb" shell "su -c 'pm disable-user --user 0 $pkg' >/dev/null 2>&1 || echo 'not disabled: $pkg'
    su -c 'pm uninstall-system-updates $pkg; pm clear $pkg' >/dev/null 2>&1" </dev/null
done

# Airplane mode without Wi-Fi in its radio list: modem, Bluetooth and NFC go off. Wi-Fi
# is switched back on anyway, since turning airplane mode on sometimes still drops it;
# Android then remembers to keep Wi-Fi on in airplane mode across reboots.
"$adb" shell 'settings put global airplane_mode_radios cell,bluetooth,nfc,wimax &&
  cmd connectivity airplane-mode enable && cmd wifi set-wifi-enabled enabled &&
  settings put global stay_on_while_plugged_in 0'
