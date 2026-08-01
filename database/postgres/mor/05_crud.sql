-- Demostracion de operaciones CRUD sobre el modelo objeto-relacional.
-- Usa registros propios (id 3, 103 y clinica 3) para no alterar los datos semilla.

-- INSERT: clinica tipada, empleado y doctor heredado.
INSERT INTO clinic (id, name, address, equipments)
VALUES (
    3,
    'GlobalHealth Cartago',
    ROW('Calle 3', 'Cartago', 'Cartago', '30101', 'Costa Rica')::address_t,
    ARRAY[ROW('Carestream', 'DRX-Evolution', 'XR-SN-005', 2022, 'operational', 24)::equipment_t]
);

INSERT INTO employee (id, first_name, last_name, email, hire_date, address, phone, salary)
VALUES (
    3,
    'Carlos',
    'Vega',
    'carlos.vega@globalhealth.cr',
    DATE '2024-05-01',
    ROW('Av. 7', 'Alajuela', 'Alajuela', '20101', 'Costa Rica')::address_t,
    ROW('506', '8899-1122', 'mobile')::phone_t,
    7800.00
);

INSERT INTO doctor (id, first_name, last_name, email, hire_date, salary, specialty, license, specialties, clinic_id, phone_numbers)
VALUES (
    103,
    'Lucia',
    'Rojas',
    'lucia.rojas@globalhealth.cr',
    DATE '2024-06-15',
    13500.00,
    'Pediatria',
    'MED-9900',
    ARRAY['Pediatria'],
    1,
    ARRAY[ROW('506', '7777-3344', 'mobile')::phone_t]
);

-- SELECT: columnas compuestas formateadas, arreglos y agregacion.
SELECT e.id, e.first_name, e.last_name, format_address(e.address) AS address, format_phone(e.phone) AS phone
  FROM employee e
 ORDER BY e.id;

SELECT d.id, d.first_name, d.last_name, d.specialty, unnest(d.specialties) AS subspecialty
  FROM doctor d
 ORDER BY d.id, subspecialty;

SELECT c.id, c.name, clinic_equipment_count_id(c.id) AS equipment_count
  FROM clinic c
 ORDER BY c.id;

SELECT c.id, c.name, eq.brand, eq.model, eq.status
  FROM clinic c, unnest(c.equipments) AS eq
 ORDER BY c.id;

-- UPDATE: salario, asignacion de clinica y composicion via funcion.
UPDATE employee SET salary = salary + 500 WHERE id = 3;

UPDATE doctor SET clinic_id = 2 WHERE id = 103;

SELECT register_equipment(3, ROW('General Electric', 'Venue', 'US-SN-006', 2024, 'operational', 48)::equipment_t) AS cartago_equipment_count;

-- DELETE: doctor, empleado y clinica (la composicion se elimina con la clinica).
DELETE FROM doctor WHERE id = 103;

DELETE FROM employee WHERE id = 3;

DELETE FROM clinic WHERE id = 3;
