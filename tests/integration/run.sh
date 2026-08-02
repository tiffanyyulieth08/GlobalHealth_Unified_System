#!/bin/sh
set -eu

cd "$(dirname "$0")/../.."

RUN_ID="${INTEGRATION_RUN_ID:-$(date +%s)-$$}"
PROJECT_NAME="${INTEGRATION_COMPOSE_PROJECT:-globalhealth-integration-$RUN_ID}"
APP_PORT="${INTEGRATION_APP_PORT:-18080}"
BASE_URL="http://localhost:$APP_PORT"
EVIDENCE_DIR="${INTEGRATION_EVIDENCE_DIR:-docs/evidence/integration}"
DB_USER="globalhealth_integration"
DB_NAME="globalhealth_integration"
MONGO_DB="globalhealth_integration"
SCHEMA_NAME="integration_test"

export APP_PORT
export POSTGRES_DB="$DB_NAME"
export POSTGRES_USER="$DB_USER"
export POSTGRES_PASSWORD="pg-$RUN_ID-integration-secret"
export POSTGRES_REPLICATION_USER="replicator_integration"
export POSTGRES_REPLICATION_PASSWORD="replication-$RUN_ID-integration-secret"
export FRAGMENT_FDW_PASSWORD="vertical-$RUN_ID-integration-secret"
export FRAGMENT_HORIZONTAL_FDW_PASSWORD="horizontal-$RUN_ID-integration-secret"
export MONGODB_DB="$MONGO_DB"
export MONGODB_URI="mongodb://mongodb:27017/$MONGO_DB"

compose() {
    docker compose -p "$PROJECT_NAME" "$@"
}

