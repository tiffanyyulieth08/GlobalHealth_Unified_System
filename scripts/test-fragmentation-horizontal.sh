#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

DB_USER="${POSTGRES_USER:-globalhealth}"
NORTH_DB="${FRAGMENT_NORTH_DB:-globalhealth_north}"
SOUTH_DB="${FRAGMENT_SOUTH_DB:-globalhealth_south}"
COORDINATOR_DB="${FRAGMENT_HORIZONTAL_COORDINATOR_DB:-globalhealth_horizontal}"

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

compose up -d --build --wait --wait-timeout 180 fragment-north fragment-south fragmentation-coordinator-horizontal

echo "==> Limpiando y sembrando datos de prueba"
query fragment-north "$DB_USER" "$NORTH_DB" "TRUNCATE TABLE patients" >/dev/null
query fragment-south "$DB_USER" "$SOUTH_DB" "TRUNCATE TABLE patients" >/dev/null
compose exec -T fragment-north psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$NORTH_DB" < database/postgres/fragmentation/horizontal/north/03_seed.sql >/dev/null
compose exec -T fragment-south psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$SOUTH_DB" < database/postgres/fragmentation/horizontal/south/03_seed.sql >/dev/null

echo "==> Datos semilla"
NORTH_COUNT="$(query fragment-north "$DB_USER" "$NORTH_DB" "SELECT count(*) FROM patients")"
assert_eq "$NORTH_COUNT" "3" "fragment-north semilla 3 registros"

SOUTH_COUNT="$(query fragment-south "$DB_USER" "$SOUTH_DB" "SELECT count(*) FROM patients")"
assert_eq "$SOUTH_COUNT" "3" "fragment-south semilla 3 registros"

echo "==> Restricciones CHECK por region"
NORTH_REGIONS="$(query fragment-north "$DB_USER" "$NORTH_DB" "SELECT count(*) FROM patients WHERE region = 'NORTH'")"
assert_eq "$NORTH_REGIONS" "3" "fragment-north solo region NORTH"

SOUTH_REGIONS="$(query fragment-south "$DB_USER" "$SOUTH_DB" "SELECT count(*) FROM patients WHERE region = 'SOUTH'")"
assert_eq "$SOUTH_REGIONS" "3" "fragment-south solo region SOUTH"

echo "==> Enrutamiento de inserciones por region"
query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT insert_patient(6, 'Pablo Norte', '555-3006', 'pablo.norte@example.com', 'Calle 6 #15-25', 'NORTH')" >/dev/null
assert_eq "$(query fragment-north "$DB_USER" "$NORTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 6")" "1" "enrutamiento NORTH inserta en fragment-north"
assert_eq "$(query fragment-south "$DB_USER" "$SOUTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 6")" "0" "enrutamiento NORTH no toca fragment-south"

query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT insert_patient(7, 'Lucia Sur', '555-3007', 'lucia.sur@example.com', 'Calle 7 #16-26', 'SOUTH')" >/dev/null
assert_eq "$(query fragment-south "$DB_USER" "$SOUTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 7")" "1" "enrutamiento SOUTH inserta en fragment-south"
assert_eq "$(query fragment-north "$DB_USER" "$NORTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 7")" "0" "enrutamiento SOUTH no toca fragment-north"

echo "==> Insercion correcta en Norte"
query fragment-north "$DB_USER" "$NORTH_DB" "INSERT INTO patients (patient_id, full_name, phone, email, address, region) VALUES (20, 'Ruth Nino', '555-3020', 'ruth.nino@example.com', 'Calle 20 #15-40', 'NORTH')" >/dev/null
assert_eq "$(query fragment-north "$DB_USER" "$NORTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 20")" "1" "paciente NORTH insertado en fragment-north"

echo "==> Insercion correcta en Sur"
query fragment-south "$DB_USER" "$SOUTH_DB" "INSERT INTO patients (patient_id, full_name, phone, email, address, region) VALUES (21, 'Pedro Sur', '555-3021', 'pedro.sur@example.com', 'Calle 21 #16-41', 'SOUTH')" >/dev/null
assert_eq "$(query fragment-south "$DB_USER" "$SOUTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 21")" "1" "paciente SOUTH insertado en fragment-south"

echo "==> Rechazo en el nodo equivocado"
if query fragment-north "$DB_USER" "$NORTH_DB" "INSERT INTO patients (patient_id, full_name, phone, email, address, region) VALUES (30, 'Nodo Equivocado', '555-3030', 'equivocado@example.com', 'Calle 30 #15-50', 'SOUTH')" >/dev/null 2>&1; then
    fail "fragment-north debe rechazar un paciente con region SOUTH"
fi
echo "OK: fragment-north rechaza insercion con region SOUTH"

if query fragment-south "$DB_USER" "$SOUTH_DB" "INSERT INTO patients (patient_id, full_name, phone, email, address, region) VALUES (31, 'Nodo Equivocado', '555-3031', 'equivocado2@example.com', 'Calle 31 #16-51', 'NORTH')" >/dev/null 2>&1; then
    fail "fragment-south debe rechazar un paciente con region NORTH"
fi
echo "OK: fragment-south rechaza insercion con region NORTH"

echo "==> Deteccion de patient_id duplicado entre nodos"
DUPLICATES="$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT patient_id FROM patients_north INTERSECT SELECT patient_id FROM patients_south ORDER BY patient_id")"
assert_eq "$DUPLICATES" "1" "patient_id 1 duplicado entre nodos"

echo "==> Reconstruccion global mediante UNION ALL"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all")" "10" "reconstruccion global 10 registros"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE region = 'NORTH'")" "5" "reconstruccion global 5 NORTH"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE region = 'SOUTH'")" "5" "reconstruccion global 5 SOUTH"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE patient_id = 6")" "1" "reconstruccion incluye paciente 6 (NORTH)"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE patient_id = 7")" "1" "reconstruccion incluye paciente 7 (SOUTH)"

echo "All fragmentation horizontal tests passed."
