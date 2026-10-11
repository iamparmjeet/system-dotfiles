#!/bin/bash
# Patch for omarchy-brightness-display: adds DDC/CI support for external monitors
# 
# After an `omarchy update` overwrites ~/.local/share/omarchy/bin/omarchy-brightness-display,
# re-run this patch:   bash ~/Scripts/omarchy-brightness-display.ddc-patch.sh
#
# Or just replace the whole file manually with the content below.

target="/home/parm/.local/share/omarchy/bin/omarchy-brightness-display"

if [[ ! -f "$target" ]]; then
  echo "Target not found: $target"
  echo "Update the path at the top of this script and re-run."
  exit 1
fi

cat > "$target" << 'OMARCHY_BRIGHTNESS_DISPLAY'
#!/bin/bash

# omarchy:summary=Show or adjust brightness on the most likely display device.
# omarchy:args=[--no-osd] [+N%|N%-|N%|off|on]
# omarchy:examples=omarchy brightness display | omarchy brightness display +5% | omarchy brightness display --no-osd 50% | omarchy brightness display off | omarchy brightness display on

no_osd=0
args=()

for arg in "$@"; do
  if [[ $arg == "--no-osd" ]]; then
    no_osd=1
  else
    args+=("$arg")
  fi
done

set -- "${args[@]}"

# -- Helpers --

# Check whether the focused monitor is an external (non-internal) display.
# External monitors have no kernel backlight device -- they need DDC/CI.
is_external_focused() {
  local name
  name=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true).name') || return 1
  [[ -n $name ]] && ! echo "$name" | grep -qE '^(eDP|LVDS|DSI)-'
}

# Read brightness via ddcutil (0-100)
display_brightness_ddc() {
  ddcutil getvcp 10 2>/dev/null | grep -oP 'current value =\s*\K\d+'
}

# Read brightness via brightnessctl (percent)
display_brightness_ctl() {
  brightnessctl -d "$1" -m 2>/dev/null | awk -F, '{ gsub("%", "", $4); print $4; found=1 } END{ exit !found }'
}

# Apply adaptive step sizes shared by both backends
apply_step() {
  local step="$1" current="$2" target
  if [[ $step == "+5%" ]]; then
    (( current < 5 )) && (( target = current + 1 )) || (( target = current + 5 ))
    (( target > 100 )) && target=100
    echo "$target"
  elif [[ $step == "5%-" ]]; then
    (( current <= 5 )) && (( target = current - 1 )) || (( target = current - 5 ))
    (( target < 1 )) && target=1
    echo "$target"
  else
    echo "${step%\%}"
  fi
}

# -- Read-only (no args) --

if (( $# == 0 )); then
  if is_external_focused; then
    val=$(display_brightness_ddc)
    [[ -n $val ]] && echo "$val" && exit
  fi

  if omarchy-hyprland-monitor-focused-apple; then
    omarchy-brightness-display-apple
    exit
  fi

  device="$(omarchy-hw-display)" || exit 1
  display_brightness_ctl "$device"
  exit
fi

step="$1"

# -- DPMS shortcuts --

if [[ $step == "off" ]]; then
  hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })' >/dev/null 2>&1
  exit 0
elif [[ $step == "on" ]]; then
  hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' >/dev/null 2>&1
  exit 0
fi

exec {lock_fd}>"${XDG_RUNTIME_DIR:-/tmp}/omarchy-brightness-display.lock"
flock -n "$lock_fd" || exit 0

# -- DDC/CI path (external monitors) --

if is_external_focused; then
  ddc_opts=(--disable-dynamic-sleep --sleep-multiplier 0 --noverify)

  if [[ $step == "+5%" || $step == "5%-" ]]; then
    current=$(display_brightness_ddc)
    if [[ -n $current ]]; then
      target=$(apply_step "$step" "$current")
      ddcutil setvcp "${ddc_opts[@]}" 10 "$target" >/dev/null 2>&1
      (( no_osd )) || omarchy-osd -i brightness -p "$target"
      exit
    fi
  else
    target="${step%\%}"
    ddcutil setvcp "${ddc_opts[@]}" 10 "$target" >/dev/null 2>&1
    if (( $? == 0 )); then
      (( no_osd )) || omarchy-osd -i brightness -p "$target"
      exit
    fi
    exit 1
  fi
fi

# -- Apple display path --

if omarchy-hyprland-monitor-focused-apple; then
  if (( no_osd )); then
    omarchy-brightness-display-apple --no-osd "$step"
  else
    omarchy-brightness-display-apple "$step"
  fi
  exit
fi

# -- brightnessctl path (internal / laptop backlight) --

device="$(omarchy-hw-display)" || exit 1
current=$(display_brightness_ctl "$device") || exit 1

target=$(apply_step "$step" "$current")
brightnessctl -d "$device" set "${target}%" >/dev/null

(( no_osd )) || omarchy-osd -i brightness -p "$(display_brightness_ctl "$device")"
OMARCHY_BRIGHTNESS_DISPLAY

chmod +x "$target"
echo "Patched: $target"
echo "Run: omarchy restart shell   (to pick up the change if needed)"
