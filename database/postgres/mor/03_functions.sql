-- Funciones que reciben tipos compuestos.

-- Formatea una direccion (recibe address_t).
CREATE OR REPLACE FUNCTION format_address(a address_t)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT a.street || ', ' || a.city || ', ' || a.state || ' ' || a.zip || ', ' || a.country;
$$;

-- Formatea un telefono (recibe phone_t).
CREATE OR REPLACE FUNCTION format_phone(p phone_t)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT '+' || p.country_code || ' ' || p.number || ' (' || p.kind || ')';
$$;

-- Agrega un equipo a una clinica (composicion).
-- Recibe un equipment_t y lo anexa al arreglo de equipos de la clinica.
CREATE OR REPLACE FUNCTION register_equipment(p_clinic_id integer, p_equipment equipment_t)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_count integer;
BEGIN
    UPDATE clinic
       SET equipments = coalesce(equipments, ARRAY[]::equipment_t[]) || p_equipment
     WHERE id = p_clinic_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Clinic with id % not found', p_clinic_id;
    END IF;

    SELECT array_length(equipments, 1) INTO v_count FROM clinic WHERE id = p_clinic_id;
    RETURN v_count;
END;
$$;

-- Cuenta los equipos de una clinica (recibe un valor de tipo clinic_t).
CREATE OR REPLACE FUNCTION clinic_equipment_count(c clinic_t)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT coalesce(array_length(c.equipments, 1), 0);
$$;

-- Cuenta los equipos de una clinica por id.
CREATE OR REPLACE FUNCTION clinic_equipment_count_id(p_clinic_id integer)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT coalesce(array_length(e.equipments, 1), 0)
      FROM clinic e
     WHERE e.id = p_clinic_id;
$$;

-- Salario anual de un empleado (recibe el tipo compuesto de la tabla employee).
CREATE OR REPLACE FUNCTION yearly_salary(e employee)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT e.salary * 12;
$$;
