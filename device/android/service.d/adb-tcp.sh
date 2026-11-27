#!/system/bin/sh
# Keeps adb reachable over Wi-Fi on port 5555 after every boot (only already-authorized keys can connect).
until [ "$(getprop sys.boot_completed)" = 1 ]; do sleep 2; done
setprop service.adb.tcp.port 5555
stop adbd
start adbd
