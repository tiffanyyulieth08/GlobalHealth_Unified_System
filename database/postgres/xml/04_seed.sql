\set ON_ERROR_STOP on

SELECT register_xml_schema(
    'clinical-record-v1',
    '1.0',
    'https://globalhealth.example/xml/clinical-record/v1',
    :'xsd_content'
);
