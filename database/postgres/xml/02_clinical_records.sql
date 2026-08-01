CREATE OR REPLACE FUNCTION validate_xml_against_schema(
    p_document xml,
    p_schema_name text
)
RETURNS boolean
LANGUAGE plpython3u
STABLE
STRICT
AS $$
from lxml import etree

row = plpy.execute(
    "SELECT xsd_document::text FROM xml_schema_registry "
    "WHERE schema_name = %s" % plpy.quote_literal(p_schema_name),
    1
)
if not row:
    plpy.error("XSD schema not found: %s" % p_schema_name)

try:
    schema_root = etree.fromstring(row[0]["xsd_document"].encode("utf-8"))
    schema = etree.XMLSchema(schema_root)
    document = etree.fromstring(p_document.encode("utf-8"))
except (etree.XMLSyntaxError, etree.XMLSchemaParseError) as exc:
    plpy.error("XML or XSD parsing error: %s" % exc)

if not schema.validate(document):
    errors = "; ".join(str(error) for error in schema.error_log)
    plpy.error("XML does not conform to %s: %s" % (p_schema_name, errors))
return True
$$;

CREATE TABLE clinical_records_xml (
    record_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    schema_name text NOT NULL DEFAULT 'clinical-record-v1'
        REFERENCES xml_schema_registry (schema_name),
    clinical_document xml NOT NULL,
    created_at timestamptz NOT NULL DEFAULT current_timestamp,
    updated_at timestamptz NOT NULL DEFAULT current_timestamp
);

CREATE OR REPLACE FUNCTION enforce_clinical_record_xsd()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM validate_xml_against_schema(NEW.clinical_document, NEW.schema_name);
    NEW.updated_at := current_timestamp;
    RETURN NEW;
END;
$$;

CREATE TRIGGER clinical_records_validate_xsd
BEFORE INSERT OR UPDATE OF clinical_document, schema_name
ON clinical_records_xml
FOR EACH ROW
EXECUTE FUNCTION enforce_clinical_record_xsd();
