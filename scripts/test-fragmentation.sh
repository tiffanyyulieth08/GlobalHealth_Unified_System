#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

sh scripts/test-fragmentation-vertical.sh
sh scripts/test-fragmentation-horizontal.sh

echo "All fragmentation tests passed."
