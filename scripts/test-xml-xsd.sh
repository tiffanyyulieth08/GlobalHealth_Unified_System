#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

DB_NAME="${XML_XSD_DB:-globalhealth_xml_xsd_test}"
DB_USER="${POSTGRES_USER:-globalhealth}"
XML_DIR="database/postgres/xml"
XSD_FILE="$XML_DIR/schemas/clinical-record-v1.xsd"

if [ -n "${XML_XSD_PSQL:-}" ]; then
    run_admin() {
        PGPASSWORD="${POSTGRES_PASSWORD:-change-me}" $XML_XSD_PSQL -v ON_ERROR_STOP=1 -d postgres "$@"
    }
    run_file() {
        sql_file="$1"
        shift
        PGPASSWORD="${POSTGRES_PASSWORD:-change-me}" $XML_XSD_PSQL -v ON_ERROR_STOP=1 -d "$DB_NAME" "$@" -f "$sql_file"
    }
else
    compose() {
        if [ -n "${XML_XSD_COMPOSE_PROJECT:-}" ]; then
            docker compose -p "$XML_XSD_COMPOSE_PROJECT" "$@"
        else
            docker compose "$@"
        fi
    }
    compose up -d --wait --wait-timeout 120 postgres-primary
    run_admin() {
        compose exec -T postgres-primary psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres "$@"
    }
    run_file() {
        sql_file="$1"
        shift
        compose exec -T postgres-primary psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" "$@" < "$sql_file"
    }
fi

cleanup() {
    run_admin -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
    run_admin -c "DROP DATABASE IF EXISTS $DB_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "==> Creating test database $DB_NAME"
cleanup
run_admin -c "CREATE DATABASE $DB_NAME"

for file in 01_schema_registry.sql 02_clinical_records.sql 03_xml_operations.sql; do
    echo "==> $file"
    run_file "$XML_DIR/$file"
done

echo "==> 04_tests.sql"
XSD_CONTENT=$(sed "s/'/''/g" "$XSD_FILE")
run_file "$XML_DIR/04_tests.sql" -v xsd_content="$XSD_CONTENT"

echo "All XML/XSD tests passed."
