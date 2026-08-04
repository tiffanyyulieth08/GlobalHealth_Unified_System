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

# Inserta un paciente mediante la ruta normal (insert_patient via coordinador).
insert_patient() {
    pid="$1"
    name="$2"
    phone="$3"
    email="$4"
    address="$5"
    region="$6"
    query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" \
        "SELECT insert_patient($pid, '$name', '$phone', '$email', '$address', '$region')" >/dev/null
}

# Ejecuta insert_patient esperando que la base la rechace. La operacion ocurre
# dentro de una transaccion de prueba que termina en ROLLBACK; la deteccion se
# demuestra por una marca emitida por la base, no por el texto de la shell.
expect_insert_patient_rejected() {
    label="$1"
    pid="$2"
    region="$3"
    out="$(
        compose exec -T fragmentation-coordinator-horizontal \
            psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$COORDINATOR_DB" <<SQL 2>&1 || true
BEGIN;
DO \$\$
DECLARE
    rejected boolean := false;
BEGIN
    BEGIN
        PERFORM insert_patient($pid, 'Duplicado', '555-0000', 'dup@example.com', 'Calle 0 #0-0', '$region');
    EXCEPTION WHEN OTHERS THEN
        rejected := true;
    END;
    IF rejected THEN
        RAISE NOTICE 'REJECTED_AS_EXPECTED';
    ELSE
        RAISE EXCEPTION 'FAIL: $label (insert_patient no fue rechazado)';
    END IF;
END
\$\$;
ROLLBACK;
SQL
    )"
    if ! printf '%s\n' "$out" | grep -Fq "REJECTED_AS_EXPECTED"; then
        fail "$label: insert_patient no fue rechazado por la base"
    fi
    echo "OK: $label"
}

compose up -d --build --wait --wait-timeout 180 fragment-north fragment-south fragmentation-coordinator-horizontal

echo "==> Limpiando y sembrando datos de prueba (llaves disjuntas)"
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

echo "==> Conjuntos de llaves disjuntos en estado normal"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT patient_id FROM patients_north INTERSECT SELECT patient_id FROM patients_south")" "" "sin patient_id compartidos entre NORTH y SOUTH (INTERSECT vacio)"

echo "==> Ruta normal de escritura: insert_patient via coordinador"
# insert_patient es la unica ruta normal de escritura; el coordinador comprueba
# que el patient_id no exista en ningun fragmento antes de insertar.
insert_patient 6 'Pablo Norte' '555-3006' 'pablo.norte@example.com' 'Calle 6 #15-25' 'NORTH'
assert_eq "$(query fragment-north "$DB_USER" "$NORTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 6")" "1" "enrutamiento NORTH inserta en fragment-north"
assert_eq "$(query fragment-south "$DB_USER" "$SOUTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 6")" "0" "enrutamiento NORTH no toca fragment-south"

insert_patient 7 'Lucia Sur' '555-3007' 'lucia.sur@example.com' 'Calle 7 #16-26' 'SOUTH'
assert_eq "$(query fragment-south "$DB_USER" "$SOUTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 7")" "1" "enrutamiento SOUTH inserta en fragment-south"
assert_eq "$(query fragment-north "$DB_USER" "$NORTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 7")" "0" "enrutamiento SOUTH no toca fragment-north"

insert_patient 20 'Ruth Nino' '555-3020' 'ruth.nino@example.com' 'Calle 20 #15-40' 'NORTH'
assert_eq "$(query fragment-north "$DB_USER" "$NORTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 20")" "1" "insercion normal NORTH via coordinador"

insert_patient 21 'Pedro Sur' '555-3021' 'pedro.sur@example.com' 'Calle 21 #16-41' 'SOUTH'
assert_eq "$(query fragment-south "$DB_USER" "$SOUTH_DB" "SELECT count(*) FROM patients WHERE patient_id = 21")" "1" "insercion normal SOUTH via coordinador"

echo "==> Acceso administrativo directo a un fragmento"
# Escribir directamente sobre un fragmento es una operacion administrativa de
# mantenimiento (esquiva el chequeo global del coordinador); NO es la ruta
# normal de escritura. Se verifica que la restriccion CHECK de region sigue
# activa en los fragmentos.
if query fragment-north "$DB_USER" "$NORTH_DB" "INSERT INTO patients (patient_id, full_name, phone, email, address, region) VALUES (30, 'Nodo Equivocado', '555-3030', 'equivocado@example.com', 'Calle 30 #15-50', 'SOUTH')" >/dev/null 2>&1; then
    fail "fragment-north debe rechazar un paciente con region SOUTH"
fi
echo "OK: fragment-north rechaza insercion con region SOUTH"

if query fragment-south "$DB_USER" "$SOUTH_DB" "INSERT INTO patients (patient_id, full_name, phone, email, address, region) VALUES (31, 'Nodo Equivocado', '555-3031', 'equivocado2@example.com', 'Calle 31 #16-51', 'NORTH')" >/dev/null 2>&1; then
    fail "fragment-south debe rechazar un paciente con region NORTH"
fi
echo "OK: fragment-south rechaza insercion con region NORTH"

echo "==> Duplicados entre nodos (negativas con ROLLBACK)"
expect_insert_patient_rejected "insert_patient rechaza patient_id 1 (existe en NORTH) en SOUTH" 1 SOUTH
expect_insert_patient_rejected "insert_patient rechaza patient_id 4 (existe en SOUTH) en NORTH" 4 NORTH
expect_insert_patient_rejected "insert_patient rechaza patient_id 20 (existe en NORTH) en SOUTH" 20 SOUTH

echo "==> Estado normal tras las negativas (sin rastros)"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT patient_id FROM patients_north INTERSECT SELECT patient_id FROM patients_south")" "" "sigue sin patient_id compartidos tras las negativas"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE patient_id = 1")" "1" "solo queda la semilla para patient_id 1"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE patient_id = 4")" "1" "solo queda la semilla para patient_id 4"

echo "==> Reconstruccion global mediante UNION ALL"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all")" "10" "reconstruccion global 10 registros"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE region = 'NORTH'")" "5" "reconstruccion global 5 NORTH"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE region = 'SOUTH'")" "5" "reconstruccion global 5 SOUTH"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE patient_id = 6")" "1" "reconstruccion incluye paciente 6 (NORTH)"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM patients_all WHERE patient_id = 7")" "1" "reconstruccion incluye paciente 7 (SOUTH)"
assert_eq "$(query fragmentation-coordinator-horizontal "$DB_USER" "$COORDINATOR_DB" "SELECT count(*) FROM (SELECT patient_id FROM patients_all GROUP BY patient_id HAVING count(*) > 1) d")" "0" "reconstruccion global sin patient_id duplicados"

echo "All fragmentation horizontal tests passed."
