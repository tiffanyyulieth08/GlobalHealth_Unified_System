CREATE EXTENSION IF NOT EXISTS plpython3u;

CREATE TABLE xml_schema_registry (
    schema_name text PRIMARY KEY,
    schema_version text NOT NULL,
    namespace_uri text NOT NULL,
    xsd_document xml NOT NULL,
    created_at timestamptz NOT NULL DEFAULT current_timestamp,
    updated_at timestamptz NOT NULL DEFAULT current_timestamp,
    UNIQUE (schema_name, schema_version)
);

CREATE OR REPLACE FUNCTION register_xml_schema(
    p_schema_name text,
    p_schema_version text,
    p_namespace_uri text,
    p_xsd text
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO xml_schema_registry (
        schema_name, schema_version, namespace_uri, xsd_document
    )
    VALUES (
        p_schema_name, p_schema_version, p_namespace_uri, xmlparse(document p_xsd)
    );
END;
$$;

CREATE OR REPLACE FUNCTION get_xml_schema(p_schema_name text)
RETURNS TABLE (
    schema_name text,
    schema_version text,
    namespace_uri text,
    xsd_document xml,
    created_at timestamptz,
    updated_at timestamptz
)
LANGUAGE sql
STABLE
AS $$
    SELECT r.schema_name, r.schema_version, r.namespace_uri,
           r.xsd_document, r.created_at, r.updated_at
    FROM xml_schema_registry AS r
    WHERE r.schema_name = p_schema_name;
$$;

CREATE OR REPLACE FUNCTION update_xml_schema(
    p_schema_name text,
    p_schema_version text,
    p_namespace_uri text,
    p_xsd text
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE xml_schema_registry
    SET schema_version = p_schema_version,
        namespace_uri = p_namespace_uri,
        xsd_document = xmlparse(document p_xsd),
        updated_at = current_timestamp
    WHERE schema_name = p_schema_name;
    RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION delete_xml_schema(p_schema_name text)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM xml_schema_registry
    WHERE schema_name = p_schema_name;
    RETURN FOUND;
END;
$$;
