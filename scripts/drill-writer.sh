#!/usr/bin/env bash
# Create numbered files in a directory and record how long each create takes.
# Run on the client, against a directory on the Gluster mount.
# Usage: drill-writer.sh <directory> [count] [interval-seconds] [logfile]
# Output lines: <file number> <seconds> <ok|FAIL: reason>
set -euo pipefail

dir=${1:?usage: drill-writer.sh <directory> [count] [interval-seconds] [logfile]}
count=${2:-300}
interval=${3:-0.5}
logfile=${4:-}

errfile=$(mktemp)
trap 'rm -f "$errfile"' EXIT

mkdir -p "$dir"

for i in $(seq 1 "$count"); do
  start=$(date +%s.%N)
  if { echo "$i" > "$dir/f$i.txt"; } 2> "$errfile"; then
    status=ok
  else
    status="FAIL: $(tr -d '\n' < "$errfile")"
  fi
  end=$(date +%s.%N)
  line=$(awk -v s="$start" -v e="$end" -v i="$i" -v st="$status" 'BEGIN { printf "%d %.3f %s", i, e - s, st }')
  echo "$line"
  if [ -n "$logfile" ]; then
    echo "$line" >> "$logfile"
  fi
  sleep "$interval"
done
