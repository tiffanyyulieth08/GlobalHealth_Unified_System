#!/bin/sh
set -eu

: "${POSTGRES_PRIMARY_HOST:?POSTGRES_PRIMARY_HOST is required}"
: "${POSTGRES_REPLICATION_USER:?POSTGRES_REPLICATION_USER is required}"
: "${POSTGRES_REPLICATION_PASSWORD:?POSTGRES_REPLICATION_PASSWORD is required}"

if [ "$(id -u)" = "0" ]; then
    mkdir -p "$PGDATA"
    chown -R postgres:postgres "$PGDATA"
    chmod 0700 "$PGDATA"
    exec gosu postgres "$0" "$@"
fi

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    find "$PGDATA" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    until PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" pg_basebackup \
        --host="$POSTGRES_PRIMARY_HOST" \
        --port="${POSTGRES_PRIMARY_PORT:-5432}" \
        --username="$POSTGRES_REPLICATION_USER" \
        --pgdata="$PGDATA" \
        --format=plain \
        --wal-method=stream \
        --write-recovery-conf \
        --checkpoint=fast
    do
        sleep 2
    done
fi

touch "$PGDATA/standby.signal"
chmod 0700 "$PGDATA"

exec docker-entrypoint.sh postgres -c hot_standby=on
