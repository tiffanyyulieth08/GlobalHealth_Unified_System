-- Tablas del modelo objeto-relacional (MOR).

-- Secuencia para los identificadores de clinic.
CREATE SEQUENCE mor_clinic_id_seq;

-- Tabla tipada: clinic OF clinic_t.
-- Los equipos viven dentro del arreglo equipments, lo que modela la
-- composicion fuerte entre clinica y equipos.
CREATE TABLE clinic OF clinic_t (
    id WITH OPTIONS DEFAULT nextval('mor_clinic_id_seq') PRIMARY KEY,
    name WITH OPTIONS NOT NULL UNIQUE
);

-- Empleado base. El tipo compuesto address_t y phone_t se usan como columnas.
CREATE TABLE employee (
    id         serial PRIMARY KEY,
    first_name varchar(60) NOT NULL,
    last_name  varchar(60) NOT NULL,
    email      varchar(120) NOT NULL UNIQUE,
    hire_date  date NOT NULL DEFAULT CURRENT_DATE,
    address    address_t,
    phone      phone_t,
    salary     numeric(10, 2) CHECK (salary >= 0)
);

-- Doctor heredado de employee (INHERITS).
-- Las restricciones del padre no se heredan, por eso se redefinen aqui.
CREATE TABLE doctor (
    specialty     varchar(80) NOT NULL,
    license       varchar(40) NOT NULL UNIQUE,
    specialties   varchar(80)[],
    clinic_id     integer REFERENCES clinic(id),
    phone_numbers phone_t[]
) INHERITS (employee);

ALTER TABLE doctor ADD PRIMARY KEY (id);
ALTER TABLE doctor ADD UNIQUE (email);
ALTER TABLE doctor ADD CONSTRAINT doctor_salary_check CHECK (salary >= 0);
