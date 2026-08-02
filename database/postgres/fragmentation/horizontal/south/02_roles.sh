#!/bin/sh
set -eu

: "${FRAGMENT_HORIZONTAL_FDW_PASSWORD:?FRAGMENT_HORIZONTAL_FDW_PASSWORD is required}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=fdw_password="$FRAGMENT_HORIZONTAL_FDW_PASSWORD" <<'EOSQL'
CREATE ROLE fdw_writer LOGIN PASSWORD :'fdw_password';

GRANT SELECT, INSERT ON patients TO fdw_writer;
EOSQL
