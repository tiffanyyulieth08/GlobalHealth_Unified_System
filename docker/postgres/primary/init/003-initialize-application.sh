#!/bin/sh
set -eu

MOR_DIR="/opt/globalhealth/postgres/mor"
XML_DIR="/opt/globalhealth/postgres/xml"

run_file() {
    psql \
        --username "$POSTGRES_USER" \
        --dbname "$POSTGRES_DB" \
        --set=ON_ERROR_STOP=1 \
        --file "$1"
}

for file in 01_types.sql 02_tables.sql 03_functions.sql 04_seed.sql; do
    run_file "$MOR_DIR/$file"
done

for file in 01_schema_registry.sql 02_clinical_records.sql 03_xml_operations.sql; do
    run_file "$XML_DIR/$file"
done

psql \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --set=ON_ERROR_STOP=1 \
    --set=xsd_content="$(cat "$XML_DIR/schemas/clinical-record-v1.xsd")" \
    --file "$XML_DIR/04_seed.sql"
