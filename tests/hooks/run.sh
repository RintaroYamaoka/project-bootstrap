#!/usr/bin/env bash
# Runs every tests/hooks/*.test.bash as its own process and aggregates results.
# Usage: bash tests/hooks/run.sh
set -u
cd "$(dirname "$0")"

total_files=0
failed_files=0

for f in *.test.bash; do
  [ -e "$f" ] || continue
  total_files=$((total_files + 1))
  echo "== $f =="
  if ! bash "$f"; then
    failed_files=$((failed_files + 1))
  fi
done

echo
echo "SUITES: $total_files run, $failed_files failed"
[ "$failed_files" = 0 ]
