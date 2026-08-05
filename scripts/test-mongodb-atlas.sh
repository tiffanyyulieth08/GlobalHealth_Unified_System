#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

if [ -z "${MONGODB_URI:-}" ]; then
    echo "BLOCKED: MONGODB_URI de Atlas no proporcionada."
    exit 2
fi

case "$MONGODB_URI" in
    mongodb+srv://*) ;;
    *)
        echo "BLOCKED: MONGODB_URI no es una URI mongodb+srv de Atlas."
        exit 2
        ;;
esac

for tool in docker mongosh curl python; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "BLOCKED: $tool es requerido para validar Atlas."
        exit 2
    fi
done

RUN_ID="$(date +%Y%m%d%H%M%S)-$$"
MONGODB_DB="gh_atlas_${RUN_ID}"
PROJECT_NAME="globalhealth-atlas-validation-$$"
APP_PORT="${ATLAS_VALIDATION_PORT:-18081}"
BASE_URL="http://localhost:$APP_PORT"
TEMP_ROOT="${TMPDIR:-/tmp}"
TEMP_DIR="$(mktemp -d "$TEMP_ROOT/globalhealth-atlas.XXXXXX")"
MONGO_OUTPUT="$TEMP_DIR/mongosh-output.txt"
COMPOSE_OUTPUT="$TEMP_DIR/compose-output.txt"
HEALTH_OUTPUT="$TEMP_DIR/health.json"

export MONGODB_PROVIDER="atlas"
export MONGODB_DB
export APP_PORT
export APP_ENV="production"
export APP_DEBUG="false"
export POSTGRES_DB="globalhealth_atlas_validation"
export POSTGRES_USER="globalhealth_atlas_validation"
export POSTGRES_PASSWORD="atlas-validation-postgres-$RUN_ID"
export POSTGRES_REPLICATION_USER="atlas_validation_replicator"
export POSTGRES_REPLICATION_PASSWORD="atlas-validation-replication-$RUN_ID"

compose() {
    docker compose -p "$PROJECT_NAME" -f compose.yaml -f compose.atlas.yaml "$@"
}

cleanup() {
    case "$MONGODB_DB" in
        gh_atlas_*)
            mongosh "$MONGODB_URI" --quiet \
                --eval "db.getSiblingDB('$MONGODB_DB').dropDatabase()" \
                >"$MONGO_OUTPUT" 2>&1 || true
            ;;
    esac
    compose down -v --remove-orphans >"$COMPOSE_OUTPUT" 2>&1 || true
    case "$TEMP_DIR" in
        "$TEMP_ROOT"/globalhealth-atlas.*)
            rm -rf "$TEMP_DIR"
            ;;
    esac
}

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

trap cleanup EXIT INT TERM

echo "==> Validando operaciones Atlas en una base temporal"
if ! mongosh "$MONGODB_URI" --quiet \
    --file database/mongodb/01_collections.js \
    >"$MONGO_OUTPUT" 2>&1; then
    fail "no se pudieron crear colecciones e índices en Atlas"
fi
if ! mongosh "$MONGODB_URI" --quiet \
    --file database/mongodb/atlas_validation.js \
    >"$MONGO_OUTPUT" 2>&1; then
    fail "falló CRUD, agregación o lookup en Atlas"
fi
echo "OK: colecciones, índices, CRUD, agregación y lookup"

echo "==> Iniciando backend en modo Atlas sin el servicio MongoDB local"
if ! compose up -d --build --wait --wait-timeout 240 backend \
    >"$COMPOSE_OUTPUT" 2>&1; then
    fail "el backend no inició en modo Atlas"
fi

if ! curl --silent --show-error --fail \
    "$BASE_URL/api/mongodb/health" \
    --output "$HEALTH_OUTPUT" 2>"$TEMP_DIR/curl-error.txt"; then
    fail "el endpoint de salud de MongoDB no respondió"
fi

if ! python - "$HEALTH_OUTPUT" "$MONGODB_DB" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as health_file:
    payload = json.load(health_file)

expected = {
    "status": "healthy",
    "provider": "atlas",
    "database": sys.argv[2],
}
if payload != expected:
    raise SystemExit(1)
PY
then
    fail "el endpoint de salud no devolvió la respuesta sanitizada esperada"
fi

echo "OK: health status=healthy provider=atlas database=base_temporal"
echo "PASS: validación real de MongoDB Atlas completada sin exponer la URI."
