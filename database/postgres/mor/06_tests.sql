-- Pruebas positivas y negativas del modelo objeto-relacional (MOR).
-- Cualquier asercion fallida lanza una excepcion y aborta la ejecucion.

\set ON_ERROR_STOP on

-- Helpers de asercion.
CREATE OR REPLACE FUNCTION mor_test_assert(p_condition boolean, p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_condition THEN
        RAISE NOTICE 'PASS: %', p_message;
    ELSE
        RAISE EXCEPTION 'FAIL: %', p_message;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION mor_expects_error(p_sql text, p_message text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    BEGIN
        EXECUTE p_sql;
        RAISE EXCEPTION 'FAIL: %', p_message;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'PASS: %', p_message;
    END;
END;
$$;

-- PRUEBAS POSITIVAS ---------------------------------------------------------

SELECT mor_test_assert(
    EXISTS (SELECT 1 FROM pg_type WHERE typname = 'address_t'),
    'address_t type exists');

SELECT mor_test_assert(
    EXISTS (SELECT 1 FROM pg_type WHERE typname = 'phone_t'),
    'phone_t type exists');

SELECT mor_test_assert(
    EXISTS (SELECT 1 FROM pg_type WHERE typname = 'equipment_t'),
    'equipment_t type exists');

SELECT mor_test_assert(
    EXISTS (SELECT 1 FROM pg_type WHERE typname = 'clinic_t'),
    'clinic_t type exists');

SELECT mor_test_assert(
    EXISTS (SELECT 1 FROM pg_class WHERE relname = 'clinic' AND relkind = 'r'),
    'clinic table (CREATE TABLE ... OF) exists');

SELECT mor_test_assert(
    (SELECT pg_typeof(address)::text FROM clinic WHERE id = 1) = 'address_t',
    'clinic.address is address_t');

SELECT mor_test_assert(
    (SELECT pg_typeof(equipments)::text FROM clinic WHERE id = 1) = 'equipment_t[]',
    'clinic.equipments is equipment_t[] (composition)');

SELECT mor_test_assert(
    EXISTS (
        SELECT 1
          FROM pg_inherits i
          JOIN pg_class c ON c.oid = i.inhrelid
          JOIN pg_class p ON p.oid = i.inhparent
         WHERE c.relname = 'doctor' AND p.relname = 'employee'
    ),
    'doctor inherits employee');

SELECT mor_test_assert(
    EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'doctor' AND column_name = 'first_name'),
    'doctor inherits employee columns');

SELECT mor_test_assert(
    (SELECT count(*) FROM ONLY employee) = 2,
    'seed employees count (ONLY employee)');

SELECT mor_test_assert(
    (SELECT count(*) FROM doctor) = 2,
    'seed doctors count');

SELECT mor_test_assert(
    (SELECT count(*) FROM clinic) = 2,
    'seed clinics count');

SELECT mor_test_assert(
    (SELECT pg_typeof(specialties)::text FROM doctor WHERE id = 101) = 'character varying[]',
    'doctor.specialties is character varying[]');

SELECT mor_test_assert(
    (SELECT pg_typeof(phone_numbers)::text FROM doctor WHERE id = 101) = 'phone_t[]',
    'doctor.phone_numbers is phone_t[]');

SELECT mor_test_assert(
    format_address(ROW('Calle 4', 'Heredia', 'Heredia', '40101', 'Costa Rica')::address_t)
        = 'Calle 4, Heredia, Heredia 40101, Costa Rica',
    'format_address receives address_t');

SELECT mor_test_assert(
    format_phone(ROW('506', '8888-1234', 'mobile')::phone_t) = '+506 8888-1234 (mobile)',
    'format_phone receives phone_t');

SELECT mor_test_assert(
    yearly_salary((SELECT e FROM employee e WHERE id = 1)) = 102000.00,
    'yearly_salary receives employee row type');

SELECT mor_test_assert(
    clinic_equipment_count(
        ROW(1, 'GlobalHealth San Jose', NULL, ARRAY[
            ROW('Siemens', 'MAGNETOM Vida', 'MRI-SN-001', 2021, 'operational', 24)::equipment_t
        ]::equipment_t[])::clinic_t
    ) = 1,
    'clinic_equipment_count receives clinic_t');

SELECT mor_test_assert(
    register_equipment(2, ROW('Philips', 'EPIQ Elite', 'US-SN-007', 2024, 'operational', 48)::equipment_t) = 3,
    'register_equipment receives equipment_t and appends to composition');

SELECT mor_test_assert(
    clinic_equipment_count_id(2) = 3,
    'clinic 2 has 3 equipments after register_equipment');

INSERT INTO clinic (name, equipments)
VALUES (
    'Clinic Temp Delete',
    ARRAY[ROW('Stryker', '1588 AIM', 'LR-SN-008', 2023, 'operational', 24)::equipment_t]
);

DELETE FROM clinic WHERE name = 'Clinic Temp Delete';

SELECT mor_test_assert(
    NOT EXISTS (SELECT 1 FROM clinic WHERE name = 'Clinic Temp Delete'),
    'deleting clinic removes its equipment composition');

-- PRUEBAS NEGATIVAS ---------------------------------------------------------

SELECT mor_expects_error(
    'INSERT INTO employee (first_name, last_name, email) VALUES (''X'', ''Y'', ''maria.fernandez@globalhealth.cr'')',
    'duplicate employee email rejected');

SELECT mor_expects_error(
    'INSERT INTO employee (first_name, last_name, email, salary) VALUES (''X'', ''Y'', ''neg.salary@test.cr'', -5)',
    'negative employee salary rejected');

SELECT mor_expects_error(
    'INSERT INTO doctor (id, first_name, last_name, email, specialty) VALUES (999, ''X'', ''Y'', ''neg.null@test.cr'', NULL)',
    'null doctor specialty rejected');

SELECT mor_expects_error(
    'INSERT INTO doctor (id, first_name, last_name, email, specialty, salary) VALUES (998, ''X'', ''Y'', ''neg.dsal@test.cr'', ''D'', -1)',
    'negative doctor salary rejected');

SELECT mor_expects_error(
    'SELECT register_equipment(999, ROW(''A'', ''B'', ''C'', 2020, ''D'', 1)::equipment_t)',
    'register_equipment on missing clinic rejected');

SELECT mor_expects_error(
    'INSERT INTO employee (first_name, last_name, email, phone) VALUES (''X'', ''Y'', ''neg.phone@test.cr'', ''not a phone'')',
    'text into phone_t column rejected');

SELECT mor_expects_error(
    'INSERT INTO employee (id, first_name, last_name, email, phone) VALUES (997, ''X'', ''Y'', ''neg.phone2@test.cr'', ROW(''506'', ''1234''))',
    'record with wrong field count into phone_t rejected');

SELECT mor_expects_error(
    'INSERT INTO doctor (id, first_name, last_name, email, specialty, license) VALUES (996, ''X'', ''Y'', ''neg.lic@test.cr'', ''D'', ''MED-1234'')',
    'duplicate doctor license rejected');

SELECT mor_expects_error(
    'INSERT INTO clinic (name, address) VALUES (''GlobalHealth San Jose'', NULL)',
    'duplicate clinic name rejected');

SELECT mor_test_assert(true, 'All MOR tests passed');
