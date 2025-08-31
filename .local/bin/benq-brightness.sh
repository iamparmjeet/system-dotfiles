#!/usr/bin/env bash
# Clean BenQ brightness control (VCP 0x10)
# - Prints number only when brightness changes (up/down/set)
# - Silent for "show"
# - Default bus: 1 (override with MON_BUS env)
# - Step size: 5% (override with STEP env)

set -euo pipefail

BUS="${MON_BUS:-1}"
STEP="${STEP:-5}"
ACTION="${1:-show}"
VALUE="${2:-}"

DDC=(/usr/bin/timeout 0.6s /usr/bin/ddcutil --sleep-multiplier=0.2 --bus="$BUS")

get_cur_max() {
  # Grab last two integers as cur and max. Works across ddcutil formats.
  local out
  out="$("${DDC[@]}" -t getvcp 10 2>/dev/null || true)"
  [[ -n "$out" ]] || return 1
  # shellcheck disable=SC2207
  local nums=($(printf '%s' "$out" | grep -oE '[0-9]+' || true))
  local n=${#nums[@]}
  ((n >= 2)) || return 1
  printf '%s %s\n' "${nums[n - 2]}" "${nums[n - 1]}"
}

percent() {
  local cur="$1" max="$2"
  printf '%d\n' $(((cur * 100 + max / 2) / max))
}

clamp() {
  local v="$1" lo="$2" hi="$3"
  ((v < lo)) && v="$lo"
  ((v > hi)) && v="$hi"
  echo "$v"
}

main() {
  local cur max tgt new

  case "$ACTION" in
  show)
    # Intentionally silent
    exit 0
    ;;
  up | down | set)
    read -r cur max < <(get_cur_max)
    case "$ACTION" in
    up) tgt=$((cur + (STEP * max) / 100)) ;;
    down) tgt=$((cur - (STEP * max) / 100)) ;;
    set)
      : "${VALUE:?Provide percent 0-100}"
      tgt=$(((VALUE * max + 50) / 100))
      ;;
    esac
    new="$(clamp "$tgt" 0 "$max")"
    "${DDC[@]}" setvcp 10 "$new" --noverify >/dev/null
    # Print number only when brightness changes
    percent "$new" "$max"
    ;;
  *)
    echo "Usage: benq-brightness.sh {show|up|down|set 0-100}" >&2
    exit 2
    ;;
  esac
}

main "$@"
