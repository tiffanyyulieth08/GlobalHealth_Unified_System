#!/bin/sh
set -eu

run_sql() {
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$1"
}

for file in 01_types.sql 02_tables.sql 03_functions.sql 04_seed.sql; do
    run_sql "/opt/globalhealth/mor/$file"
done

for file in 01_schema_registry.sql 02_clinical_records.sql 03_xml_operations.sql; do
    run_sql "/opt/globalhealth/xml/$file"
done

xsd_content=$(cat /opt/globalhealth/xml/schemas/clinical-record-v1.xsd)
psql -v ON_ERROR_STOP=1 \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --set=xsd_content="$xsd_content" <<'SQL'
SELECT register_xml_schema(
    'clinical-record-v1',
    '1.0',
    'https://globalhealth.example/xml/clinical-record/v1',
    :'xsd_content'
);
SQL
