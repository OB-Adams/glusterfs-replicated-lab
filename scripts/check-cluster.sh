#!/usr/bin/env bash
# One-screen health summary for a Gluster volume.
# Run on any Gluster server.
# Usage: check-cluster.sh [volume-name]   (default: gv0)
set -uo pipefail

vol=${1:-gv0}

if ! command -v gluster > /dev/null 2>&1; then
  echo "gluster command not found. Run this on a Gluster server." >&2
  exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
  SUDO=sudo
else
  SUDO=
fi

section() {
  printf '\n== %s ==\n' "$1"
}

section "peers"
$SUDO gluster pool list

section "volume status: $vol"
$SUDO gluster volume status "$vol"

section "heal summary: $vol"
$SUDO gluster volume heal "$vol" info summary

section "split-brain entries: $vol"
$SUDO gluster volume heal "$vol" info split-brain

section "selected options: $vol"
for opt in cluster.quorum-type cluster.server-quorum-type cluster.self-heal-daemon network.ping-timeout; do
  $SUDO gluster volume get "$vol" "$opt" | tail -n 1
done
