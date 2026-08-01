#!/bin/sh
set -eu

: "${FRAGMENT_FDW_PASSWORD:?FRAGMENT_FDW_PASSWORD is required}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=fdw_password="$FRAGMENT_FDW_PASSWORD" <<'EOSQL'
CREATE ROLE public_role LOGIN PASSWORD :'fdw_password';
CREATE ROLE fdw_reader LOGIN PASSWORD :'fdw_password';

GRANT SELECT ON patients_public TO public_role;
GRANT SELECT ON patients_public TO fdw_reader;
EOSQL
