-- Tipos compuestos del modelo objeto-relacional (MOR).

-- Direccion postal de una persona o clinica.
CREATE TYPE address_t AS (
    street  varchar(120),
    city    varchar(80),
    state   varchar(80),
    zip     varchar(20),
    country varchar(80)
);

-- Telefono de contacto.
CREATE TYPE phone_t AS (
    country_code varchar(6),
    number       varchar(20),
    kind         varchar(20)
);

-- Caracteristicas de un equipo medico.
CREATE TYPE equipment_t AS (
    brand            varchar(60),
    model            varchar(60),
    serial_number    varchar(60),
    acquisition_year smallint,
    status           varchar(20),
    warranty_months  smallint
);

-- Tipo para la tabla tipada clinic (CREATE TABLE ... OF).
CREATE TYPE clinic_t AS (
    id         integer,
    name       varchar(120),
    address    address_t,
    equipments equipment_t[]
);
