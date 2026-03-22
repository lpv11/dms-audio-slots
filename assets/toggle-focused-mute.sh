#!/usr/bin/env bash
set -euo pipefail

# Toggle mute for the sink input(s) that belong to the focused app window (Hyprland).
# Dependencies: hyprctl, pactl, jq, awk

require_cmds=(hyprctl pactl jq awk ps)
for cmd in "${require_cmds[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd not found" >&2
    exit 1
  fi
done

notify() {
  local level="$1"
  local msg="$2"
  hyprctl notify "$level" 2000 "rgb(89,146,255)" "$msg" >/dev/null 2>&1 || true
}

notify_error() {
  local msg="$1"
  hyprctl notify 1 2000 "rgb(255,120,120)" "$msg" >/dev/null 2>&1 || true
}

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
    /^Sink Input #/ {inblk = ($3 == ("#" target_id) || $3 == target_id); next}
    inblk && /^[[:space:]]*Mute:/ {print $2; exit}
  ' <<<"$inputs"
}

get_sink_label() {
  local inputs="$1"
  local target_id="$2"
  awk -v target_id="$target_id" '
    function lc(s) { return tolower(s) }
    function is_generic_label(s, t) {
      t = lc(s)
      if (t == "") return 1
      return (index(t, "steam") > 0 ||
              index(t, "pressure-vessel") > 0 ||
              index(t, "proton") > 0 ||
              index(t, "wine-preloader") > 0 ||
              index(t, "wine_preloader") > 0 ||
              index(t, "wine64-preloader") > 0 ||
              index(t, "wine64_preloader") > 0 ||
              t == "wine" || t == "wine64" ||
              index(t, "wineserver") > 0)
    }
    function emit_best_label() {
      if (binary != "" && !is_generic_label(binary)) { print binary; return }
      if (media != "" && !is_generic_label(media)) { print media; return }
      if (app != "" && !is_generic_label(app)) { print app; return }
      if (media != "") { print media; return }
      if (app != "") { print app; return }
      if (binary != "") { print binary; return }
    }
    /^Sink Input #/ {
      inblk = ($3 == ("#" target_id) || $3 == target_id)
      next
    }
    inblk && /application.process.binary/ {
      if (match($0, /"([^"]+)"/, m)) binary = m[1]
      next
    }
    inblk && /application.name/ {
      if (match($0, /"([^"]+)"/, m)) app = m[1]
      next
    }
    inblk && /media.name/ {
      if (match($0, /"([^"]+)"/, m)) media = m[1]
      next
    }
    inblk && /^$/ {
      emit_best_label()
      exit
    }
    END {
      if (inblk) {
        emit_best_label()
      }
    }
  ' <<<"$inputs"
}

normalize_label() {
  local s="$1"
  # Trim
  s="$(printf '%s' "$s" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

  printf '%s' "$s"
}

active_json=$(hyprctl -j activewindow 2>/dev/null || true)
if [[ -z "${active_json}" || "${active_json}" == "null" ]]; then
  echo "No active window (or hyprctl failed)." >&2
  exit 1
fi

if ! jq -e . >/dev/null 2>&1 <<<"${active_json}"; then
  notify_error "hyprctl did not return JSON (are you in Hyprland?)"
  echo "hyprctl did not return JSON." >&2
  exit 1
fi

pid=$(jq -r '.pid // empty' <<<"${active_json}")
class=$(jq -r '.class // empty' <<<"${active_json}")
initial_class=$(jq -r '.initialClass // empty' <<<"${active_json}")
title=$(jq -r '.title // empty' <<<"${active_json}")

if [[ -z "${pid}" ]]; then
  echo "Could not resolve PID for focused window." >&2
  exit 1
fi

# Optional per-app overrides for matching sink inputs.
# Keys are lowercased Hyprland class names, values are the preferred match string.
declare -A OVERRIDE_MATCH
OVERRIDE_MATCH["melonds"]="melonds"

class_lc=$(printf '%s' "$class" | tr '[:upper:]' '[:lower:]')
match_class="$class"
if [[ -n "${OVERRIDE_MATCH[$class_lc]:-}" ]]; then
  match_class="${OVERRIDE_MATCH[$class_lc]}"
fi

is_steam_like=0
if [[ "$class_lc" == steam || "$class_lc" == steam_app_* ]]; then
  is_steam_like=1
fi

get_pid_csv_with_descendants() {
  local root_pid="$1"
  ps -eo pid=,ppid= 2>/dev/null | awk -v root="$root_pid" '
    {
      pid = $1
      ppid = $2
      exists[pid] = 1
      kids[ppid] = kids[ppid] " " pid
    }
    END {
      if (!exists[root]) {
        print root
        exit
      }
      n = 1
      q[1] = root
      seen[root] = 1
      out = root
      for (i = 1; i <= n; i++) {
        cur = q[i]
        split(kids[cur], arr, " ")
        for (j in arr) {
          c = arr[j]
          if (c == "" || seen[c]) continue
          seen[c] = 1
          n++
          q[n] = c
          out = out "," c
        }
      }
      print out
    }
  '
}

target_pid_csv="$(get_pid_csv_with_descendants "$pid")"
target_name1="$match_class"
target_name2="$initial_class"
target_name3="$title"

# Steam wrapper windows (steam_app_*) often own the focused PID while audio belongs
# to a child game process. Prefer title+descendant PID matching over steam class match.
if [[ "$is_steam_like" -eq 1 ]]; then
  if [[ -n "$title" ]]; then
    target_name1="$title"
    target_name2=""
    target_name3=""
  fi
