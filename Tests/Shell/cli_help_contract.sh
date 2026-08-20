#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="${1:-$ROOT_DIR/.build/debug/peeker-cli}"

test -x "$CLI"

paths=(
  ""
  "status"
  "timer"
  "timer list"
  "timer get"
  "timer create"
  "timer update"
  "timer delete"
  "timer start"
  "timer pause"
  "timer move"
  "timer config"
  "timer config get"
  "timer config set"
  "pusher"
  "pusher list"
  "pusher get"
  "pusher create"
  "pusher update"
  "pusher delete"
  "pusher move"
  "pusher config"
  "pusher config get"
  "pusher config set"
  "scheduler"
  "scheduler list"
  "scheduler get"
  "scheduler create"
  "scheduler update"
  "scheduler delete"
  "scheduler source"
  "scheduler source list"
  "scheduler source import"
  "scheduler source refresh"
  "scheduler source remove"
  "scheduler config"
  "scheduler config get"
  "scheduler config set"
)

usages=(
  "Usage: peeker <command>"
  "Usage: peeker status"
  "Usage: peeker timer <command> [arguments]"
  "Usage: peeker timer list"
  "Usage: peeker timer get (--id <template-id> | <exact-name>)"
  "Usage: peeker timer create --name <name> --target <duration> --color <#RRGGBB>"
  "Usage: peeker timer update (--id <template-id> | <exact-name>) [options]"
  "Usage: peeker timer delete (--id <template-id> | <exact-name>)"
  "Usage: peeker timer start (--id <template-id> | <exact-name>)"
  "Usage: peeker timer pause"
  "Usage: peeker timer move (--id <template-id> | <exact-name>) [--before <template-id> | --after <template-id>]"
  "Usage: peeker timer config <command>"
  "Usage: peeker timer config get"
  "Usage: peeker timer config set [--enabled <bool>] [--refresh-time <HH:mm>]"
  "Usage: peeker pusher <command> [arguments]"
  "Usage: peeker pusher list [--status <status>]"
  "Usage: peeker pusher get (--id <task-id> | <exact-title>)"
  "Usage: peeker pusher create --title <title> --urgency <urgency> [--daily <bool>]"
  "Usage: peeker pusher update (--id <task-id> | <exact-title>) [options]"
  "Usage: peeker pusher delete (--id <task-id> | <exact-title>)"
  "Usage: peeker pusher move (--id <task-id> | <exact-title>) --status <status> [--before <task-id> | --after <task-id>]"
  "Usage: peeker pusher config <command>"
  "Usage: peeker pusher config get"
  "Usage: peeker pusher config set [--enabled <bool>] [--carry-incomplete <bool>] [--refresh-time <HH:mm>]"
  "Usage: peeker scheduler <command> [arguments]"
  "Usage: peeker scheduler list [--from <time-or-date> --to <time-or-date>]"
  "Usage: peeker scheduler get --id <event-id> [--occurrence <time-or-date>]"
  "Usage: peeker scheduler create --title <title> <time-range> [options]"
  "Usage: peeker scheduler update --id <event-id> [--occurrence <key> --scope <scope>] [options]"
  "Usage: peeker scheduler delete --id <event-id> [--occurrence <key> --scope <scope>]"
  "Usage: peeker scheduler source <command> [arguments]"
  "Usage: peeker scheduler source list"
  "Usage: peeker scheduler source import --file <path>"
  "Usage: peeker scheduler source refresh --id <source-id> [--file <new-path>]"
  "Usage: peeker scheduler source remove --id <source-id>"
  "Usage: peeker scheduler config <command>"
  "Usage: peeker scheduler config get"
  "Usage: peeker scheduler config set [--enabled <bool>] [--reminder <off|1..60>]"
)

test "${#paths[@]}" -eq "${#usages[@]}"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

for index in "${!paths[@]}"; do
  for flag in --help -h; do
    args=()
    if [[ -n "${paths[$index]}" ]]; then
      read -r -a args <<< "${paths[$index]}"
    fi
    stdout="$TMP_ROOT/stdout"
    stderr="$TMP_ROOT/stderr"

    set +e
    if [[ ${#args[@]} -eq 0 ]]; then
      TMPDIR="$TMP_ROOT/" "$CLI" "$flag" >"$stdout" 2>"$stderr"
    else
      TMPDIR="$TMP_ROOT/" "$CLI" "${args[@]}" "$flag" >"$stdout" 2>"$stderr"
    fi
    status=$?
    set -e

    if [[ $status -ne 0 ]]; then
      echo "help failed ($status): ${paths[$index]} $flag" >&2
      cat "$stderr" >&2
      exit 1
    fi
    test ! -s "$stderr"
    grep -Fq -- "${usages[$index]}" "$stdout"
  done
done

invalid_paths=(
  "unknown --help"
  "timer unknown --help"
  "timer --help extra"
  "--help timer"
  "scheduler source unknown -h"
  "scheduler list extra --help"
)

for invocation in "${invalid_paths[@]}"; do
  read -r -a args <<< "$invocation"
  stdout="$TMP_ROOT/stdout"
  stderr="$TMP_ROOT/stderr"

  set +e
  TMPDIR="$TMP_ROOT/" "$CLI" "${args[@]}" >"$stdout" 2>"$stderr"
  status=$?
  set -e

  if [[ $status -ne 2 ]]; then
    echo "invalid help path exited $status instead of 2: $invocation" >&2
    cat "$stderr" >&2
    exit 1
  fi
  test ! -s "$stdout"
  ruby -rjson -e '
    value = JSON.parse(File.read(ARGV.fetch(0)))
    abort "expected invalid_usage" unless value["ok"] == false && value.dig("error", "code") == "invalid_usage"
  ' "$stderr"
done

echo "CLI help contract passed"
