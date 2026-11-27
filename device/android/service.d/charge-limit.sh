#!/system/bin/sh
# Keeps the battery between 40 and 80 % on a phone that never leaves the charger.
# Writing stop_charge also sets charger-manager's externally_control, so it does not
# turn charging back on by itself; with charging stopped the phone runs from USB.
ctl=/sys/class/power_supply/battery/charger.0/stop_charge
cap=/sys/class/power_supply/battery/capacity
state=
while :; do
  level=$(cat $cap)
  if [ "$level" -ge 80 ]; then want=1
  elif [ "$level" -le 40 ]; then want=0
  else want=${state:-0}
  fi
  # The write fails while unplugged, so it is retried until it sticks.
  [ "$want" = "$state" ] || { echo $want > $ctl 2>/dev/null && state=$want; }
  sleep 60
done
