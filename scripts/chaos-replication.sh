#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

DB_NAME="${POSTGRES_DB:-globalhealth}"
DB_USER="${POSTGRES_USER:-globalhealth}"
APP_PORT="${APP_PORT:-8000}"
BASE_URL="${CHAOS_BASE_URL:-http://localhost:$APP_PORT}"
EVIDENCE_DIR="${CHAOS_EVIDENCE_DIR:-docs/evidence/replication-chaos}"
MAX_ATTEMPTS="${CHAOS_MAX_ATTEMPTS:-60}"
HTTP_TIMEOUT="${CHAOS_HTTP_TIMEOUT:-15}"
PROBE_ID="chaos-$(date +%s)-$$"
PRIMARY_NEEDS_RESTART=0

compose() {
    if [ -n "${CHAOS_COMPOSE_PROJECT:-}" ]; then
        docker compose -p "$CHAOS_COMPOSE_PROJECT" "$@"
    else
        docker compose "$@"
    fi
}

primary_query() {
    compose exec -T postgres-primary \
        psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -tAc "$1"
}

replica_query() {
    compose exec -T postgres-replica \
        psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" -tAc "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    actual="$1"
    expected="$2"
    label="$3"
    if [ "$actual" != "$expected" ]; then
        fail "$label: se obtuvo '$actual', se esperaba '$expected'"
    fi
    printf 'OK: %s\n' "$label"
}

wait_for_primary() {
    attempt=1
    while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
        state="$(primary_query "SELECT pg_is_in_recovery()" 2>/dev/null || true)"
        if [ "$state" = "f" ]; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    return 1
}

restore_primary() {
    original_status=$?
    trap - EXIT INT TERM
    if [ "$PRIMARY_NEEDS_RESTART" = "1" ]; then
        set +e
        printf '==> Restaurando postgres-primary desde el trap de salida\n'
        mkdir -p "$EVIDENCE_DIR"
        compose start postgres-primary > "$EVIDENCE_DIR/99-emergency-restoration.txt" 2>&1
        wait_for_primary
        restore_status=$?
        printf 'primary_recovered=%s\n' "$(
            if [ "$restore_status" -eq 0 ]; then
                printf 'true'
            else
                printf 'false'
            fi
        )" >> "$EVIDENCE_DIR/99-emergency-restoration.txt"
        set -e
        if [ "$restore_status" -ne 0 ]; then
            printf 'FAIL: postgres-primary no se recupero durante la restauracion final\n' >&2
            exit 1
        fi
    fi
    exit "$original_status"
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap restore_primary EXIT

mkdir -p "$EVIDENCE_DIR"

printf '==> Comprobando salud inicial de Primary, Replica y backend\n'
compose up -d --build --wait --wait-timeout 180 backend
assert_eq "$(primary_query "SELECT pg_is_in_recovery()")" "f" "Primary esta saludable y acepta escrituras"
assert_eq "$(replica_query "SELECT pg_is_in_recovery()")" "t" "Replica esta saludable y permanece en recovery"

INITIAL_HTTP="$(
    curl --silent --show-error \
        --max-time "$HTTP_TIMEOUT" \
        --output "$EVIDENCE_DIR/01-initial-health.json" \
        --write-out '%{http_code}' \
        "$BASE_URL/health/databases" || true
)"
assert_eq "$INITIAL_HTTP" "200" "health/databases responde HTTP 200"
printf 'http_status=%s\n' "$INITIAL_HTTP" > "$EVIDENCE_DIR/01-initial-health-http.txt"

printf '==> Insertando dato en Primary\n'
primary_query "
    CREATE TABLE IF NOT EXISTS chaos_replication_probe (
        probe_id text PRIMARY KEY,
        created_at timestamptz NOT NULL DEFAULT current_timestamp
    );
    INSERT INTO chaos_replication_probe (probe_id) VALUES ('$PROBE_ID');
" > "$EVIDENCE_DIR/02-primary-insert.txt"
printf 'probe_id=%s\n' "$PROBE_ID" >> "$EVIDENCE_DIR/02-primary-insert.txt"

