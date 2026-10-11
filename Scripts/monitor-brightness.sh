#!/bin/bash
# Standalone external monitor brightness control via DDC/CI
# Works on any Linux system with ddcutil installed.
# Internal/laptop displays use brightnessctl; external use ddcutil.
#
# Usage:
#   monitor-brightness.sh           # read current brightness
#   monitor-brightness.sh 50        # set to 50%
#   monitor-brightness.sh +5        # increase by 5
#   monitor-brightness.sh 5-        # decrease by 5
#
# Depends: ddcutil, brightnessctl, hyprctl (optional — falls back to
#          ddcutil detect if hyprctl isn't available)

set -euo pipefail

ddc_opts=(--disable-dynamic-sleep --sleep-multiplier 0 --noverify)

# ---- Detect the external monitor via DDC ----
find_external_ddc() {
  ddcutil detect --brief 2>/dev/null | grep -B1 -A1 'Invalid display' | head -1 | grep -oP 'Display \d+' | grep -oP '\d+'
}

# ---- Read brightness ----
read_brightness() {
  local display="${1:-}"
  if [[ -n $display ]]; then
    ddcutil "${ddc_opts[@]}" getvcp 10 2>/dev/null | grep -oP 'current value =\s*\K\d+'
  else
    # Try ddcutil first, fall back to brightnessctl
    local disp
    disp=$(find_external_ddc)
    if [[ -n $disp ]]; then
      ddcutil "${ddc_opts[@]}" getvcp 10 2>/dev/null | grep -oP 'current value =\s*\K\d+'
    elif command -v brightnessctl &>/dev/null; then
      local dev
      dev=$(ls -1 /sys/class/backlight 2>/dev/null | head -1)
      [[ -n $dev ]] && brightnessctl -d "$dev" -m 2>/dev/null | awk -F, '{gsub("%","",$4); print $4}'
    fi
  fi
}

# ---- Set brightness ----
set_brightness() {
  local target="$1"
  local display="${2:-}"
  if [[ -n $display ]]; then
    ddcutil "${ddc_opts[@]}" setvcp 10 "$target" >/dev/null 2>&1
  else
    local disp
    disp=$(find_external_ddc)
    if [[ -n $disp ]]; then
      ddcutil "${ddc_opts[@]}" setvcp 10 "$target" >/dev/null 2>&1
    elif command -v brightnessctl &>/dev/null; then
      local dev
      dev=$(ls -1 /sys/class/backlight 2>/dev/null | head -1)
      [[ -n $dev ]] && brightnessctl -d "$dev" set "${target}%" >/dev/null
    fi
  fi
}

# ---- Main ----
if (( $# == 0 )); then
  read_brightness
  exit
fi

arg="$1"

if [[ $arg == +* ]]; then
  # Increase (e.g. +5)
  step="${arg#+}"
  current=$(read_brightness) || current=50
  target=$(( current + step ))
  (( target > 100 )) && target=100
elif [[ $arg == *- ]]; then
  # Decrease (e.g. 5-)
  step="${arg%-}"
  current=$(read_brightness) || current=50
  target=$(( current - step ))
  (( target < 1 )) && target=1
else
  # Absolute value
  target="${arg%\%}"   # strip optional %
fi

set_brightness "$target"
echo "$target"
