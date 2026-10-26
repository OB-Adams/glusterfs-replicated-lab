#!/usr/bin/env bash
# Print a file count and one combined checksum for a directory on a brick.
# Run on each server with the same path and compare the output.
# Usage: compare-bricks.sh <directory-on-brick>
# Only inspect bricks with this script. Never write to a brick directory.
set -euo pipefail

dir=${1:?usage: compare-bricks.sh <directory-on-brick>}

if [ ! -d "$dir" ]; then
  echo "not a directory: $dir" >&2
  exit 1
fi

cd "$dir"
count=$(find . -type f | wc -l)
digest=$(find . -type f -print0 | sort -z | xargs -0 -r sha256sum | sha256sum | cut -d' ' -f1)

echo "host:   $(hostname)"
echo "path:   $dir"
echo "files:  $count"
echo "digest: $digest"
