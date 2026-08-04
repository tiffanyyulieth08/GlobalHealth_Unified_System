#!/bin/sh
set -eu

: "${FRAGMENT_NORTH_DB:?FRAGMENT_NORTH_DB is required}"
: "${FRAGMENT_SOUTH_DB:?FRAGMENT_SOUTH_DB is required}"
: "${FRAGMENT_HORIZONTAL_FDW_PASSWORD:?FRAGMENT_HORIZONTAL_FDW_PASSWORD is required}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=north_db="$FRAGMENT_NORTH_DB" \
    --set=south_db="$FRAGMENT_SOUTH_DB" \
    --set=fdw_password="$FRAGMENT_HORIZONTAL_FDW_PASSWORD" \
    --set=coordinator_user="$POSTGRES_USER" <<'EOSQL'
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER fragment_north_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'fragment-north', dbname :'north_db', port '5432');

CREATE SERVER fragment_south_server
    FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'fragment-south', dbname :'south_db', port '5432');

CREATE FOREIGN TABLE patients_north (
    patient_id integer,
    full_name text,
    phone text,
    email text,
    address text,
    region text
) SERVER fragment_north_server OPTIONS (table_name 'patients');

CREATE FOREIGN TABLE patients_south (
    patient_id integer,
    full_name text,
    phone text,
    email text,
    address text,
    region text
) SERVER fragment_south_server OPTIONS (table_name 'patients');

CREATE USER MAPPING FOR :"coordinator_user" SERVER fragment_north_server
    OPTIONS (user 'fdw_writer', password :'fdw_password');
CREATE USER MAPPING FOR :"coordinator_user" SERVER fragment_south_server
    OPTIONS (user 'fdw_writer', password :'fdw_password');

CREATE VIEW patients_all AS
    SELECT patient_id, full_name, phone, email, address, region
    FROM patients_north
    UNION ALL
    SELECT patient_id, full_name, phone, email, address, region
    FROM patients_south;

CREATE FUNCTION insert_patient(
    p_patient_id integer,
    p_full_name text,
    p_phone text,
    p_email text,
    p_address text,
    p_region text
) RETURNS void AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM patients_north WHERE patient_id = p_patient_id)
       OR EXISTS (SELECT 1 FROM patients_south WHERE patient_id = p_patient_id)
    THEN
        RAISE EXCEPTION 'patient_id % already exists across fragments', p_patient_id;
    END IF;

    IF p_region = 'NORTH' THEN
        INSERT INTO patients_north (patient_id, full_name, phone, email, address, region)
        VALUES (p_patient_id, p_full_name, p_phone, p_email, p_address, p_region);
    ELSIF p_region = 'SOUTH' THEN
        INSERT INTO patients_south (patient_id, full_name, phone, email, address, region)
        VALUES (p_patient_id, p_full_name, p_phone, p_email, p_address, p_region);
    ELSE
        RAISE EXCEPTION 'region % is not supported (expected NORTH or SOUTH)', p_region;
    END IF;
END;
$$ LANGUAGE plpgsql;
EOSQL
