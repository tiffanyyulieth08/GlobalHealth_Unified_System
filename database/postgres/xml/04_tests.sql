\set ON_ERROR_STOP on

SELECT register_xml_schema(
    'clinical-record-v1',
    '1.0',
    'https://globalhealth.example/xml/clinical-record/v1',
    :'xsd_content'
);

DO $$
BEGIN
    IF (SELECT count(*) FROM get_xml_schema('clinical-record-v1')) <> 1 THEN
        RAISE EXCEPTION 'Schema registry read test failed';
    END IF;
END;
$$;

SELECT register_xml_schema(
    'temporary-test-schema',
    '1.0',
    'https://globalhealth.example/xml/clinical-record/v1',
    :'xsd_content'
);

SELECT update_xml_schema(
    'temporary-test-schema',
    '1.1',
    'https://globalhealth.example/xml/clinical-record/v1',
    :'xsd_content'
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM xml_schema_registry
        WHERE schema_name = 'temporary-test-schema'
          AND schema_version = '1.1'
    ) THEN
        RAISE EXCEPTION 'Schema registry update test failed';
    END IF;
    IF NOT delete_xml_schema('temporary-test-schema') THEN
        RAISE EXCEPTION 'Schema registry delete test failed';
    END IF;
END;
$$;

INSERT INTO clinical_records_xml (clinical_document)
VALUES (xmlparse(document
'<clinicalRecord xmlns="https://globalhealth.example/xml/clinical-record/v1" version="1.0">
  <patient>
    <id>PAT-000123</id>
    <fullName>Ana Rodríguez</fullName>
    <birthDate>1990-04-12</birthDate>
  </patient>
  <physician>
    <license>MED-12345</license>
    <fullName>Laura Jiménez</fullName>
  </physician>
  <recordDate>2026-07-31T14:30:00-06:00</recordDate>
  <diagnosis code="A09" severity="high">Gastroenteritis infecciosa</diagnosis>
  <notes>Control en siete días</notes>
</clinicalRecord>'));

DO $$
BEGIN
    BEGIN
        EXECUTE $bad$INSERT INTO clinical_records_xml (clinical_document)
                VALUES (xmlparse(document '<clinicalRecord><patient></clinicalRecord>'))$bad$;
        RAISE EXCEPTION 'Malformed XML was accepted';
    EXCEPTION
        WHEN invalid_xml_document THEN NULL;
    END;

    BEGIN
        INSERT INTO clinical_records_xml (clinical_document)
        VALUES (xmlparse(document
            '<clinicalRecord xmlns="https://globalhealth.example/xml/clinical-record/v1" version="1.0">
               <patient><id>INVALID</id><fullName>Ana Rodríguez</fullName><birthDate>1990-04-12</birthDate></patient>
               <physician><license>MED-12345</license><fullName>Laura Jiménez</fullName></physician>
               <recordDate>2026-07-31T14:30:00-06:00</recordDate>
             </clinicalRecord>'));
        RAISE EXCEPTION 'Well-formed but XSD-invalid XML was accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM NOT LIKE '%XML does not conform to clinical-record-v1:%' THEN
                RAISE;
            END IF;
    END;
END;
$$;

DO $$
DECLARE
    v_record_id bigint;
BEGIN
    SELECT record_id INTO v_record_id FROM clinical_records_xml LIMIT 1;

    UPDATE clinical_records_xml
    SET clinical_document = xml_replace_node_text(
        clinical_document,
        '/gh:clinicalRecord/gh:diagnosis',
        'Gastroenteritis resuelta',
        '{"gh":"https://globalhealth.example/xml/clinical-record/v1"}'
    )
    WHERE record_id = v_record_id;

    IF NOT EXISTS (
        SELECT 1 FROM clinical_record_xpath
        WHERE record_id = v_record_id
          AND diagnosis = 'Gastroenteritis resuelta'
    ) THEN
        RAISE EXCEPTION 'Internal node update test failed';
    END IF;

    IF NOT xpath_exists(
        '/gh:clinicalRecord/gh:notes',
        (SELECT clinical_document FROM clinical_records_xml WHERE record_id = v_record_id),
        ARRAY[ARRAY['gh', 'https://globalhealth.example/xml/clinical-record/v1']]
    ) THEN
        RAISE EXCEPTION 'Internal node update removed notes';
    END IF;

    UPDATE clinical_records_xml
    SET clinical_document = xml_remove_nodes(
        clinical_document,
        '/gh:clinicalRecord/gh:notes',
        '{"gh":"https://globalhealth.example/xml/clinical-record/v1"}'
    )
    WHERE record_id = v_record_id;

    IF xpath_exists(
        '/gh:clinicalRecord/gh:notes',
        (SELECT clinical_document FROM clinical_records_xml WHERE record_id = v_record_id),
        ARRAY[ARRAY['gh', 'https://globalhealth.example/xml/clinical-record/v1']]
    ) THEN
        RAISE EXCEPTION 'Internal node deletion test failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM clinical_record_high_severity WHERE record_id = v_record_id
    ) THEN
        RAISE EXCEPTION 'xpath_exists test failed';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM clinical_record_relational
        WHERE record_id = v_record_id
          AND patient_id = 'PAT-000123'
          AND diagnosis_code = 'A09'
    ) THEN
        RAISE EXCEPTION 'XMLTABLE test failed';
    END IF;
END;
$$;

DO $$
DECLARE
    v_record_id bigint;
BEGIN
    SELECT record_id INTO v_record_id FROM clinical_records_xml LIMIT 1;

    -- Eliminar un nodo obligatorio (<patient>) debe ser rechazado por el
    -- trigger de validacion; el documento almacenado no debe modificarse.
    BEGIN
        UPDATE clinical_records_xml
        SET clinical_document = xml_remove_nodes(
            clinical_document,
            '/gh:clinicalRecord/gh:patient',
            '{"gh":"https://globalhealth.example/xml/clinical-record/v1"}'
        )
        WHERE record_id = v_record_id;
        RAISE EXCEPTION 'Removal of a required node was accepted';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLERRM NOT LIKE '%XML does not conform to clinical-record-v1:%' THEN
                RAISE;
            END IF;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM clinical_record_xpath
        WHERE record_id = v_record_id
          AND patient_name = 'Ana Rodríguez'
    ) THEN
        RAISE EXCEPTION 'Required node removal modified the stored document';
    END IF;
END;
$$;

SELECT 'All XML/XSD tests passed.' AS result;
