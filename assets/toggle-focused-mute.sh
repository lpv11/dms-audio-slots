#!/usr/bin/env bash
set -euo pipefail

require_cmds=(pactl awk)
for cmd in "${require_cmds[@]}"; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "$cmd not found" >&2
    exit 1
  }
done

notify_message() {
  local summary="$1"
  local body="$2"
  if [[ "$notification_mode" == "hypr" ]]; then
    if command -v hyprctl >/dev/null 2>&1; then
      hyprctl notify 0 2000 "rgb(89,146,255)" "${summary}: ${body}" >/dev/null 2>&1 || true
    fi
    return
  fi
  if [[ "$notification_mode" == "desktop" ]]; then
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "$summary" "$body" >/dev/null 2>&1 || true
    fi
    return
  fi
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$summary" "$body" >/dev/null 2>&1 || true
    return
  fi
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl notify 0 2000 "rgb(89,146,255)" "${summary}: ${body}" >/dev/null 2>&1 || true
  fi
}

notify_error() {
  local msg="$1"
  if [[ "$notification_mode" == "hypr" ]]; then
    if command -v hyprctl >/dev/null 2>&1; then
      hyprctl notify 1 2000 "rgb(255,120,120)" "$msg" >/dev/null 2>&1 || true
    fi
    return
  fi
  if [[ "$notification_mode" == "desktop" ]]; then
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "Audio App Mute" "$msg" >/dev/null 2>&1 || true
    fi
    return
  fi
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Audio App Mute" "$msg" >/dev/null 2>&1 || true
    return
  fi
  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl notify 1 2000 "rgb(255,120,120)" "$msg" >/dev/null 2>&1 || true
  fi
}

declare -A target_pid_map

get_sink_inputs() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 2s pactl list sink-inputs 2>/dev/null || true
  else
    pactl list sink-inputs 2>/dev/null || true
  fi
}

get_mute_state() {
  local inputs="$1"
  local target_id="$2"
  awk -v target_id="$target_id" '
    /^Sink Input #/ { inblk = ($3 == ("#" target_id) || $3 == target_id); next }
    inblk && /^[[:space:]]*Mute:/ { print $2; exit }
  ' <<<"$inputs"
}

app_id="${1:-}"
title="${2:-}"
app_name="${3:-}"
focused_pid="${4:-}"
notification_mode="${5:-auto}"
title_base="${title%% - *}"
title_base="${title_base%% | *}"

if [[ -z "$focused_pid" ]]; then
  if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    focused_pid="$(hyprctl -j activewindow 2>/dev/null | jq -r '.pid // empty' 2>/dev/null || true)"
  elif command -v swaymsg >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    focused_pid="$(swaymsg -t get_tree 2>/dev/null | jq -r '.. | select(.focused? == true) | .pid // empty' 2>/dev/null | head -n1 || true)"
  fi
fi

if [[ -z "$app_id" && -z "$title" && -z "$app_name" && -z "$focused_pid" ]]; then
  notify_error "No focused app metadata available"
  exit 1
fi

declare -A override_match
override_match["melonds"]="melonds"

class_lc="$(printf '%s' "$app_id" | tr '[:upper:]' '[:lower:]')"
match_class="$app_id"
if [[ -n "${override_match[$class_lc]:-}" ]]; then
  match_class="${override_match[$class_lc]}"
fi

add_pid() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  target_pid_map["$pid"]=1
}

add_pid_tree() {
  local root_pid="$1"
  local child=""
  add_pid "$root_pid"
  while IFS= read -r child; do
    [[ -n "$child" ]] || continue
    add_pid "$child"
    add_pid_tree "$child"
  done < <(pgrep -P "$root_pid" 2>/dev/null || true)
}

if [[ -n "$focused_pid" ]]; then
  add_pid_tree "$focused_pid"
fi

if [[ "$app_id" =~ ^steam_app_([0-9]+)$ ]]; then
  steam_id="${BASH_REMATCH[1]}"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    add_pid_tree "$pid"
  done < <(pgrep -f "steam_app_${steam_id}|AppId=${steam_id}|/${steam_id}/" 2>/dev/null || true)
fi

target_pids_csv=""
for pid in "${!target_pid_map[@]}"; do
  if [[ -z "$target_pids_csv" ]]; then
    target_pids_csv="$pid"
  else
    target_pids_csv="${target_pids_csv},${pid}"
  fi
