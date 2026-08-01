#!/bin/sh
set -eu

: "${POSTGRES_REPLICATION_USER:?POSTGRES_REPLICATION_USER is required}"
: "${POSTGRES_REPLICATION_PASSWORD:?POSTGRES_REPLICATION_PASSWORD is required}"

psql \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --set=replication_user="$POSTGRES_REPLICATION_USER" \
    --set=replication_password="$POSTGRES_REPLICATION_PASSWORD" <<'EOSQL'
CREATE ROLE :"replication_user"
WITH REPLICATION LOGIN PASSWORD :'replication_password';
EOSQL
