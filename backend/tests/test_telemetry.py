import os
import unittest
from datetime import UTC, datetime
from unittest.mock import patch

from fastapi import HTTPException

from app.routers.telemetry import mongodb_health, telemetry_summary


class FakeAdmin:
    def command(self, command: str) -> None:
        if command != "ping":
            raise AssertionError("unexpected command")


class FakeClient:
    admin = FakeAdmin()


class FakeCollection:
    def __init__(self) -> None:
        self.pipeline = None

    def aggregate(self, pipeline):
        self.pipeline = pipeline
        return [
            {
                "patientId": "P001",
                "sensorType": "heart_rate",
                "sampleCount": 2,
            }
        ]


class FakeDatabase:
    name = "globalhealth_test"
    client = FakeClient()

    def __init__(self) -> None:
        self.sensor_logs = FakeCollection()

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
