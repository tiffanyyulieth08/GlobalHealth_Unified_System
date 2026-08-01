#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

DB_NAME="${POSTGRES_DB:-globalhealth}"
DB_USER="${POSTGRES_USER:-globalhealth}"
TEST_ID="replication-$(date +%s)-$$"
TABLE_NAME="replication_test_$(date +%s)_$$"
MAX_ATTEMPTS="${REPLICATION_TEST_ATTEMPTS:-30}"

compose() {
    if [ -n "${REPLICATION_COMPOSE_PROJECT:-}" ]; then
        docker compose -p "$REPLICATION_COMPOSE_PROJECT" "$@"
    else
        docker compose "$@"
    fi
}

primary_query() {
    compose exec -T postgres-primary \
        psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -tAc "$1"
}

replica_query() {
    compose exec -T postgres-replica \
        psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -tAc "$1"
}

cleanup() {
    primary_query "DROP TABLE IF EXISTS $TABLE_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

compose up -d --build --wait --wait-timeout 120 postgres-primary postgres-replica

PRIMARY_RECOVERY="$(primary_query "SELECT pg_is_in_recovery()")"
REPLICA_RECOVERY="$(replica_query "SELECT pg_is_in_recovery()")"

if [ "$PRIMARY_RECOVERY" != "f" ]; then
    echo "Primary recovery state is $PRIMARY_RECOVERY; expected f" >&2
    exit 1
fi

if [ "$REPLICA_RECOVERY" != "t" ]; then
    echo "Replica recovery state is $REPLICA_RECOVERY; expected t" >&2
    exit 1
fi

primary_query "
    CREATE TABLE $TABLE_NAME (
        test_id text PRIMARY KEY,
        created_at timestamptz NOT NULL DEFAULT current_timestamp
    );
    INSERT INTO $TABLE_NAME (test_id) VALUES ('$TEST_ID');
" >/dev/null

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    REPLICATED="$(
        replica_query "
            SELECT EXISTS (
                SELECT 1
                FROM $TABLE_NAME
                WHERE test_id = '$TEST_ID'
            );
        " 2>/dev/null || true
    )"
    if [ "$REPLICATED" = "t" ]; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done

if [ "${REPLICATED:-}" != "t" ]; then
    echo "Record $TEST_ID did not reach the replica" >&2
    exit 1
fi

echo "Primary pg_is_in_recovery(): false"
echo "Replica pg_is_in_recovery(): true"
echo "Replicated record: $TEST_ID"
echo "All replication tests passed."
