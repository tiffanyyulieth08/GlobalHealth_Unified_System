#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

MONGODB_DIR="database/mongodb"
MONGODB_DB="${MONGODB_DB:-globalhealth_test}"
export MONGODB_DB

if [ -n "${MONGODB_URI:-}" ]; then
    if ! command -v mongosh >/dev/null 2>&1; then
        echo "mongosh is required when MONGODB_URI is provided." >&2
        exit 1
    fi
    run_file() {
        mongosh "$MONGODB_URI" --quiet --file "$1"
    }
    cleanup() {
        mongosh "$MONGODB_URI" --quiet --eval \
            "db.getSiblingDB('$MONGODB_DB').dropDatabase()" >/dev/null
    }
else
    docker compose up -d mongodb
    run_file() {
        docker compose exec -T \
            -e MONGODB_DB="$MONGODB_DB" \
            mongodb mongosh "mongodb://localhost:27017/$MONGODB_DB" --quiet < "$1"
    }
    cleanup() {
        docker compose exec -T mongodb \
            mongosh "mongodb://localhost:27017/$MONGODB_DB" --quiet \
            --eval "db.dropDatabase()" >/dev/null
    }
fi

trap cleanup EXIT

for file in 01_collections.js 02_seed.js 03_operations.js 04_aggregations.js 05_tests.js; do
    echo "==> $file"
    run_file "$MONGODB_DIR/$file"
done

echo "All MongoDB scripts passed."
