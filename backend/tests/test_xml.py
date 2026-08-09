import asyncio
import unittest
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import asyncpg
from fastapi import HTTPException, Request

from app.routers import xml


NOW = datetime(2026, 8, 8, tzinfo=timezone.utc)
XSD = '<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"/>'
DOCUMENT = '<clinicalRecord xmlns="urn:test"/>'


def schema_row(name: str = "clinical-record-v1") -> dict:
    return {
        "schema_name": name,
        "schema_version": "1.0",
        "namespace_uri": "urn:test",
        "xsd_document": XSD,
        "created_at": NOW,
        "updated_at": NOW,
    }


def clinical_row(record_id: int = 1) -> dict:
    return {
        "record_id": record_id,
        "schema_name": "clinical-record-v1",
        "clinical_document": DOCUMENT,
        "created_at": NOW,
        "updated_at": NOW,
    }


class FakePool:
    def __init__(self) -> None:
        self.rows: list[dict] = []
        self.row: dict | None = None
        self.values: list[object] = []
        self.result = "DELETE 1"
        self.raises: asyncpg.PostgresError | None = None
        self.calls: list[tuple[str, tuple]] = []

    async def fetch(self, sql: str, *args):
        self.calls.append((sql, args))
        return self.rows

    async def fetchrow(self, sql: str, *args):
        self.calls.append((sql, args))
        if self.raises:
            raise self.raises
        return self.row

    async def fetchval(self, sql: str, *args):
        self.calls.append((sql, args))
        if self.raises:
            raise self.raises
        return self.values.pop(0)

    async def execute(self, sql: str, *args):
        self.calls.append((sql, args))
        if self.raises:
            raise self.raises
        return self.result

    async def acquire(self):
        return self

    async def release(self, connection) -> None:
        pass

    @asynccontextmanager
    async def transaction(self):
        yield


def request(pool: FakePool) -> Request:
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/api/xml",
        "headers": [],
        "query_string": b"",
        "app": type("App", (), {"state": type("State", (), {"write_pool": pool})()})(),
    }
    return Request(scope)


class XmlSchemaApiTests(unittest.TestCase):
    def test_create_schema_uses_registry_function(self) -> None:
        db = FakePool()
        db.row = schema_row("new-schema")
        result = asyncio.run(
            xml.create_schema(
                request(db),
                xml.SchemaCreate(
                    schema_name="new-schema",
                    schema_version="1.0",
                    namespace_uri="urn:test",
                    xsd_document=XSD,
                ),
            )
        )
        self.assertEqual(result["schema_name"], "new-schema")
        self.assertIn("register_xml_schema", " ".join(call[0] for call in db.calls))

    def test_list_and_get_schemas_use_registry(self) -> None:
        db = FakePool()
        db.rows = [schema_row()]
        self.assertEqual(len(asyncio.run(xml.list_schemas(request(db)))), 1)
        db.row = schema_row()
        result = asyncio.run(xml.get_schema(request(db), "clinical-record-v1"))
        self.assertEqual(result["schema_version"], "1.0")
        self.assertIn("get_xml_schema", db.calls[-1][0])

    def test_update_schema_revalidates_dependent_records(self) -> None:
        db = FakePool()
        db.values = [True]
        db.row = schema_row()
        result = asyncio.run(
            xml.update_schema(
                request(db),
                "clinical-record-v1",
                xml.SchemaUpdate(
                    schema_version="1.1",
                    namespace_uri="urn:test",
                    xsd_document=XSD,
                ),
            )
        )
        sql = " ".join(call[0] for call in db.calls)
        self.assertEqual(result["schema_name"], "clinical-record-v1")
        self.assertIn("update_xml_schema", sql)
        self.assertIn("validate_xml_against_schema", sql)

    def test_delete_schema_in_use_returns_409(self) -> None:
        db = FakePool()
        db.values = [True]
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(xml.delete_schema(request(db), "clinical-record-v1"))
        self.assertEqual(raised.exception.status_code, 409)
        self.assertNotIn("delete_xml_schema", " ".join(call[0] for call in db.calls))

    def test_delete_unused_schema_calls_registry_function(self) -> None:
        db = FakePool()
        db.values = [False, True]
        response = asyncio.run(xml.delete_schema(request(db), "unused"))
        self.assertEqual(response.status_code, 204)
        self.assertIn("delete_xml_schema", db.calls[-1][0])


