#!/usr/bin/env bash
# Write Gluster brick, heal and peer state for node_exporter's textfile collector.
# Usage: gluster-metrics.sh [volume] [textfile-directory]
set -uo pipefail

vol=${1:-gv0}
dir=${2:-/var/lib/node_exporter/textfile}
out="$dir/gluster.prom"
tmp=$(mktemp "$dir/.gluster.prom.XXXXXX") || exit 1
trap 'rm -f "$tmp"' EXIT

status=$(gluster volume status "$vol" 2>/dev/null); rc_status=$?
# heal info can exit non-zero while a brick is unreachable, so its output is checked instead
heal=$(gluster volume heal "$vol" info summary 2>/dev/null)
pool=$(gluster pool list 2>/dev/null); rc_pool=$?

{
  echo '# HELP gluster_brick_up Brick process online according to gluster volume status (1 online, 0 offline).'
  echo '# TYPE gluster_brick_up gauge'
  printf '%s\n' "$status" | awk -v v="$vol" '$1 == "Brick" {
    split($2, a, ":")
    printf "gluster_brick_up{volume=\"%s\",host=\"%s\",brick=\"%s\"} %d\n", v, a[1], $2, ($(NF-1) == "Y")
  }'

  echo '# HELP gluster_heal_pending_entries Entries pending heal on a brick. Absent while the brick is unreachable.'
  echo '# TYPE gluster_heal_pending_entries gauge'
  printf '%s\n' "$heal" | awk -v v="$vol" '
    /^Brick / { b = $2 }
    /^Total Number of entries:/ && $NF ~ /^[0-9]+$/ {
      printf "gluster_heal_pending_entries{volume=\"%s\",brick=\"%s\"} %s\n", v, b, $NF }'

  echo '# HELP gluster_heal_split_brain_entries Entries in split-brain on a brick. Absent while the brick is unreachable.'
  echo '# TYPE gluster_heal_split_brain_entries gauge'
  printf '%s\n' "$heal" | awk -v v="$vol" '
    /^Brick / { b = $2 }
    /^Number of entries in split-brain:/ && $NF ~ /^[0-9]+$/ {
      printf "gluster_heal_split_brain_entries{volume=\"%s\",brick=\"%s\"} %s\n", v, b, $NF }'

  echo '# HELP gluster_peer_connected Peer state according to gluster pool list (1 connected).'
  echo '# TYPE gluster_peer_connected gauge'
  printf '%s\n' "$pool" | awk 'NR > 1 && NF >= 3 {
    printf "gluster_peer_connected{peer=\"%s\"} %d\n", $2, ($3 == "Connected") }'

  if [ "$rc_status" -eq 0 ] && [ "$rc_pool" -eq 0 ] && printf '%s\n' "$heal" | grep -q '^Brick '; then
    echo '# HELP gluster_metrics_last_success_timestamp_seconds Unix time of the last run in which every gluster command returned data.'
    echo '# TYPE gluster_metrics_last_success_timestamp_seconds gauge'
    echo "gluster_metrics_last_success_timestamp_seconds $(date +%s)"
  fi
} > "$tmp"

chmod 0644 "$tmp"
mv "$tmp" "$out"
trap - EXIT
