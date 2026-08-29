#!/usr/bin/env bash

set -euo pipefail

mode=${1:-all}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
target_home=${STATUSLINE_TARGET_HOME:-${HOME:?HOME is not set}}
timestamp=$(date +%Y%m%d-%H%M%S)

usage() {
  printf 'Usage: %s [all|claude|codex]\n' "$0"
}

case "$mode" in
  all|claude|codex) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  printf 'Error: python3 is required.\n' >&2
  exit 1
fi

backup_file() {
  local path=$1
  if [ -f "$path" ]; then
    cp -p "$path" "${path}.bak.${timestamp}"
    printf 'Backup: %s\n' "${path}.bak.${timestamp}"
  fi
}

install_claude() {
  local claude_dir settings_file

  if ! command -v jq >/dev/null 2>&1; then
    printf 'Error: jq is required by the Claude statusline.\n' >&2
    exit 1
  fi

  claude_dir="${target_home}/.claude"
  settings_file="${claude_dir}/settings.json"
  mkdir -p "$claude_dir"

  backup_file "${claude_dir}/statusline.sh"
  backup_file "${claude_dir}/subagent-statusline.sh"
  backup_file "$settings_file"

  install -m 0755 "${script_dir}/claude/statusline.sh" "${claude_dir}/statusline.sh"
  install -m 0755 "${script_dir}/claude/subagent-statusline.sh" "${claude_dir}/subagent-statusline.sh"
  python3 "${script_dir}/scripts/merge_claude_settings.py" \
    "$settings_file" "${script_dir}/claude/settings-snippet.json"

  printf 'Installed Claude statusline into %s\n' "$claude_dir"
}

install_codex() {
  local codex_dir config_file

  codex_dir="${target_home}/.codex"
  config_file="${codex_dir}/config.toml"
  mkdir -p "$codex_dir"

  backup_file "$config_file"
  python3 "${script_dir}/scripts/merge_codex_statusline.py" \
    "$config_file" "${script_dir}/codex/statusline-snippet.toml"

  printf 'Installed Codex statusline into %s\n' "$config_file"
}

case "$mode" in
  all)
    install_claude
    install_codex
    ;;
  claude) install_claude ;;
  codex) install_codex ;;
esac

printf 'Done. Restart the affected CLI application(s).\n'