printf '==> Esperando el dato en Replica\n'
attempt=1
replicated="f"
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    replicated="$(
        replica_query "
            SELECT EXISTS (
                SELECT 1
                FROM chaos_replication_probe
                WHERE probe_id = '$PROBE_ID'
            )
        " 2>/dev/null || true
    )"
    if [ "$replicated" = "t" ]; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done
assert_eq "$replicated" "t" "el dato insertado llego a Replica"
printf 'probe_id=%s\nreplicated=true\nattempts=%s\n' \
    "$PROBE_ID" "$attempt" > "$EVIDENCE_DIR/03-replica-observation.txt"

printf '==> Deteniendo postgres-primary sin eliminar volumenes\n'
PRIMARY_NEEDS_RESTART=1
compose stop postgres-primary > "$EVIDENCE_DIR/04-primary-stop.txt" 2>&1

printf '==> Consultando dashboard durante la caida de Primary\n'
DASHBOARD_HTTP="$(
    curl --silent --show-error \
        --max-time "$HTTP_TIMEOUT" \
        --output "$EVIDENCE_DIR/05-dashboard-replica.json" \
        --write-out '%{http_code}' \
        "$BASE_URL/dashboard" || true
)"
assert_eq "$DASHBOARD_HTTP" "200" "dashboard responde HTTP 200 desde Replica"
printf 'http_status=%s\n' "$DASHBOARD_HTTP" > "$EVIDENCE_DIR/05-dashboard-http.txt"
grep -Fq '"source":"replica"' "$EVIDENCE_DIR/05-dashboard-replica.json" \
    || fail "dashboard no declara Replica como fuente"
grep -Fq '"in_recovery":true' "$EVIDENCE_DIR/05-dashboard-replica.json" \
    || fail "dashboard no confirma que la fuente esta en recovery"

printf '==> Intentando escritura HTTP con Primary detenido\n'
WRITE_HTTP="$(
    curl --silent --show-error \
        --max-time "$HTTP_TIMEOUT" \
        --request POST \
        --output "$EVIDENCE_DIR/06-rejected-write.json" \
        --write-out '%{http_code}' \
        "$BASE_URL/chaos/replication/write?probe_id=$PROBE_ID-unavailable" || true
)"
assert_eq "$WRITE_HTTP" "503" "la escritura responde HTTP 503"
printf 'http_status=%s\n' "$WRITE_HTTP" > "$EVIDENCE_DIR/06-rejected-write-http.txt"

printf '==> Reiniciando postgres-primary\n'
compose start postgres-primary > "$EVIDENCE_DIR/07-primary-start.txt" 2>&1
wait_for_primary || fail "postgres-primary no se recupero"
PRIMARY_NEEDS_RESTART=0
printf 'primary_in_recovery=false\n' > "$EVIDENCE_DIR/08-primary-recovery.txt"

printf '==> Esperando que la replicacion vuelva a streaming\n'
attempt=1
primary_streaming="f"
replica_streaming="f"
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    primary_streaming="$(
        primary_query "
            SELECT EXISTS (
                SELECT 1
                FROM pg_stat_replication
                WHERE state = 'streaming'
            )
        " 2>/dev/null || true
    )"
    replica_streaming="$(
        replica_query "
            SELECT EXISTS (
                SELECT 1
                FROM pg_stat_wal_receiver
                WHERE status = 'streaming'
            )
        " 2>/dev/null || true
    )"
    if [ "$primary_streaming" = "t" ] && [ "$replica_streaming" = "t" ]; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done
assert_eq "$primary_streaming" "t" "Primary reporta una conexion de replicacion streaming"
assert_eq "$replica_streaming" "t" "Replica reporta WAL receiver streaming"

{
    printf 'primary_streaming=%s\n' "$primary_streaming"
    printf 'replica_streaming=%s\n' "$replica_streaming"
    printf 'attempts=%s\n' "$attempt"
    primary_query "
        SELECT application_name || '|' || state || '|' || sync_state
        FROM pg_stat_replication
        ORDER BY application_name
    "
    replica_query "
        SELECT status || '|' || sender_host || '|' || sender_port
        FROM pg_stat_wal_receiver
    "
} > "$EVIDENCE_DIR/09-streaming-restored.txt"

printf 'All replication chaos checks passed.\n'
