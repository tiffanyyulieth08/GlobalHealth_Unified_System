#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

DB_USER="${POSTGRES_USER:-globalhealth}"
PUBLIC_DB="${FRAGMENT_PUBLIC_DB:-globalhealth_public}"
FINANCIAL_DB="${FRAGMENT_FINANCIAL_DB:-globalhealth_financial}"
COORDINATOR_DB="${FRAGMENT_COORDINATOR_DB:-globalhealth}"

compose() {
    if [ -n "${FRAGMENTATION_COMPOSE_PROJECT:-}" ]; then
        docker compose -p "$FRAGMENTATION_COMPOSE_PROJECT" "$@"
    else
        docker compose "$@"
    fi
}

query() {
    compose exec -T "$1" psql -v ON_ERROR_STOP=1 -U "$2" -d "$3" -tAc "$4"
}

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_eq() {
    actual="$1"
    expected="$2"
    label="$3"
    if [ "$actual" != "$expected" ]; then
        fail "$label: got '$actual', expected '$expected'"
    fi
    echo "OK: $label -> $actual"
}

public_orphans() {
    query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "
        SELECT count(*) FROM (
            SELECT p.patient_id
            FROM patients_public p
            LEFT JOIN patients_financial f USING (patient_id)
            WHERE f.patient_id IS NULL
        ) orphans"
}

financial_orphans() {
    query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "
        SELECT count(*) FROM (
            SELECT f.patient_id
            FROM patients_financial f
            LEFT JOIN patients_public p USING (patient_id)
            WHERE p.patient_id IS NULL
        ) orphans"
}

# Crea temporalmente un registro solo en un fragmento (huerfano), lo detecta
# desde el coordinador dentro de la misma transaccion y revierte con ROLLBACK.
# Si el huerfano no se detecta, la suite falla con FAIL.
expect_public_orphan_rejected() {
    label="$1"
    out="$(
        compose exec -T fragmentation-coordinator \
            psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$COORDINATOR_DB" <<SQL 2>&1 || true
BEGIN;
INSERT INTO patients_public (patient_id, full_name) VALUES (99, 'Orfan Publico');
DO \$\$
DECLARE
    v_orphans integer;
BEGIN
    SELECT count(*) INTO v_orphans FROM (
        SELECT p.patient_id
        FROM patients_public p
        LEFT JOIN patients_financial f USING (patient_id)
        WHERE f.patient_id IS NULL
    ) o;
    IF v_orphans <> 1 THEN
        RAISE EXCEPTION 'FAIL: huerfano publico no detectado (v_orphans=%)', v_orphans;
    END IF;
    RAISE NOTICE 'ORPHAN_PUBLIC_DETECTED';
END
\$\$;
ROLLBACK;
SQL
    )"
    if ! printf '%s\n' "$out" | grep -Fq "ORPHAN_PUBLIC_DETECTED"; then
        fail "$label"
    fi
    echo "OK: $label"
}

expect_financial_orphan_rejected() {
    label="$1"
    out="$(
        compose exec -T fragmentation-coordinator \
            psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$COORDINATOR_DB" <<SQL 2>&1 || true
BEGIN;
INSERT INTO patients_financial (patient_id, insurance_provider) VALUES (99, 'Orfan Financiero');
DO \$\$
DECLARE
    v_orphans integer;
BEGIN
    SELECT count(*) INTO v_orphans FROM (
        SELECT f.patient_id
        FROM patients_financial f
        LEFT JOIN patients_public p USING (patient_id)
        WHERE p.patient_id IS NULL
    ) o;
    IF v_orphans <> 1 THEN
        RAISE EXCEPTION 'FAIL: huerfano financiero no detectado (v_orphans=%)', v_orphans;
    END IF;
    RAISE NOTICE 'ORPHAN_FINANCIAL_DETECTED';
END
\$\$;
ROLLBACK;
SQL
    )"
    if ! printf '%s\n' "$out" | grep -Fq "ORPHAN_FINANCIAL_DETECTED"; then
        fail "$label"
    fi
    echo "OK: $label"
}

compose up -d --build --wait --wait-timeout 180 fragment-public fragment-financial fragmentation-coordinator

echo "==> Datos en los fragmentos (mismos patient_id en ambos)"
PUBLIC_COUNT="$(query fragment-public "$DB_USER" "$PUBLIC_DB" "SELECT count(*) FROM patients_public")"
assert_eq "$PUBLIC_COUNT" "6" "fragment-public contiene 6 registros"

