\set ON_ERROR_STOP on

SELECT register_xml_schema(
    'clinical-record-v1',
    '1.0',
    'https://globalhealth.example/xml/clinical-record/v1',
    :'xsd_content'
);

INSERT INTO clinic (id, name, address, equipments)
VALUES (
    900001,
    'GlobalHealth Integration Clinic',
    ROW('Integration Street 1', 'San Jose', 'San Jose', '10101', 'Costa Rica')::address_t,
    ARRAY[]::equipment_t[]
);

INSERT INTO doctor (
    id,
    first_name,
    last_name,
    email,
    hire_date,
    address,
    phone,
    salary,
    specialty,
    license,
    specialties,
    clinic_id,
    phone_numbers
)
VALUES (
    900001,
    'Tiffany',
    'Integration',
    'tiffany.integration@globalhealth.test',
    CURRENT_DATE,
    ROW('Integration Street 1', 'San Jose', 'San Jose', '10101', 'Costa Rica')::address_t,
    ROW('506', '2000-0001', 'work')::phone_t,
    10000.00,
    'Medicina Interna',
    'INT-MED-900001',
    ARRAY['Medicina Interna'],
    900001,
    ARRAY[ROW('506', '2000-0001', 'work')::phone_t]
);

INSERT INTO clinical_records_xml (clinical_document)
VALUES (xmlparse(document
'<clinicalRecord xmlns="https://globalhealth.example/xml/clinical-record/v1" version="1.0">
  <patient>
    <id>INT-P001</id>
    <fullName>Paciente Integracion</fullName>
    <birthDate>1992-05-14</birthDate>
  </patient>
  <physician>
    <license>INT-MED-900001</license>
    <fullName>Tiffany Integration</fullName>
  </physician>
  <recordDate>2026-08-01T09:00:00-06:00</recordDate>
  <diagnosis code="Z00" severity="low">Control de integracion</diagnosis>
  <notes>Expediente valido para la prueba integral</notes>
</clinicalRecord>'));

DO $$
BEGIN
    IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'El flujo PostgreSQL no se ejecuto en Primary';
    END IF;

    BEGIN
        INSERT INTO clinical_records_xml (clinical_document)
        VALUES (xmlparse(document
            '<clinicalRecord xmlns="https://globalhealth.example/xml/clinical-record/v1" version="1.0">
               <patient><id>INT-P001</id></patient>
               <recordDate>not-a-date</recordDate>
             </clinicalRecord>'));
        RAISE EXCEPTION 'El XML invalido fue aceptado';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM NOT LIKE '%XML does not conform to clinical-record-v1:%' THEN
                RAISE;
            END IF;
    END;

    IF (SELECT count(*) FROM doctor WHERE license = 'INT-MED-900001') <> 1 THEN
        RAISE EXCEPTION 'No se creo el medico de integracion';
    END IF;

    IF (
        SELECT count(*)
        FROM clinical_record_relational
        WHERE patient_id = 'INT-P001'
          AND physician_license = 'INT-MED-900001'
    ) <> 1 THEN
        RAISE EXCEPTION 'No se inserto el expediente XML valido';
    END IF;

    IF (SELECT count(*) FROM clinical_records_xml) <> 1 THEN
        RAISE EXCEPTION 'El XML invalido altero la cantidad de expedientes';
    END IF;
END;
$$;

SELECT 'OK: medico creado en PostgreSQL Primary' AS evidence;
SELECT 'OK: expediente XML valido insertado' AS evidence;
SELECT 'OK: expediente XML invalido rechazado por XSD' AS evidence;