class XmlClinicalRecordApiTests(unittest.TestCase):
    def test_create_record_relies_on_xmlparse_and_validation_trigger(self) -> None:
        db = FakePool()
        db.row = clinical_row()
        result = asyncio.run(
            xml.create_record(
                request(db), xml.ClinicalRecordCreate(clinical_document=DOCUMENT)
            )
        )
        self.assertEqual(result["record_id"], 1)
        self.assertIn("INSERT INTO clinical_records_xml", db.calls[0][0])
        self.assertIn("xmlparse(document $2)", db.calls[0][0])

    def test_get_list_update_and_delete_records(self) -> None:
        db = FakePool()
        db.rows = [clinical_row()]
        self.assertEqual(len(asyncio.run(xml.list_records(request(db)))), 1)
        db.row = clinical_row()
        self.assertEqual(asyncio.run(xml.get_record(request(db), 1))["record_id"], 1)
        updated = asyncio.run(
            xml.update_record(
                request(db),
                1,
                xml.ClinicalRecordUpdate(
                    schema_name="clinical-record-v1", clinical_document=DOCUMENT
                ),
            )
        )
        self.assertEqual(updated["record_id"], 1)
        self.assertIn("xmlparse(document $3)", db.calls[-1][0])
        self.assertEqual(asyncio.run(xml.delete_record(request(db), 1)).status_code, 204)

    def test_malformed_and_xsd_invalid_xml_map_to_422(self) -> None:
        for message in (
            "invalid XML document",
            "XML does not conform to clinical-record-v1",
        ):
            db = FakePool()
            db.raises = asyncpg.PostgresError(message)
            with self.assertRaises(HTTPException) as raised:
                asyncio.run(
                    xml.create_record(
                        request(db),
                        xml.ClinicalRecordCreate(clinical_document="<bad>"),
                    )
                )
            self.assertEqual(raised.exception.status_code, 422)

    def test_internal_update_uses_database_function(self) -> None:
        db = FakePool()
        db.row = clinical_row()
        result = asyncio.run(
            xml.replace_record_content(
                request(db),
                1,
                xml.NodeReplace(xpath="/gh:root/gh:item", value="changed"),
            )
        )
        self.assertEqual(result["record_id"], 1)
        self.assertIn("xml_replace_node_text", db.calls[0][0])

    def test_internal_delete_uses_database_function(self) -> None:
        db = FakePool()
        db.row = clinical_row()
        result = asyncio.run(
            xml.remove_record_content(
                request(db), 1, xml.NodeRemove(xpath="/gh:root/gh:notes")
            )
        )
        self.assertEqual(result["record_id"], 1)
        self.assertIn("xml_remove_nodes", db.calls[0][0])

    def test_native_xpath_and_xmltable_queries(self) -> None:
        db = FakePool()
        db.row = {"nodes": ["<diagnosis>ok</diagnosis>"]}
        extracted = asyncio.run(
            xml.extract_record_nodes(request(db), 1, "/gh:root/gh:diagnosis", "{}")
        )
        self.assertEqual(len(extracted["nodes"]), 1)
        self.assertIn("xpath(", db.calls[-1][0])
        db.rows = [{"record_id": 1, "patient_id": "PAT-000123"}]
        relational = asyncio.run(xml.relational_records(request(db)))
        self.assertEqual(relational[0]["patient_id"], "PAT-000123")
        self.assertIn("clinical_record_relational", db.calls[-1][0])


class XmlRouterRegistrationTests(unittest.TestCase):
    def test_all_routes_are_under_api_xml(self) -> None:
        self.assertTrue(xml.router.routes)
        self.assertTrue(all(route.path.startswith("/api/xml/") for route in xml.router.routes))
