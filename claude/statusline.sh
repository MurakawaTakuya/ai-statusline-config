#!/usr/bin/env bash

# Codex-like Claude Code status line. Claude Code sends session JSON on stdin.
input=$(cat)

if ! values=$(printf '%s' "$input" | jq -r '
  def clean:
    if . == null then ""
    else tostring | gsub("[\\r\\n]"; " ")
    end;
  [
    .model.display_name,
    .effort.level,
    .thinking.enabled,
    .fast_mode,
    .rate_limits.five_hour.used_percentage,
    .rate_limits.five_hour.resets_at,
    .rate_limits.seven_day.used_percentage,
    .rate_limits.seven_day.resets_at,
    .session_name,
    .workspace.current_dir,
    (.worktree.name // .workspace.git_worktree),
    .context_window.used_percentage,
    .context_window.total_input_tokens,
    .context_window.total_output_tokens,
    .context_window.context_window_size,
    (if .prompt_cache.hit_ratio == null then null else (.prompt_cache.hit_ratio * 100 | floor) end),
    .prompt_cache.warm,
    .prompt_cache.expires_at,
    .session_id,
    .cost.total_cost_usd
  ] | map(clean) | join("\u001f")
'); then
  printf 'Claude status unavailable\n'
  exit 0
fi

IFS=$'\x1f' read -r model effort thinking fast_mode five_pct five_reset week_pct \
  week_reset session_name cwd worktree_name context_pct total_input total_output \
  context_size cache_hit_pct cache_warm cache_expires session_id session_cost <<< "$values"

RESET=$'\033[0m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
CYAN=$'\033[36m'
BLUE=$'\033[34m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
MAGENTA=$'\033[35m'

to_int() {
  local value=${1:-0}
  value=${value%.*}
  case "$value" in
    ''|*[!0-9]*) value=0 ;;
  esac
  printf '%d' "$value"
}

format_tokens() {
  local value whole tenth
  value=$(to_int "$1")

  if [ "$value" -ge 1000000 ]; then
    whole=$((value / 1000000))
    tenth=$(((value % 1000000) / 100000))
    if [ "$tenth" -eq 0 ]; then printf '%dM' "$whole"; else printf '%d.%dM' "$whole" "$tenth"; fi
  elif [ "$value" -ge 1000 ]; then
    whole=$((value / 1000))
    tenth=$(((value % 1000) / 100))
    if [ "$tenth" -eq 0 ]; then printf '%dk' "$whole"; else printf '%d.%dk' "$whole" "$tenth"; fi
  else
    printf '%d' "$value"
  fi
}

bar() {
  # bar <pct> [marker_pct color]
  local pct=$1
  local marker_pct=${2:-}
  local color=${3:-}
  local width=10
  local filled output i marker_idx=-1

  pct=$(to_int "$pct")
  [ "$pct" -gt 100 ] && pct=100
  filled=$((pct * width / 100))

  if [ -n "$marker_pct" ]; then
    marker_pct=$(to_int "$marker_pct")
    [ "$marker_pct" -gt 100 ] && marker_pct=100
    marker_idx=$(((marker_pct * width + 50) / 100))
    [ "$marker_idx" -ge "$width" ] && marker_idx=$((width - 1))
  fi

  output=""
  i=0
  while [ "$i" -lt "$width" ]; do
    if [ "$i" -eq "$marker_idx" ]; then
      output="${output}${RESET}${BOLD}┃${RESET}${color}"
    elif [ "$i" -lt "$filled" ]; then
      output="${output}█"
    else
      output="${output}░"
    fi
    i=$((i + 1))
  done

  printf '%s' "$output"
}

human_duration() {
  local seconds=$1
  local days hours minutes

  if [ "$seconds" -le 0 ]; then
    printf 'now'
    return
  fi

  days=$((seconds / 86400))
  hours=$(((seconds % 86400) / 3600))
  minutes=$(((seconds % 3600) / 60))

  if [ "$days" -gt 0 ]; then
    printf '%dd%dh' "$days" "$hours"
  elif [ "$hours" -gt 0 ]; then
    printf '%dh%dm' "$hours" "$minutes"
  else
    printf '%dm' "$minutes"
  fi
}

percent_color() {
  local pct
  pct=$(to_int "$1")
  if [ "$pct" -ge 90 ]; then
    printf '%s' "$RED"
  elif [ "$pct" -ge 70 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

remaining_color() {
  local pct
  pct=$(to_int "$1")
  if [ "$pct" -lt 20 ]; then
    printf '%s' "$RED"
  elif [ "$pct" -lt 50 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

limit_segment() {
  local label=$1
  local window=${4:-0}
  local used_pct reset_at now remaining_pct remaining_time color pace_pct=""
  used_pct=$(to_int "$2")
  reset_at=$(to_int "$3")
  [ "$used_pct" -gt 100 ] && used_pct=100
  remaining_pct=$((100 - used_pct))
  color=$(remaining_color "$remaining_pct")

  now=$(date +%s)
  remaining_time=$((reset_at - now))
  # Pace marker: where "left %" would sit if the window were used at a constant rate.
  if [ "$reset_at" -gt 0 ] && [ "$window" -gt 0 ]; then
    [ "$remaining_time" -lt 0 ] && remaining_time=0
    pace_pct=$((remaining_time * 100 / window))
  fi

  printf '%s%s %s %d%% left%s' "$color" "$label" \
    "$(bar "$remaining_pct" "$pace_pct" "$color")" "$remaining_pct" "$RESET"
  if [ "$reset_at" -gt 0 ]; then
    printf '%s %s%s' "$DIM" "$(human_duration "$remaining_time")" "$RESET"
  fi
}

format_usd() {
  local value=$1
  case "$value" in
    ''|*[!0-9.]*) return 1 ;;
  esac
  LC_NUMERIC=C printf '$%.2f' "$value"
}

find_ccusage() {
  local candidate
  if command -v ccusage >/dev/null 2>&1; then
    command -v ccusage
    return 0
  fi
  for candidate in "$HOME/.local/share/mise/shims/ccusage" /opt/homebrew/bin/ccusage /usr/local/bin/ccusage; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

today_cost=""

# Today's total across all sessions comes from ccusage (reads ~/.claude/projects/*.jsonl).
# The result is cached for 60s and shared by every session, since the value is global.
load_today_cost() {
  local cache_dir cache_file cache_tmp cache_mtime now cost ccusage_bin

  cache_dir=${TMPDIR:-/tmp}
  cache_file="${cache_dir%/}/claude-statusline-today-cost"
  now=$(date +%s)
  cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || printf '0')

  if [ ! -f "$cache_file" ] || [ $((now - cache_mtime)) -gt 60 ]; then
    ccusage_bin=$(find_ccusage) || return
    cost=$("$ccusage_bin" daily --json --since "$(date +%Y%m%d)" 2>/dev/null \
      | jq -r '.daily[0].totalCost // empty' 2>/dev/null || true)
    if [ -n "$cost" ]; then
      cache_tmp="${cache_file}.tmp.$$"
      printf '%s\n' "$cost" > "$cache_tmp"
      mv "$cache_tmp" "$cache_file"
    elif [ -f "$cache_file" ]; then
      touch "$cache_file"
    fi
  fi

  [ -f "$cache_file" ] && IFS= read -r today_cost < "$cache_file"
}

git_branch=""
git_staged=0
git_modified=0
git_untracked=0

load_git_status() {
  local safe_session cache_dir cache_file cache_mtime now status cache_tmp

  [ -d "$cwd" ] || return
  safe_session=$(printf '%s' "${session_id:-default}" | tr -cd '[:alnum:]_-')
  [ -n "$safe_session" ] || safe_session=default
  cache_dir=${TMPDIR:-/tmp}
  cache_file="${cache_dir%/}/claude-statusline-git-${safe_session}"
  now=$(date +%s)
  cache_mtime=$(stat -f %m "$cache_file" 2>/dev/null || printf '0')

  if [ ! -f "$cache_file" ] || [ $((now - cache_mtime)) -gt 5 ]; then
    git_branch=$(git -C "$cwd" branch --show-current 2>/dev/null || true)
    if [ -z "$git_branch" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
      git_branch="detached@$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)"
    fi

    status=$(git -C "$cwd" status --porcelain=v1 --untracked-files=normal 2>/dev/null || true)
    git_staged=$(printf '%s\n' "$status" | awk 'length($0) >= 2 && substr($0, 1, 2) != "??" && substr($0, 1, 1) != " " { n++ } END { print n + 0 }')
    git_modified=$(printf '%s\n' "$status" | awk 'length($0) >= 2 && substr($0, 1, 2) != "??" && substr($0, 2, 1) != " " { n++ } END { print n + 0 }')
    git_untracked=$(printf '%s\n' "$status" | awk 'substr($0, 1, 2) == "??" { n++ } END { print n + 0 }')

    cache_tmp="${cache_file}.tmp.$$"
    printf '%s|%d|%d|%d\n' "$git_branch" "$git_staged" "$git_modified" "$git_untracked" > "$cache_tmp"
    mv "$cache_tmp" "$cache_file"
  fi

  IFS='|' read -r git_branch git_staged git_modified git_untracked < "$cache_file"
}

append_segment() {
  local segment=$1
  if [ -n "$line" ]; then
    line="${line}${DIM} | ${RESET}"
  fi
  line="${line}${segment}"
}

model=${model:-Claude}
model_label=$model
if [ -n "$effort" ]; then
  model_label="${model_label} (${effort})"
elif [ "$thinking" = "true" ]; then
  model_label="${model_label} (thinking)"
fi

line=""
model_segment="${CYAN}${model_label}${RESET}"
[ "$fast_mode" = "true" ] && model_segment="${model_segment}${YELLOW} FAST${RESET}"
append_segment "$model_segment"
sync_rate_limits() {
  # Share rate limits across sessions: an idle session only sees the values from
  # its own last API response. Each session writes only its own values to its own
  # file (no write races); readers take, per window, the max used % among entries
  # in the newest unexpired window. Usage never decreases within a window, and
  # resets_at within 10 min of the newest is treated as the same window (jitter).
  local dir="$HOME/.claude/statusline-ratelimits"
  local safe_session own tmp now merged

  mkdir -p "$dir" 2>/dev/null || return
  safe_session=$(printf '%s' "${session_id:-default}" | tr -cd '[:alnum:]_-')
  [ -n "$safe_session" ] || safe_session=default
  own="$dir/$safe_session"

  if [ -n "$five_pct$week_pct" ]; then
    tmp="$dir/.${safe_session}.tmp.$$"  # dotfile: skipped by the * glob below
    {
      if [ -n "$five_pct" ]; then printf '5h %s %s\n' "$(to_int "$five_reset")" "$(to_int "$five_pct")"; fi
      if [ -n "$week_pct" ]; then printf 'week %s %s\n' "$(to_int "$week_reset")" "$(to_int "$week_pct")"; fi
    } > "$tmp" && mv "$tmp" "$own" || rm -f "$tmp"
  fi

  # Drop files of sessions not updated for over a week.
  find "$dir" -type f -mtime +8 -delete 2>/dev/null

  now=$(date +%s)
  merged=$(cat "$dir"/* 2>/dev/null | awk -v now="$now" '
    $2 > now {
      n[$1]++; r[$1, n[$1]] = $2; p[$1, n[$1]] = $3
      if ($2 > maxr[$1]) maxr[$1] = $2
    }
    END {
      for (w in n) {
        best = -1
        for (i = 1; i <= n[w]; i++)
          if (r[w, i] >= maxr[w] - 600 && p[w, i] > best) best = p[w, i]
        print w, maxr[w], best
      }
    }')

  local name reset pct
  while read -r name reset pct; do
    case "$name" in
      5h) five_reset=$reset; five_pct=$pct ;;
      week) week_reset=$reset; week_pct=$pct ;;
    esac
  done <<< "$merged"
}

sync_rate_limits
[ -n "$five_pct" ] && append_segment "$(limit_segment '5h' "$five_pct" "$five_reset" 18000)"
[ -n "$week_pct" ] && append_segment "$(limit_segment 'week' "$week_pct" "$week_reset" 604800)"
if session_cost_fmt=$(format_usd "$session_cost"); then
  append_segment "${YELLOW}session ${session_cost_fmt}${RESET}"
fi

printf '%s\n' "$line"
line=""

context_pct=$(to_int "$context_pct")
total_input=$(to_int "$total_input")
total_output=$(to_int "$total_output")
context_size=$(to_int "$context_size")
used_tokens=$((total_input + total_output))
context_color=$(percent_color "$context_pct")

context_segment="${context_color}Context $(bar "$context_pct") ${context_pct}% used${RESET}"
if [ "$context_size" -gt 0 ]; then
  context_segment="${context_segment}${DIM} · $(format_tokens "$used_tokens")/$(format_tokens "$context_size")${RESET}"
fi
append_segment "$context_segment"

if [ -n "$cache_hit_pct" ]; then
  cache_hit_pct=$(to_int "$cache_hit_pct")
  cache_expires=$(to_int "$cache_expires")
  cache_now=$(date +%s)

  if [ "$cache_warm" = "true" ] && [ "$cache_expires" -gt "$cache_now" ]; then
    cache_remaining=$((cache_expires - cache_now))
    cache_segment="${GREEN}cache ${cache_hit_pct}% warm${RESET}${DIM} · $(human_duration "$cache_remaining") left${RESET}"
  else
    cache_segment="${YELLOW}cache ${cache_hit_pct}% cold${RESET}"
  fi
  append_segment "$cache_segment"
fi

load_today_cost
if today_cost_fmt=$(format_usd "$today_cost"); then
  append_segment "${YELLOW}today ${today_cost_fmt}${RESET}"
fi

printf '%s\n' "$line"
line=""

[ -n "$session_name" ] && append_segment "${MAGENTA}${session_name}${RESET}"
if [ -n "$cwd" ]; then
  case "$cwd" in
    "$HOME") dir_label="~" ;;
    "$HOME"/*) dir_label="~${cwd#"$HOME"}" ;;
    *) dir_label=$cwd ;;
  esac
  append_segment "${BLUE}${dir_label}${RESET}"
  load_git_status
fi

[ -n "$git_branch" ] && append_segment "${GREEN}${git_branch}${RESET}"
[ -n "$worktree_name" ] && append_segment "${MAGENTA}wt:${worktree_name}${RESET}"
if [ $((git_staged + git_modified + git_untracked)) -gt 0 ]; then
  append_segment "${YELLOW}+${git_staged} ~${git_modified} ?${git_untracked}${RESET}"
elif [ -n "$git_branch" ]; then
  append_segment "${DIM}clean${RESET}"
fi

[ -n "$line" ] && printf '%s\n' "$line"
