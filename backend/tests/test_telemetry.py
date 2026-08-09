import os
import unittest
from datetime import UTC, datetime
from unittest.mock import patch

from fastapi import HTTPException
from pymongo import DESCENDING

from app.routers.telemetry import (
    PatientUpdate,
    get_patient,
    list_sessions,
    mongodb_health,
    telemetry_summary,
    update_patient,
)


class FakeAdmin:
    def command(self, command: str) -> None:
        if command != "ping":
            raise AssertionError("unexpected command")


class FakeClient:
    admin = FakeAdmin()


class FakeCursor:
    def __init__(self, documents: list[dict], collection) -> None:
        self._documents = documents
        self._collection = collection

    def sort(self, key, direction):
        self._collection.sort_key = (key, direction)
        return self

    def limit(self, value):
        self._collection.limit_value = value
        return self

    def __iter__(self):
        return iter(self._documents)


class FakeCollection:
    def __init__(self, documents: list[dict] | None = None) -> None:
        self.pipeline = None
        self._documents = documents or []
        self.filters = None
        self.update = None
        self.sort_key = None
        self.limit_value = None

    def aggregate(self, pipeline):
        self.pipeline = pipeline
        return [
            {
                "patientId": "P001",
                "sensorType": "heart_rate",
                "sampleCount": 2,
            }
        ]

    def find(self, filters, projection=None):
        self.filters = filters
        return FakeCursor(self._documents, self)

    def find_one(self, filters, projection=None):
        self.filters = filters
        if self._documents:
            return dict(self._documents[0])
        return None

    def find_one_and_update(self, filters, update, return_document=None, projection=None):
        self.filters = filters
        self.update = update
        if not self._documents:
            return None
        return {**dict(self._documents[0]), **update["$set"]}


class FakeDatabase:
    name = "globalhealth_test"
    client = FakeClient()

    def __init__(self) -> None:
        self.sensor_logs = FakeCollection()
        self.patients = FakeCollection(
            [
                {
                    "patientId": "P001",
                    "firstName": "Ana",
                    "lastName": "Solis",
                    "active": True,
                }
            ]
        )
        self.sessions = FakeCollection(
            [
                {
                    "sessionId": "S001",
                    "patientId": "P001",
                    "deviceId": "ECG-CR-001",
                    "status": "active",
                }
            ]
        )

    def command(self, command: str) -> None:
        self.client.admin.command(command)


class TelemetryTests(unittest.TestCase):
    def test_health_is_sanitized(self) -> None:
        database = FakeDatabase()
        with patch.dict(
            os.environ,
            {"MONGODB_PROVIDER": "atlas", "MONGODB_URI": "mongodb+srv://safe.invalid/db"},
            clear=False,
        ):
            result = mongodb_health(database)
        self.assertEqual(
            result,
            {
                "status": "healthy",
                "provider": "atlas",
                "database": "globalhealth_test",
            },
        )

    def test_summary_contains_group_lookup_and_limit(self) -> None:
        database = FakeDatabase()
        result = telemetry_summary(
            database=database,
            patient_id="P001",
            recorded_from=None,
            recorded_to=None,
            limit=10,
        )
        pipeline = database.sensor_logs.pipeline
        self.assertEqual(result["count"], 1)
        self.assertTrue(any("$group" in stage for stage in pipeline))
        self.assertTrue(any("$lookup" in stage for stage in pipeline))
        self.assertEqual(pipeline[-1], {"$limit": 10})

    def test_summary_rejects_inverted_date_range(self) -> None:
        database = FakeDatabase()
        with self.assertRaises(HTTPException) as raised:
            telemetry_summary(
                database=database,
                patient_id=None,
                recorded_from=datetime(2026, 8, 5, tzinfo=UTC),
                recorded_to=datetime(2026, 8, 4, tzinfo=UTC),
                limit=50,
            )
        self.assertEqual(raised.exception.status_code, 422)


class PatientEndpointTests(unittest.TestCase):
    def test_get_patient_returns_document(self) -> None:
        database = FakeDatabase()
        result = get_patient("P001", database)
        self.assertEqual(database.patients.filters, {"patientId": "P001"})
        self.assertEqual(result["patientId"], "P001")
        self.assertNotIn("_id", result)

    def test_get_patient_raises_when_missing(self) -> None:
        database = FakeDatabase()
        database.patients._documents = []
        with self.assertRaises(HTTPException) as raised:
            get_patient("MISSING", database)
        self.assertEqual(raised.exception.status_code, 404)

    def test_update_patient_sets_only_provided_fields(self) -> None:
        database = FakeDatabase()
        result = update_patient("P001", PatientUpdate(first_name="Renamed"), database)
        self.assertEqual(database.patients.filters, {"patientId": "P001"})
        self.assertEqual(database.patients.update["$set"]["firstName"], "Renamed")
        self.assertEqual(result["firstName"], "Renamed")
        self.assertIn("updatedAt", database.patients.update["$set"])
        self.assertNotIn("lastName", database.patients.update["$set"])

    def test_update_patient_raises_when_missing(self) -> None:
        database = FakeDatabase()
        database.patients._documents = []
        with self.assertRaises(HTTPException) as raised:
            update_patient("MISSING", PatientUpdate(first_name="Renamed"), database)
        self.assertEqual(raised.exception.status_code, 404)

    def test_update_patient_rejects_empty_payload(self) -> None:
        database = FakeDatabase()
        with self.assertRaises(HTTPException) as raised:
            update_patient("P001", PatientUpdate(), database)
        self.assertEqual(raised.exception.status_code, 422)


class SessionEndpointTests(unittest.TestCase):
    def test_list_sessions_filters_by_patient_with_limit_and_order(self) -> None:
        database = FakeDatabase()
        result = list_sessions(
            database,
            patient_id="P001",
            session_status=None,
            limit=5,
        )
        self.assertEqual(database.sessions.filters, {"patientId": "P001"})
        self.assertEqual(database.sessions.sort_key, ("startedAt", DESCENDING))
        self.assertEqual(database.sessions.limit_value, 5)
        self.assertEqual(result[0]["sessionId"], "S001")

    def test_list_sessions_filters_by_patient_and_status(self) -> None:
        database = FakeDatabase()
        list_sessions(
            database,
            patient_id="P001",
            session_status="active",
            limit=20,
        )
        self.assertEqual(
            database.sessions.filters,
            {"patientId": "P001", "status": "active"},
        )
