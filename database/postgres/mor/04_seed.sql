-- Datos semilla del modelo objeto-relacional (MOR).

-- Clinicas tipadas con equipos embebidos (composicion).
INSERT INTO clinic (id, name, address, equipments)
VALUES (
    1,
    'GlobalHealth San Jose',
    ROW('Avenida Central 240', 'San Jose', 'San Jose', '10101', 'Costa Rica')::address_t,
    ARRAY[
        ROW('Siemens', 'MAGNETOM Vida', 'MRI-SN-001', 2021, 'operational', 24)::equipment_t,
        ROW('GE HealthCare', 'Revolution', 'CT-SN-002', 2019, 'maintenance', 12)::equipment_t
    ]
);

INSERT INTO clinic (id, name, address, equipments)
VALUES (
    2,
    'GlobalHealth Heredia',
    ROW('Calle 6', 'Heredia', 'Heredia', '40101', 'Costa Rica')::address_t,
    ARRAY[
        ROW('Philips', 'Azurion 7', 'XC-SN-003', 2020, 'operational', 36)::equipment_t
    ]
);

SELECT setval('mor_clinic_id_seq', 2, true);

-- Empleados (solo la tabla employee).
INSERT INTO employee (id, first_name, last_name, email, hire_date, address, phone, salary)
VALUES (
    1,
    'Maria',
    'Fernandez',
    'maria.fernandez@globalhealth.cr',
    DATE '2023-01-15',
    ROW('Calle 4', 'Heredia', 'Heredia', '40101', 'Costa Rica')::address_t,
    ROW('506', '8888-1234', 'mobile')::phone_t,
    8500.00
);

INSERT INTO employee (id, first_name, last_name, email, hire_date, address, phone, salary)
VALUES (
    2,
    'Pedro',
    'Mora',
    'pedro.mora@globalhealth.cr',
    DATE '2022-08-01',
    ROW('Av. 5', 'Alajuela', 'Alajuela', '20101', 'Costa Rica')::address_t,
    ROW('506', '8888-9999', 'mobile')::phone_t,
    7800.00
);

-- Doctores heredados de employee con arreglos de especialidades y telefonos.
INSERT INTO doctor (id, first_name, last_name, email, hire_date, address, phone, salary, specialty, license, specialties, clinic_id, phone_numbers)
VALUES (
    101,
    'Ana',
    'Solano',
    'ana.solano@globalhealth.cr',
    DATE '2020-03-10',
    ROW('Av. Central 88', 'San Jose', 'San Jose', '10101', 'Costa Rica')::address_t,
    ROW('506', '2222-3344', 'work')::phone_t,
    12000.00,
    'Cardiologia',
    'MED-1234',
    ARRAY['Cardiologia', 'Medicina Interna'],
    1,
    ARRAY[
        ROW('506', '8888-5566', 'mobile')::phone_t,
        ROW('506', '2222-3344', 'work')::phone_t
    ]
);

INSERT INTO doctor (id, first_name, last_name, email, hire_date, address, phone, salary, specialty, license, specialties, clinic_id, phone_numbers)
VALUES (
    102,
    'Luis',
    'Vargas',
    'luis.vargas@globalhealth.cr',
    DATE '2021-11-22',
    ROW('Calle 12', 'Heredia', 'Heredia', '40101', 'Costa Rica')::address_t,
    ROW('506', '2233-4455', 'work')::phone_t,
    13500.00,
    'Neurologia',
    'MED-5678',
    ARRAY['Neurologia'],
    2,
    ARRAY[
        ROW('506', '8888-7788', 'mobile')::phone_t
    ]
);

-- Agregar equipo a la clinica 2 mediante la funcion de composicion.
SELECT register_equipment(2, ROW('Mindray', 'DC-80', 'US-SN-004', 2023, 'operational', 36)::equipment_t);

-- Sincronizar la secuencia de employee con los ids usados.
SELECT setval('employee_id_seq', (SELECT max(id) FROM employee), true);
