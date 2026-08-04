#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

DB_NAME="${MOR_DB:-globalhealth_mor_test}"
DB_USER="${POSTGRES_USER:-globalhealth}"
MOR_DIR="database/postgres/mor"

if [ -n "${MOR_PSQL:-}" ]; then
    run_admin() {
        PGPASSWORD="${POSTGRES_PASSWORD:-change-me}" $MOR_PSQL -v ON_ERROR_STOP=1 -d postgres "$@"
    }
    run_file() {
        PGPASSWORD="${POSTGRES_PASSWORD:-change-me}" $MOR_PSQL -v ON_ERROR_STOP=1 -d "$DB_NAME" -f "$1"
    }
else
    compose() {
        if [ -n "${MOR_COMPOSE_PROJECT:-}" ]; then
            docker compose -p "$MOR_COMPOSE_PROJECT" "$@"
        else
            docker compose "$@"
        fi
    }
    compose up -d --wait --wait-timeout 120 postgres-primary
    run_admin() {
        compose exec -T postgres-primary psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres "$@"
    }
    run_file() {
        compose exec -T postgres-primary psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" < "$1"
    }
fi

echo "==> Creating test database $DB_NAME"
run_admin -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
run_admin -c "DROP DATABASE IF EXISTS $DB_NAME"
run_admin -c "CREATE DATABASE $DB_NAME"

for f in 01_types.sql 02_tables.sql 03_functions.sql 04_seed.sql 05_crud.sql; do
    echo "==> $f"
    run_file "$MOR_DIR/$f"
done

echo "==> 06_tests.sql"
run_file "$MOR_DIR/06_tests.sql"

echo "==> Cleaning up test database"
run_admin -c "DROP DATABASE IF EXISTS $DB_NAME"

echo "All MOR tests passed."
