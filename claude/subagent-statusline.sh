#!/usr/bin/env bash

# Customize rows in Claude Code's subagent panel.
input=$(cat)

if ! rows=$(printf '%s' "$input" | jq -r '
  def clean:
    if . == null then ""
    else tostring | gsub("[\\r\\n]"; " ")
    end;
  .tasks[]? |
  [
    .id,
    (.name // .label // .type // "agent"),
    .status,
    .model,
    .effort,
    .contextWindowSize,
    .tokenCount
  ] | map(clean) | join("\u001f")
'); then
  exit 0
fi

RESET=$'\033[0m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'

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
  local pct=$1
  local width=10
  local filled empty output i

  pct=$(to_int "$pct")
  [ "$pct" -gt 100 ] && pct=100
  filled=$((pct * width / 100))
  empty=$((width - filled))
  output=""
  i=0

  while [ "$i" -lt "$filled" ]; do
    output="${output}█"
    i=$((i + 1))
  done
  i=0
  while [ "$i" -lt "$empty" ]; do
    output="${output}░"
    i=$((i + 1))
  done

  printf '%s' "$output"
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

format_model() {
  local value=$1
  [ -n "$value" ] || return
  value=${value#claude-}
  value=$(printf '%s' "$value" | sed -E 's/-[0-9]{8}$//; s/([0-9])-([0-9])/\1.\2/g; s/-/ /g')
  printf '%s' "$value" | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i == "opus") $i = "Opus"
      else if ($i == "sonnet") $i = "Sonnet"
      else if ($i == "haiku") $i = "Haiku"
    }
    printf "%s", $1
    for (i = 2; i <= NF; i++) printf " %s", $i
  }'
}

while IFS=$'\x1f' read -r task_id task_name task_status task_model task_effort \
  context_size token_count; do
  [ -n "$task_id" ] || continue

  status_key=$(printf '%s' "$task_status" | tr '[:upper:]' '[:lower:]')
  case "$status_key" in
    *running*|*progress*) icon="●"; status_label="running"; status_color=$GREEN ;;
    *completed*|*success*|*done*) icon="✓"; status_label="done"; status_color=$GREEN ;;
    *fail*|*error*) icon="✗"; status_label="error"; status_color=$RED ;;
    *pending*|*queued*|*waiting*) icon="○"; status_label="waiting"; status_color=$YELLOW ;;
    *) icon="•"; status_label=${status_key:-unknown}; status_color=$DIM ;;
  esac

  content="${status_color}${icon} ${task_name} ${status_label}${RESET}"
  separator="${DIM} | ${RESET}"

  if [ -n "$task_model" ]; then
    model_label=$(format_model "$task_model")
    [ -n "$task_effort" ] && model_label="${model_label} (${task_effort})"
    content="${content}${separator}${CYAN}${model_label}${RESET}"
  fi

  context_size=$(to_int "$context_size")
  token_count=$(to_int "$token_count")
  if [ "$context_size" -gt 0 ]; then
    context_pct=$((token_count * 100 / context_size))
    [ "$context_pct" -gt 100 ] && context_pct=100
    context_color=$(percent_color "$context_pct")
    content="${content}${separator}${context_color}$(bar "$context_pct") ${context_pct}%${RESET}${DIM} · $(format_tokens "$token_count")/$(format_tokens "$context_size")${RESET}"
  elif [ "$token_count" -gt 0 ]; then
    content="${content}${separator}${DIM}$(format_tokens "$token_count")${RESET}"
  fi

  jq -nc --arg id "$task_id" --arg content "$content" '{id: $id, content: $content}'
done <<< "$rows"
