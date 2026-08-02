#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

sh tests/integration/run.sh
