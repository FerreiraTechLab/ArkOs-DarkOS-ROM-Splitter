#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_log="$(mktemp /tmp/rom-splitter-stage.XXXXXX)"
source "$repo_dir/packaging/Install ROM Splitter.sh"
LOG_FILE="$test_log"
trap 'cleanup; rm -f -- "$test_log"' EXIT

ui_gauge() { return 1; }
stage_ok() { progress 100 'Work completed.'; return 0; }
stage_fail() { return 2; }

run_stage 'Test stage' 'Test' stage_ok
if run_stage 'Test stage' 'Test' stage_fail; then
  printf 'Backend failure was hidden by the gauge fallback\n' >&2
  exit 1
fi

printf 'installer-stage-tests-ok\n'