FINANCIAL_COUNT="$(query fragment-financial "$DB_USER" "$FINANCIAL_DB" "SELECT count(*) FROM patients_financial")"
assert_eq "$FINANCIAL_COUNT" "6" "fragment-financial contiene 6 registros"

echo "==> Roles de fragmento"
PUBLIC_ROLE_COUNT="$(query fragment-public public_role "$PUBLIC_DB" "SELECT count(*) FROM patients_public")"
assert_eq "$PUBLIC_ROLE_COUNT" "6" "public_role lee datos publicos"

FINANCIAL_ROLE_COUNT="$(query fragment-financial financial_role "$FINANCIAL_DB" "SELECT count(*) FROM patients_financial")"
assert_eq "$FINANCIAL_ROLE_COUNT" "6" "financial_role lee datos financieros"

if query fragment-financial public_role "$FINANCIAL_DB" "SELECT count(*) FROM patients_financial" >/dev/null 2>&1; then
    fail "public_role no debe leer datos financieros en fragment-financial"
fi
echo "OK: public_role no puede leer datos financieros en fragment-financial"

echo "==> Coordinador con postgres_fdw"
COORD_PUBLIC_COUNT="$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_public")"
assert_eq "$COORD_PUBLIC_COUNT" "6" "coordinador lee tabla remota publica"

COORD_FINANCIAL_COUNT="$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_financial")"
assert_eq "$COORD_FINANCIAL_COUNT" "6" "coordinador lee tabla remota financiera"

echo "==> Conjuntos de llaves identicos en estado normal"
assert_eq "$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "SELECT patient_id FROM patients_public EXCEPT SELECT patient_id FROM patients_financial")" "" "EXCEPT publico menos financiero vacio"
assert_eq "$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "SELECT patient_id FROM patients_financial EXCEPT SELECT patient_id FROM patients_public")" "" "EXCEPT financiero menos publico vacio"
assert_eq "$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "SELECT (SELECT count(*) FROM patients_public) - (SELECT count(*) FROM patients_financial)")" "0" "cantidad de llaves publicas igual a financieras"
assert_eq "$(public_orphans)" "0" "sin huerfanos publicos en el estado normal"
assert_eq "$(financial_orphans)" "0" "sin huerfanos financieros en el estado normal"

echo "==> Reconstruccion completa del paciente"
RECON_COUNT="$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_full")"
assert_eq "$RECON_COUNT" "6" "patients_full reconstruye 6 pacientes completos"

RECON_COMPLETE="$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "
    SELECT count(*) FROM patients_full
    WHERE full_name IS NULL
       OR phone IS NULL
       OR email IS NULL
       OR address IS NULL
       OR emergency_contact IS NULL
       OR insurance_provider IS NULL
       OR insurance_number IS NULL
       OR billing_status IS NULL
       OR outstanding_balance IS NULL
       OR payment_method IS NULL
")"
assert_eq "$RECON_COMPLETE" "0" "reconstruccion sin columnas faltantes"

RECON_SAMPLE="$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "
    SELECT full_name || ':' || insurance_provider || ':' || outstanding_balance::text
    FROM patients_full
    WHERE patient_id = 2
")"
assert_eq "$RECON_SAMPLE" "Luis Ramirez:VidaPlus:250.75" "paciente 2 reconstruido con datos publicos y financieros"

echo "==> Huerfanos como pruebas negativas temporales (ROLLBACK)"
expect_public_orphan_rejected "huerfano publico detectado y revertido (ROLLBACK)"
expect_financial_orphan_rejected "huerfano financiero detectado y revertido (ROLLBACK)"
assert_eq "$(public_orphans)" "0" "sin rastros de huerfano publico tras ROLLBACK"
assert_eq "$(financial_orphans)" "0" "sin rastros de huerfano financiero tras ROLLBACK"
assert_eq "$(query fragmentation-coordinator "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_full")" "6" "reconstruccion intacta tras las negativas"

echo "==> Restriccion del rol publico en el coordinador"
COORD_PUBLIC_ROLE_COUNT="$(query fragmentation-coordinator public_role "$COORDINATOR_DB" "SELECT count(*) FROM patients_public")"
assert_eq "$COORD_PUBLIC_ROLE_COUNT" "6" "public_role en coordinador lee datos publicos"

if query fragmentation-coordinator public_role "$COORDINATOR_DB" "SELECT count(*) FROM patients_financial" >/dev/null 2>&1; then
    fail "public_role no debe leer la tabla remota financiera desde el coordinador"
fi
echo "OK: public_role no puede leer informacion financiera desde el coordinador"

echo "All fragmentation vertical tests passed."