fi

sink_inputs=$(get_sink_inputs)

# Parse sink-input blocks and score matches.
awk_matcher='
  BEGIN {
    split(target_pid_csv, pid_arr, ",")
    for (i in pid_arr) {
      if (pid_arr[i] != "") pid_set[pid_arr[i]] = 1
    }
    target1_lc = tolower(target_name1)
    target2_lc = tolower(target_name2)
    target3_lc = tolower(target_name3)
    steam_mode = (steam_like == "1")
  }
  function is_pid_match(p) {
    return (p != "" && (p in pid_set))
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
  function is_steamish(field_lc) {
    if (field_lc == "") return 0
    return (index(field_lc, "steam") > 0 || index(field_lc, "proton") > 0 || index(field_lc, "pressure-vessel") > 0)
  }
  function flush() {
    score = 0
    if (id == "") return
    name_lc = tolower(name)
    binary_lc = tolower(binary)
    media_lc = tolower(media)

    if (is_pid_match(pid)) score += 100
    if (any_match(target1_lc)) score += 30
    if (any_match(target2_lc)) score += 20
    if (any_match(target3_lc)) score += 20

    if (steam_mode) {
      if (is_steamish(name_lc) || is_steamish(binary_lc) || is_steamish(media_lc)) score -= 60
      if (target1_lc != "" && any_match(target1_lc)) score += 40
    }

    if (score > 0) {
      print score "|" id
    }
    id=""; pid=""; name=""
    binary=""; media=""
  }
  /^Sink Input #/ {
    flush()
    id=$3
    sub(/^#/, "", id)
    next
  }
  /application.process.id/ {
    if (match($0, /"([0-9]+)"/, m)) pid=m[1]
    next
  }
  /application.name/ {
    if (match($0, /"([^"]+)"/, m)) name=m[1]
    next
  }
  /application.process.binary/ {
    if (match($0, /"([^"]+)"/, m)) binary=m[1]
    next
  }
  /media.name/ {
    if (match($0, /"([^"]+)"/, m)) media=m[1]
    next
  }
  /^$/ { flush() }
  END { flush() }
'

mapfile -t scored_sink_ids < <(
  awk -v target_pid_csv="$target_pid_csv" -v target_name1="$target_name1" -v target_name2="$target_name2" -v target_name3="$target_name3" -v steam_like="$is_steam_like" \
    "$awk_matcher" <<<"$sink_inputs"
)

if [[ ${#scored_sink_ids[@]} -eq 0 ]]; then
  notify_error "No sink input for focused app (class=${class})"
  echo "No sink input found for focused app (pid=${pid}, class=${class})." >&2
  exit 1
fi

max_score=-99999
for row in "${scored_sink_ids[@]}"; do
  score="${row%%|*}"
  if [[ "$score" =~ ^-?[0-9]+$ ]] && (( score > max_score )); then
    max_score="$score"
  fi
done

mapfile -t sink_ids < <(
  for row in "${scored_sink_ids[@]}"; do
    score="${row%%|*}"
    sid="${row#*|}"
    if [[ "$score" == "$max_score" && -n "$sid" ]]; then
      printf '%s\n' "$sid"
    fi
  done | awk "!seen[\$0]++"
)

if [[ ${#sink_ids[@]} -eq 0 ]]; then
  notify_error "No sink input selected for focused app (class=${class})"
  echo "No sink input selected for focused app (pid=${pid}, class=${class})." >&2
  exit 1
fi

state_msg="Unknown"

# Determine desired state from current states:
# if any matched input is unmuted, mute all; otherwise unmute all.
want_mute=""
for id in "${sink_ids[@]}"; do
  cur=$(get_mute_state "$sink_inputs" "$id")
  if [[ "$cur" == "no" ]]; then
    want_mute="yes"
    break
  elif [[ -z "$want_mute" && "$cur" == "yes" ]]; then
    want_mute="no"
  fi
done

set_mute_all() {
  local mode="$1" # yes|no|toggle
  local label="$2"
  local arg
  case "$mode" in
    yes) arg=1 ;;
    no) arg=0 ;;
    toggle) arg=toggle ;;
    *) return 1 ;;
  esac
  for id in "${sink_ids[@]}"; do
    pactl set-sink-input-mute "$id" "$arg"
    echo "${label} sink input #$id" >&2
  done
}

case "$want_mute" in
  yes) set_mute_all yes "Muted" ;;
  no) set_mute_all no "Unmuted" ;;
  *) set_mute_all toggle "Toggled mute for" ;;
esac

# Refresh sink inputs to get accurate post-toggle state.
sink_inputs_after=$(get_sink_inputs)

muted_count=0
unmuted_count=0
for id in "${sink_ids[@]}"; do
  state=$(get_mute_state "$sink_inputs_after" "$id")
  case "$state" in
    yes) muted_count=$((muted_count + 1)) ;;
    no) unmuted_count=$((unmuted_count + 1)) ;;
  esac
done

if [[ $muted_count -gt 0 && $unmuted_count -eq 0 ]]; then
  state_msg="Muted"
elif [[ $unmuted_count -gt 0 && $muted_count -eq 0 ]]; then
  state_msg="Unmuted"
elif [[ $muted_count -gt 0 && $unmuted_count -gt 0 ]]; then
  state_msg="Mixed"
fi

notify 0 "$state_msg"