cleanup() {
    if [ "${KEEP_INTEGRATION_ENV:-0}" != "1" ]; then
        compose down -v --remove-orphans >/dev/null 2>&1 || true
    fi
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

require_text() {
    file="$1"
    value="$2"
    label="$3"
    grep -Fq "$value" "$file" || fail "$label"
    printf 'OK: %s\n' "$label"
}

primary_query() {
    compose exec -T postgres-primary \
        psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -tAc "$1"
}

primary_file() {
    sql_file="$1"
    shift
    compose exec -T \
        -e "PGOPTIONS=-c search_path=$SCHEMA_NAME,public" \
        postgres-primary \
        psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" "$@" < "$sql_file"
}

api_post() {
    route="$1"
    payload="$2"
    output="$3"
    curl --silent --show-error --fail-with-body \
        -H "Content-Type: application/json" \
        --data "$payload" \
        "$BASE_URL$route" \
        --output "$output"
}

trap cleanup EXIT INT TERM
mkdir -p "$EVIDENCE_DIR"

printf '==> Iniciando PostgreSQL Primary/Replica, MongoDB y backend\n'
compose up -d --build --wait --wait-timeout 240 backend

printf '==> Preparando MOR y XML/XSD en PostgreSQL Primary\n'
primary_query "DROP SCHEMA IF EXISTS $SCHEMA_NAME CASCADE; CREATE SCHEMA $SCHEMA_NAME" >/dev/null
for file in \
    database/postgres/mor/01_types.sql \
    database/postgres/mor/02_tables.sql \
    database/postgres/xml/01_schema_registry.sql \
    database/postgres/xml/02_clinical_records.sql \
    database/postgres/xml/03_xml_operations.sql
do
    primary_file "$file" >/dev/null
done

XSD_CONTENT="$(sed "s/'/''/g" database/postgres/xml/schemas/clinical-record-v1.xsd)"
primary_file tests/integration/postgres_flow.sql \
    -v "xsd_content=$XSD_CONTENT" > "$EVIDENCE_DIR/postgresql.txt"
cat "$EVIDENCE_DIR/postgresql.txt"

printf '==> Preparando colecciones de telemetria en MongoDB\n'
compose cp database/mongodb/01_collections.js mongodb:/tmp/integration-collections.js >/dev/null
compose exec -T -e "MONGODB_DB=$MONGO_DB" mongodb \
    mongosh "mongodb://localhost:27017/$MONGO_DB" \
    --quiet --file /tmp/integration-collections.js > "$EVIDENCE_DIR/mongodb-setup.txt"

printf '==> Creando paciente, sesion y logs de sensores\n'
api_post "/api/patients" \
    '{"patientId":"INT-P001","firstName":"Paciente","lastName":"Integracion","dateOfBirth":"1992-05-14T00:00:00Z","sex":"unknown","active":true}' \
    "$EVIDENCE_DIR/patient.json"
api_post "/api/sessions" \
    '{"sessionId":"INT-S001","patientId":"INT-P001","deviceId":"INT-DEVICE-01","startedAt":"2026-08-01T15:00:00Z","status":"active"}' \
    "$EVIDENCE_DIR/session.json"
api_post "/api/sensor-logs" \
    '{"logId":"INT-L001","sessionId":"INT-S001","patientId":"INT-P001","sensorType":"heart_rate","value":72,"unit":"bpm","recordedAt":"2026-08-01T15:01:00Z"}' \
    "$EVIDENCE_DIR/sensor-log-1.json"
api_post "/api/sensor-logs" \
    '{"logId":"INT-L002","sessionId":"INT-S001","patientId":"INT-P001","sensorType":"oxygen_saturation","value":98,"unit":"percent","recordedAt":"2026-08-01T15:02:00Z"}' \
    "$EVIDENCE_DIR/sensor-log-2.json"

require_text "$EVIDENCE_DIR/patient.json" '"patientId":"INT-P001"' "paciente creado en MongoDB"
require_text "$EVIDENCE_DIR/session.json" '"sessionId":"INT-S001"' "sesion creada"
require_text "$EVIDENCE_DIR/sensor-log-1.json" '"logId":"INT-L001"' "primer log de sensor insertado"
require_text "$EVIDENCE_DIR/sensor-log-2.json" '"logId":"INT-L002"' "segundo log de sensor insertado"

printf '==> Ejecutando lookup paciente -> sesiones -> logs\n'
curl --silent --show-error --fail-with-body \
    "$BASE_URL/api/patients/INT-P001/telemetry" \
    --output "$EVIDENCE_DIR/lookup.json"
require_text "$EVIDENCE_DIR/lookup.json" '"sessionId":"INT-S001"' "lookup incluye la sesion"
require_text "$EVIDENCE_DIR/lookup.json" '"logId":"INT-L001"' "lookup incluye el primer log"
require_text "$EVIDENCE_DIR/lookup.json" '"logId":"INT-L002"' "lookup incluye el segundo log"

printf '==> Consultando dashboard desde PostgreSQL Replica\n'
curl --silent --show-error --fail-with-body \
    "$BASE_URL/dashboard" \
    --output "$EVIDENCE_DIR/dashboard.json"
require_text "$EVIDENCE_DIR/dashboard.json" '"source":"replica"' "dashboard declara la replica como fuente"
require_text "$EVIDENCE_DIR/dashboard.json" '"in_recovery":true' "dashboard se ejecuto en hot standby"
require_text "$EVIDENCE_DIR/dashboard.json" '"database_name":"globalhealth_integration"' "dashboard consulta la base integral"

printf '==> Reconstruyendo fragmentacion horizontal\n'
FRAGMENTATION_COMPOSE_PROJECT="$PROJECT_NAME" \
    sh scripts/test-fragmentation-horizontal.sh > "$EVIDENCE_DIR/fragmentation-horizontal.txt"
cat "$EVIDENCE_DIR/fragmentation-horizontal.txt"

printf '==> Reconstruyendo fragmentacion vertical\n'
FRAGMENTATION_COMPOSE_PROJECT="$PROJECT_NAME" \
    sh scripts/test-fragmentation-vertical.sh > "$EVIDENCE_DIR/fragmentation-vertical.txt"
cat "$EVIDENCE_DIR/fragmentation-vertical.txt"

printf '==> Verificando que no se expongan credenciales\n'
compose logs --no-color backend > "$EVIDENCE_DIR/backend.txt"
for secret in \
    "$POSTGRES_PASSWORD" \
    "$POSTGRES_REPLICATION_PASSWORD" \
    "$FRAGMENT_FDW_PASSWORD" \
    "$FRAGMENT_HORIZONTAL_FDW_PASSWORD"
do
    if grep -Fq "$secret" "$EVIDENCE_DIR"/*; then
        fail "se encontro una credencial en las evidencias o logs"
    fi
done

if grep -Eiq \
    '"(password|secret|credential)"|postgres(ql)?://[^[:space:]]+@|mongodb(\+srv)?://[^[:space:]]+@' \
    "$EVIDENCE_DIR"/*; then
    fail "se encontro material con formato de credencial"
fi
printf 'OK: respuestas y logs no exponen credenciales\n' > "$EVIDENCE_DIR/security.txt"
cat "$EVIDENCE_DIR/security.txt"

printf 'All integration tests passed.\n'
