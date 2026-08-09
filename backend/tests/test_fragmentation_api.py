import asyncio
import json
import unittest
from decimal import Decimal
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from fastapi import Request

from app.main import app
from app.routers.fragmentation import (
    horizontal_fragmentation,
    horizontal_fragmentation_summary,
    vertical_fragmentation,
    vertical_fragmentation_summary,
)
from app.routers.infrastructure import infrastructure_status


class FakePool:
    def __init__(self, rows=None, row=None, value=None) -> None:
        self.rows = rows or []
        self.row = row
        self.value = value
        self.query = None
        self.arguments = None

    async def fetch(self, query, *arguments):
        self.query = query
        self.arguments = arguments
        return self.rows

    async def fetchrow(self, query, *arguments):
        self.query = query
        self.arguments = arguments
        return self.row

    async def fetchval(self, query, *arguments):
        self.query = query
        self.arguments = arguments
        return self.value


def request_with_state(**state) -> Request:
    app = SimpleNamespace(state=SimpleNamespace(**state))
    return Request({"type": "http", "app": app})


class FragmentationApiTests(unittest.TestCase):
    def test_new_endpoints_are_get_only(self) -> None:
        expected = {
            "/api/fragmentation/horizontal",
            "/api/fragmentation/horizontal/summary",
            "/api/fragmentation/vertical",
            "/api/fragmentation/vertical/summary",
            "/api/infrastructure/status",
        }
        methods = {
            route.path: route.methods
            for route in app.routes
            if route.path in expected
        }
        self.assertEqual(set(methods), expected)
        self.assertTrue(all(route_methods == {"GET"} for route_methods in methods.values()))

    def test_horizontal_reads_patients_all(self) -> None:
        pool = FakePool(rows=[{"patientId": 1, "fullName": "Ana", "region": "NORTH"}])
        result = asyncio.run(
            horizontal_fragmentation(
                request_with_state(horizontal_fragmentation_pool=pool), 25
            )
        )
        self.assertIn("FROM patients_all", pool.query)
        self.assertNotIn("UNION", pool.query)
        self.assertNotRegex(pool.query, r"(?i)\b(INSERT|UPDATE|DELETE|TRUNCATE)\b")
        self.assertEqual(pool.arguments, (25,))
        self.assertEqual(result["patients"][0]["region"], "NORTH")

    def test_horizontal_summary_counts_regions_from_patients_all(self) -> None:
        pool = FakePool(row={"total": 10, "north": 5, "south": 5})
        result = asyncio.run(
            horizontal_fragmentation_summary(
                request_with_state(horizontal_fragmentation_pool=pool)
            )
        )
        self.assertIn("FROM patients_all", pool.query)
        self.assertEqual(result["regions"], {"NORTH": 5, "SOUTH": 5})

    def test_vertical_reads_patients_full_and_labels_field_sources(self) -> None:
        pool = FakePool(
            rows=[
                {
                    "patientId": 1,
                    "fullName": "Ana",
                    "outstandingBalance": Decimal("25.50"),
                }
            ]
        )
        result = asyncio.run(
            vertical_fragmentation(
                request_with_state(vertical_fragmentation_pool=pool), 30
            )
        )
        self.assertIn("FROM patients_full", pool.query)
        self.assertNotIn("JOIN", pool.query)
        self.assertNotRegex(pool.query, r"(?i)\b(INSERT|UPDATE|DELETE|TRUNCATE)\b")
        self.assertIn("fullName", result["fieldSources"]["public"])
        self.assertIn("outstandingBalance", result["fieldSources"]["financial"])
        self.assertEqual(result["patients"][0]["outstandingBalance"], 25.5)

    def test_vertical_summary_counts_patients_full(self) -> None:
        pool = FakePool(value=6)
        result = asyncio.run(
            vertical_fragmentation_summary(
                request_with_state(vertical_fragmentation_pool=pool)
            )
        )
        self.assertEqual(pool.query, "SELECT count(*) FROM patients_full")
        self.assertEqual(result["reconstructedPatients"], 6)

    @patch("app.routers.infrastructure.get_settings")
    def test_infrastructure_status_is_sanitized(self, settings) -> None:
        settings.return_value.mongodb_provider = "local"
        primary = FakePool(value=False)
        replica = FakePool(value=True)
        database = MagicMock()
        response = asyncio.run(
            infrastructure_status(
                request_with_state(write_pool=primary, read_pool=replica), database
            )
        )
        payload = json.loads(response.body)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(payload["primary"]["inRecovery"], False)
        self.assertEqual(payload["replica"]["inRecovery"], True)
        self.assertEqual(payload["mongodb"], {"status": "healthy", "provider": "local"})
        self.assertNotRegex(response.body.decode(), r"postgres(ql)?://|mongodb://|password")
        self.assertEqual(primary.query, "SELECT pg_is_in_recovery()")
        self.assertEqual(replica.query, "SELECT pg_is_in_recovery()")


if __name__ == "__main__":
    unittest.main()
