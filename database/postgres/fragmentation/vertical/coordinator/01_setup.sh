#!/bin/sh
set -eu

: "${FRAGMENT_PUBLIC_DB:?FRAGMENT_PUBLIC_DB is required}"
: "${FRAGMENT_FINANCIAL_DB:?FRAGMENT_FINANCIAL_DB is required}"
: "${FRAGMENT_FDW_PASSWORD:?FRAGMENT_FDW_PASSWORD is required}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=public_db="$FRAGMENT_PUBLIC_DB" \
    --set=financial_db="$FRAGMENT_FINANCIAL_DB" \
    --set=fdw_password="$FRAGMENT_FDW_PASSWORD" \
    --set=coordinator_user="$POSTGRES_USER" <<'EOSQL'
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER fragment_public_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'fragment-public', dbname :'public_db', port '5432');

CREATE SERVER fragment_financial_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'fragment-financial', dbname :'financial_db', port '5432');

CREATE FOREIGN TABLE patients_public (
    patient_id integer,
    full_name text,
    phone text,
    email text,
    address text,
    emergency_contact text
) SERVER fragment_public_server OPTIONS (table_name 'patients_public');

CREATE FOREIGN TABLE patients_financial (
    patient_id integer,
    insurance_provider text,
    insurance_number text,
    billing_status text,
    outstanding_balance numeric(12, 2),
    payment_method text
) SERVER fragment_financial_server OPTIONS (table_name 'patients_financial');

CREATE ROLE public_role LOGIN PASSWORD :'fdw_password';
CREATE ROLE financial_role LOGIN PASSWORD :'fdw_password';

CREATE USER MAPPING FOR :"coordinator_user" SERVER fragment_public_server
    OPTIONS (user 'fdw_reader', password :'fdw_password');
CREATE USER MAPPING FOR :"coordinator_user" SERVER fragment_financial_server
    OPTIONS (user 'fdw_reader', password :'fdw_password');
CREATE USER MAPPING FOR public_role SERVER fragment_public_server
    OPTIONS (user 'fdw_reader', password :'fdw_password');
CREATE USER MAPPING FOR financial_role SERVER fragment_financial_server
    OPTIONS (user 'fdw_reader', password :'fdw_password');

GRANT SELECT ON patients_public TO public_role;
GRANT SELECT ON patients_financial TO financial_role;

CREATE VIEW patients_full AS
SELECT
    p.patient_id,
    p.full_name,
    p.phone,
    p.email,
    p.address,
    p.emergency_contact,
    f.insurance_provider,
    f.insurance_number,
    f.billing_status,
    f.outstanding_balance,
    f.payment_method
FROM patients_public p
JOIN patients_financial f USING (patient_id);
EOSQL
