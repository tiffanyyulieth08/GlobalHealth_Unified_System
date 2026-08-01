CREATE OR REPLACE FUNCTION xml_replace_node_text(
    p_document xml,
    p_xpath text,
    p_value text,
    p_namespaces jsonb DEFAULT '{}'::jsonb
)
RETURNS xml
LANGUAGE plpython3u
IMMUTABLE
STRICT
AS $$
import json
from lxml import etree

root = etree.fromstring(p_document.encode("utf-8"))
namespaces = json.loads(p_namespaces) if isinstance(p_namespaces, str) else p_namespaces
nodes = root.xpath(p_xpath, namespaces=namespaces)
if not nodes:
    plpy.error("XPath selected no nodes: %s" % p_xpath)
for node in nodes:
    if not isinstance(node, etree._Element):
        plpy.error("XPath must select XML elements")
    node.text = p_value
return etree.tostring(root, encoding="unicode")
$$;

CREATE OR REPLACE FUNCTION xml_remove_nodes(
    p_document xml,
    p_xpath text,
    p_namespaces jsonb DEFAULT '{}'::jsonb
)
RETURNS xml
LANGUAGE plpython3u
IMMUTABLE
STRICT
AS $$
import json
from lxml import etree

root = etree.fromstring(p_document.encode("utf-8"))
namespaces = json.loads(p_namespaces) if isinstance(p_namespaces, str) else p_namespaces
nodes = root.xpath(p_xpath, namespaces=namespaces)
for node in nodes:
    if not isinstance(node, etree._Element) or node.getparent() is None:
        plpy.error("XPath must select removable XML elements")
    node.getparent().remove(node)
return etree.tostring(root, encoding="unicode")
$$;

CREATE OR REPLACE VIEW clinical_record_xpath AS
SELECT
    record_id,
    (xpath(
        '/gh:clinicalRecord/gh:patient/gh:fullName/text()',
        clinical_document,
        ARRAY[ARRAY['gh', 'https://globalhealth.example/xml/clinical-record/v1']]
    ))[1]::text AS patient_name,
    (xpath(
        '/gh:clinicalRecord/gh:diagnosis/text()',
        clinical_document,
        ARRAY[ARRAY['gh', 'https://globalhealth.example/xml/clinical-record/v1']]
    ))[1]::text AS diagnosis
FROM clinical_records_xml;

CREATE OR REPLACE VIEW clinical_record_high_severity AS
SELECT record_id, clinical_document
FROM clinical_records_xml
WHERE xpath_exists(
    '/gh:clinicalRecord/gh:diagnosis[@severity="high" or @severity="critical"]',
    clinical_document,
    ARRAY[ARRAY['gh', 'https://globalhealth.example/xml/clinical-record/v1']]
);

CREATE OR REPLACE VIEW clinical_record_relational AS
SELECT r.record_id, x.*
FROM clinical_records_xml AS r
CROSS JOIN LATERAL XMLTABLE(
    XMLNAMESPACES(
        'https://globalhealth.example/xml/clinical-record/v1' AS gh
    ),
    '/gh:clinicalRecord'
    PASSING r.clinical_document
    COLUMNS
        patient_id text PATH 'gh:patient/gh:id',
        patient_name text PATH 'gh:patient/gh:fullName',
        physician_license text PATH 'gh:physician/gh:license',
        physician_name text PATH 'gh:physician/gh:fullName',
        record_date timestamptz PATH 'gh:recordDate',
        diagnosis_code text PATH 'gh:diagnosis/@code',
        diagnosis text PATH 'gh:diagnosis'
) AS x;
