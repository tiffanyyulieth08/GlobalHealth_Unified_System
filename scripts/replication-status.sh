#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

DB_NAME="${POSTGRES_DB:-globalhealth}"
DB_USER="${POSTGRES_USER:-globalhealth}"

compose() {
    if [ -n "${REPLICATION_COMPOSE_PROJECT:-}" ]; then
        docker compose -p "$REPLICATION_COMPOSE_PROJECT" "$@"
    else
        docker compose "$@"
    fi
}

echo "==> Primary"
compose exec -T postgres-primary \
    psql -U "$DB_USER" -d "$DB_NAME" -P pager=off -c "
        SELECT pg_is_in_recovery() AS in_recovery;
        SELECT
            application_name,
            client_addr,
            state,
            sync_state,
            sent_lsn,
            replay_lsn
        FROM pg_stat_replication;
    "

echo "==> Replica"
compose exec -T postgres-replica \
    psql -U "$DB_USER" -d "$DB_NAME" -P pager=off -c "
        SELECT pg_is_in_recovery() AS in_recovery;
        SELECT
            status,
            sender_host,
            sender_port,
            written_lsn,
            flushed_lsn,
            latest_end_lsn
        FROM pg_stat_wal_receiver;
    "