done

sink_inputs="$(get_sink_inputs)"

awk_matcher='
  BEGIN {
    split(target_pids, pid_arr, ",")
    for (i in pid_arr) {
      if (pid_arr[i] != "")
        pid_map[pid_arr[i]] = 1
    }
    target1_lc = tolower(target_name1)
    target2_lc = tolower(target_name2)
    target3_lc = tolower(target_name3)
    target4_lc = tolower(target_name4)
  }
  function match_field(field_lc, target_lc) {
    if (field_lc == "" || target_lc == "") return 0
    return (index(field_lc, target_lc) > 0 || index(target_lc, field_lc) > 0)
  }
  function any_match(target_lc) {
    if (target_lc == "") return 0
    if (match_field(name_lc, target_lc)) return 1
    if (match_field(binary_lc, target_lc)) return 1
    if (match_field(media_lc, target_lc)) return 1
    return 0
  }
  function flush() {
    if (id == "") return
    name_lc = tolower(name)
    binary_lc = tolower(binary)
    media_lc = tolower(media)
    if (pid != "" && pid_map[pid]) {
      print id
      next
    }
    if (any_match(target1_lc) || any_match(target2_lc) || any_match(target3_lc) || any_match(target4_lc)) {
      print id
      next
    }
    id = ""; pid = ""; name = ""
    binary = ""; media = ""
  }
  /^Sink Input #/ {
    flush()
    id = $3
    sub(/^#/, "", id)
    next
  }
  /application.name/ {
    if (match($0, /"([^"]+)"/, m)) name = m[1]
    next
  }
  /application.process.id/ {
    if (match($0, /"([0-9]+)"/, m)) pid = m[1]
    next
  }
  /application.process.binary/ {
    if (match($0, /"([^"]+)"/, m)) binary = m[1]
    next
  }
  /media.name/ {
    if (match($0, /"([^"]+)"/, m)) media = m[1]
    next
  }
  /^$/ { flush() }
  END { flush() }
'

mapfile -t sink_ids < <(
  awk -v target_pids="$target_pids_csv" -v target_name1="$match_class" -v target_name2="$app_name" -v target_name3="$title" -v target_name4="$title_base" \
    "$awk_matcher" <<<"$sink_inputs"
)

if [[ ${#sink_ids[@]} -eq 0 ]]; then
  notify_error "No sink input for focused app"
  exit 1
fi

want_mute=""
for id in "${sink_ids[@]}"; do
  cur="$(get_mute_state "$sink_inputs" "$id")"
  if [[ "$cur" == "no" ]]; then
    want_mute="yes"
    break
  elif [[ -z "$want_mute" && "$cur" == "yes" ]]; then
    want_mute="no"
  fi
done

set_mute_all() {
  local mode="$1"
  local arg
  case "$mode" in
    yes) arg=1 ;;
    no) arg=0 ;;
    *) arg=toggle ;;
  esac

  for id in "${sink_ids[@]}"; do
    pactl set-sink-input-mute "$id" "$arg"
  done
}

case "$want_mute" in
  yes) set_mute_all yes ;;
  no) set_mute_all no ;;
  *) set_mute_all toggle ;;
esac

sink_inputs_after="$(get_sink_inputs)"
muted_count=0
unmuted_count=0

for id in "${sink_ids[@]}"; do
  state="$(get_mute_state "$sink_inputs_after" "$id")"
  case "$state" in
    yes) muted_count=$((muted_count + 1)) ;;
    no) unmuted_count=$((unmuted_count + 1)) ;;
  esac
done

state_msg="Unknown"
if [[ $muted_count -gt 0 && $unmuted_count -eq 0 ]]; then
  state_msg="Muted"
elif [[ $unmuted_count -gt 0 && $muted_count -eq 0 ]]; then
  state_msg="Unmuted"
elif [[ $muted_count -gt 0 && $unmuted_count -gt 0 ]]; then
  state_msg="Mixed"
fi

if [[ -n "$app_name" ]]; then
  notify_message "Audio App Mute" "${state_msg} - ${app_name}"
elif [[ -n "$app_id" ]]; then
  notify_message "Audio App Mute" "${state_msg} - ${app_id}"
else
  notify_message "Audio App Mute" "$state_msg"
fi
