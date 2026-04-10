#!/usr/bin/env bash
#  ▄████  ██▀███   ▒█████   ▒█████  ▄▄▄█████▓
# ██▒ ▀█▒▓██ ▒ ██▒▒██▒  ██▒▒██▒  ██▒▓  ██▒ ▓▒
#▒██░▄▄▄░▓██ ░▄█ ▒▒██░  ██▒▒██░  ██▒▒ ▓██░ ▒░
#░▓█  ██▓▒██▀▀█▄  ▒██   ██░▒██   ██░░ ▓██▓ ░
#░▒▓███▀▒░██▓ ▒██▒░ ████▓▒░░ ████▓▒░  ▒██▒ ░
# ░▒   ▒ ░ ▒▓ ░▒▓░░ ▒░▒░▒░ ░ ▒░▒░▒░   ▒ ░░
#  ░   ░   ░▒ ░ ▒░  ░ ▒ ▒░   ░ ▒ ▒░     ░
#░ ░   ░   ░░   ░ ░ ░ ░ ▒  ░ ░ ░ ▒    ░
#      ░    ░         ░ ░      ░ ░
# Script: charge-rate.sh
# Purpose: Battery charge rate monitor
# Dependencies: upower, awk
# Author: groot
# Modified: 2026-01-24

set -euo pipefail
interval=0
count=1
json=0

usage(){ cat <<EOF
Usage: $(basename "$0") [-i interval_seconds] [-c count] [-j]
  -i interval   Repeat every N seconds (implies continuous until count reached)
  -c count      Number of samples (default 1; use 0 for infinite when -i given)
  -j            Output JSON lines (one object per sample)
Examples:
  $0            Single snapshot
  $0 -i 5 -c 0  Stream every 5s
  $0 -i 2 -c 10 Sample 10 times
  $0 -j         JSON output
EOF
}

while getopts "i:c:jh" opt; do
  case $opt in
    i) interval=$OPTARG ;;
    c) count=$OPTARG ;;
    j) json=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
  esac
done

sample(){
  local timestamp battery dev bat_path bat status volt_uA curr_uA pow_uW energy_now_uWh energy_full_uWh capacity perc state upower_rateW upower_time
  timestamp=$(date -Iseconds)
  bat_path=$(ls /sys/class/power_supply/ | grep -m1 '^BAT') || true
  if [[ -n $bat_path ]]; then
    bat="/sys/class/power_supply/$bat_path"
    status=$(<"$bat/status")
    volt_uA=$(cat "$bat/voltage_now" 2>/dev/null || echo 0)
    curr_uA=$(cat "$bat/current_now" 2>/dev/null || echo 0)
    pow_uW=$(cat "$bat/power_now" 2>/dev/null || echo 0)
    energy_now_uWh=$(cat "$bat/energy_now" 2>/dev/null || echo 0)
    energy_full_uWh=$(cat "$bat/energy_full" 2>/dev/null || echo 0)
    capacity=$(cat "$bat/capacity" 2>/dev/null || echo 0)
  fi
  # Derive values
  local V A W W_calc Wh_now Wh_full pct
  V=$(awk -v v=$volt_uA 'BEGIN{printf "%.3f", v/1000000}')
  A=$(awk -v i=$curr_uA 'BEGIN{printf "%.3f", i/1000000}')
  Wh_now=$(awk -v e=$energy_now_uWh 'BEGIN{printf "%.2f", e/1000000}')
  Wh_full=$(awk -v e=$energy_full_uWh 'BEGIN{printf "%.2f", e/1000000}')
  pct=$capacity
  if [[ $pow_uW -gt 0 ]]; then
    W=$(awk -v p=$pow_uW 'BEGIN{printf "%.2f", p/1000000}')
  else
    # Compute W from V*A if current_now available
    W=$(awk -v v=$volt_uA -v i=$curr_uA 'BEGIN{printf "%.2f", (v*i)/1e12}')
  fi
  W_calc=$W

  # upower (may provide time to full and instantaneous rate)
  local up_dev=$(upower -e 2>/dev/null | grep -m1 BAT || true)
  if [[ -n $up_dev ]]; then
    local up_info=$(upower -i "$up_dev" 2>/dev/null || true)
    state=$(echo "$up_info" | awk -F: '/state/ {gsub(/^[ \t]+/,"",$2);print $2}' )
    upower_rateW=$(echo "$up_info" | awk -F: '/energy-rate/ {gsub(/^[ \t]+/,"",$2);print $2}' | awk '{print $1}')
    upower_time=$(echo "$up_info" | awk -F: '/time to/ {gsub(/^[ \t]+/,"",$2);print $2}')
  fi

  # Enumerate power sources (USB/AC)
  declare -A sources
  for dev in /sys/class/power_supply/*; do
    local name=$(basename "$dev")
    [[ $name == BAT* ]] && continue
    local type=$(cat "$dev/type" 2>/dev/null || echo "?")
    local online=$(cat "$dev/online" 2>/dev/null || echo "")
    local v=$(cat "$dev/voltage_now" 2>/dev/null || echo 0)
    local c=$(cat "$dev/current_now" 2>/dev/null || echo 0)
    local p=$(cat "$dev/power_now" 2>/dev/null || echo 0)
    local Vsrc=$(awk -v vv=$v 'BEGIN{printf "%.2f", vv/1000000}')
    local Asrc=$(awk -v cc=$c 'BEGIN{printf "%.3f", cc/1000000}')
    local Wsrc
    if [[ $p -gt 0 ]]; then
      Wsrc=$(awk -v pp=$p 'BEGIN{printf "%.2f", pp/1000000}')
    else
      Wsrc=$(awk -v vv=$v -v cc=$c 'BEGIN{printf "%.2f", (vv*cc)/1e12}')
    fi
    sources[$name]="$type online=$online V=$Vsrc A=$Asrc W=$Wsrc"
  done

  if (( json )); then
    printf '{"timestamp":"%s","status":"%s","state":"%s","voltage_V":%s,"current_A":%s,"power_W":%s,"energy_now_Wh":%s,"energy_full_Wh":%s,"capacity_pct":%s,"upower_rate_W":"%s","upower_time":"%s","sources":{' "$timestamp" "$status" "$state" "$V" "$A" "$W_calc" "$Wh_now" "$Wh_full" "$pct" "$upower_rateW" "$upower_time"
    local first=1
    for k in "${!sources[@]}"; do
      ((first)) || printf ','
      printf '"%s":"%s"' "$k" "${sources[$k]}"
      first=0
    done
    printf '}}\n'
  else
    echo "Timestamp: $timestamp"
    echo "Battery status: $status (upower state: $state)"
    echo "Percent: $pct%  Energy: $Wh_now Wh / $Wh_full Wh"
    echo "Voltage: $V V  Current: $A A  Power: $W_calc W (upower: ${upower_rateW:-?} W)"
    [[ -n $upower_time ]] && echo "Time remaining: $upower_time"
    echo "Sources:"; for k in "${!sources[@]}"; do echo "  $k -> ${sources[$k]}"; done | sort
    echo "---"
  fi
}

# If count=0 and interval>0 => infinite loop
samples_done=0
while :; do
  sample
  (( samples_done++ ))
  if [[ $count -ne 0 && $samples_done -ge $count ]]; then
    break
  fi
  if [[ $interval -le 0 ]]; then
    break
  fi
  sleep "$interval"
done

exit 0
