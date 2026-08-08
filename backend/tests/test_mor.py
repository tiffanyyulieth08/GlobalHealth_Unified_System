import asyncio
import json
import unittest
from datetime import date

import asyncpg
from fastapi import HTTPException, Request

from app.routers import mor


def make_request(pool) -> Request:
    scope = {
        "type": "http",
        "asgi": {"version": "3.0", "spec_version": "2.3"},
        "http_version": "1.1",
        "server": ("testserver", 80),
        "client": ("testclient", 50000),
        "scheme": "http",
        "method": "GET",
        "root_path": "",
        "path": "/api/mor/clinics",
        "raw_path": b"/api/mor/clinics",
        "query_string": b"",
        "headers": [],
        "state": {},
    }
    request = Request(scope)

    class State:
        write_pool = pool

    class App:
        state = State()

    scope["app"] = App()
    return request


def record(payload: dict) -> dict:
    return {"row": json.dumps(payload)}


class FakePool:
    def __init__(self) -> None:
        self.rows: list = []
        self.row = None
        self.val = None
        self.raises: Exception | None = None
        self.next_rows: list = []

    async def fetch(self, sql: str, *args):
        return self.rows

    async def fetchrow(self, sql: str, *args):
        if self.raises is not None:
            raise self.raises
        if self.next_rows:
            return self.next_rows.pop(0)
        return self.row

    async def fetchval(self, sql: str, *args):
        if self.raises is not None:
            raise self.raises
        return self.val

    async def execute(self, sql: str, *args):
        return "DELETE 1"


CLINIC = {
    "id": 1,
    "name": "GlobalHealth San Jose",
    "address": {
        "street": "Av. 1",
        "city": "San Jose",
        "state": "San Jose",
        "zip": "10101",
        "country": "Costa Rica",
    },
    "equipments": [
        {
            "brand": "Siemens",
            "model": "MAGNETOM Vida",
            "serial_number": "MRI-SN-001",
            "acquisition_year": 2021,
            "status": "operational",
            "warranty_months": 24,
        }
    ],
}

DOCTOR = {
    "id": 101,
    "first_name": "Ana",
    "last_name": "Solano",
    "email": "ana.solano@globalhealth.cr",
    "hire_date": "2020-03-10",
    "address": None,
    "phone": {"country_code": "506", "number": "2222-3344", "kind": "work"},
    "salary": 12000.0,
    "specialty": "Cardiologia",
    "license": "MED-1234",
    "specialties": ["Cardiologia", "Medicina Interna"],
    "clinic_id": 1,
    "phone_numbers": [
        {"country_code": "506", "number": "8888-5566", "kind": "mobile"}
    ],
}


class MorRouterTests(unittest.TestCase):
    def test_list_clinics_parses_rows(self) -> None:
        pool = FakePool()
        pool.rows = [record(CLINIC), record({**CLINIC, "id": 2})]
        result = asyncio.run(mor.list_clinics(make_request(pool)))
        self.assertEqual(len(result), 2)
        self.assertEqual(result[0]["id"], 1)
        self.assertEqual(result[1]["id"], 2)

    def test_create_clinic_returns_created(self) -> None:
        pool = FakePool()
        pool.row = record({**CLINIC, "id": 3, "name": "GlobalHealth Cartago"})
        result = asyncio.run(
            mor.create_clinic(
                make_request(pool),
                mor.ClinicCreate(name="GlobalHealth Cartago"),
            )
        )
        self.assertEqual(result["id"], 3)
        self.assertEqual(result["name"], "GlobalHealth Cartago")

    def test_get_clinic_not_found_raises_404(self) -> None:
        pool = FakePool()
        pool.row = None
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(mor.get_clinic(make_request(pool), 999))
        self.assertEqual(raised.exception.status_code, 404)

    def test_update_clinic(self) -> None:
        pool = FakePool()
        pool.row = record({**CLINIC, "name": "GlobalHealth San Jose Norte"})
        result = asyncio.run(
            mor.update_clinic(
                make_request(pool),
                1,
                mor.ClinicUpdate(name="GlobalHealth San Jose Norte"),
            )
        )
        self.assertEqual(result["name"], "GlobalHealth San Jose Norte")

    def test_delete_clinic(self) -> None:
        pool = FakePool()
        pool.row = record(CLINIC)
        result = asyncio.run(mor.delete_clinic(make_request(pool), 1))
        self.assertEqual(result["id"], 1)

    def test_add_equipment_returns_count(self) -> None:
        pool = FakePool()
        pool.row = record(CLINIC)
        pool.val = 2
        result = asyncio.run(
            mor.add_equipment(
                make_request(pool),
                1,
                mor.Equipment(brand="GE", model="Revolution", serial_number="CT-SN-002"),
            )
        )
        self.assertEqual(result["equipment_count"], 2)
        self.assertEqual(result["clinic_id"], 1)

    def test_update_equipment_by_serial(self) -> None:
        pool = FakePool()
        updated_equipment = {
            **CLINIC["equipments"][0],
            "status": "maintenance",
        }
        pool.next_rows = [
            record(CLINIC),
            record({**CLINIC, "equipments": [updated_equipment]}),
        ]
        result = asyncio.run(
            mor.update_equipment(
                make_request(pool),
                1,
                "MRI-SN-001",
                mor.EquipmentUpdate(status="maintenance"),
            )
        )
        self.assertEqual(result["status"], "maintenance")

    def test_update_equipment_not_found_raises_404(self) -> None:
        pool = FakePool()
        pool.row = record(CLINIC)
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(
                mor.update_equipment(
                    make_request(pool),
                    1,
                    "UNKNOWN",
                    mor.EquipmentUpdate(status="maintenance"),
                )
            )
        self.assertEqual(raised.exception.status_code, 404)

    def test_delete_equipment(self) -> None:
        pool = FakePool()
        pool.next_rows = [record(CLINIC), record({**CLINIC, "equipments": []})]
        result = asyncio.run(
            mor.delete_equipment(make_request(pool), 1, "MRI-SN-001")
        )
        self.assertEqual(result["serial_number"], "MRI-SN-001")

    def test_list_doctors_with_filters(self) -> None:
        pool = FakePool()
        pool.rows = [record(DOCTOR)]
        result = asyncio.run(
            mor.list_doctors(make_request(pool), clinic_id=1, specialty="Cardiologia")
        )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["license"], "MED-1234")

    def test_create_doctor_defaults_hire_date(self) -> None:
        pool = FakePool()
        pool.row = record(DOCTOR)
        asyncio.run(
            mor.create_doctor(
                make_request(pool),
                mor.DoctorCreate(
                    first_name="Ana",
                    last_name="Solano",
                    email="ana.solano@globalhealth.cr",
                    specialty="Cardiologia",
                    license="MED-1234",
                ),
            )
        )

    def test_create_doctor_serializes_explicit_hire_date(self) -> None:
        pool = FakePool()
        pool.row = record(DOCTOR)
        asyncio.run(
            mor.create_doctor(
                make_request(pool),
                mor.DoctorCreate(
                    first_name="Ana",
                    last_name="Solano",
                    email="ana.solano@globalhealth.cr",
                    hire_date=date(2021, 5, 1),
                    specialty="Cardiologia",
                    license="MED-1234",
                ),
            )
        )

    def test_get_doctor_not_found_raises_404(self) -> None:
        pool = FakePool()
        pool.row = None
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(mor.get_doctor(make_request(pool), 999))
        self.assertEqual(raised.exception.status_code, 404)

    def test_update_doctor_merges_payload(self) -> None:
        pool = FakePool()
        pool.next_rows = [
            record(DOCTOR),
            record({**DOCTOR, "salary": 15000.0}),
        ]
        result = asyncio.run(
            mor.update_doctor(make_request(pool), 101, mor.DoctorUpdate(salary=15000.0))
        )
        self.assertEqual(result["salary"], 15000.0)

    def test_delete_doctor(self) -> None:
        pool = FakePool()
        pool.row = record(DOCTOR)
        result = asyncio.run(mor.delete_doctor(make_request(pool), 101))
        self.assertEqual(result["id"], 101)

    def test_add_specialty_returns_array(self) -> None:
        pool = FakePool()
        pool.row = record({**DOCTOR, "specialties": ["Cardiologia", "Pediatria"]})
        result = asyncio.run(
            mor.add_specialty(
                make_request(pool),
                101,
                mor.SpecialtyCreate(specialty="Pediatria"),
            )
        )
        self.assertIn("Pediatria", result["specialties"])

    def test_add_duplicate_specialty_raises_409(self) -> None:
        pool = FakePool()
        pool.next_rows = [record(DOCTOR)]
        pool.row = None
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(
                mor.add_specialty(
                    make_request(pool),
                    101,
                    mor.SpecialtyCreate(specialty="Cardiologia"),
                )
            )
        self.assertEqual(raised.exception.status_code, 409)

    def test_delete_specialty_not_found_raises_404(self) -> None:
        pool = FakePool()
        pool.row = None
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(mor.delete_specialty(make_request(pool), 101, "Urologia"))
        self.assertEqual(raised.exception.status_code, 404)

    def test_add_phone(self) -> None:
        pool = FakePool()
        pool.row = record({**DOCTOR, "phone_numbers": DOCTOR["phone_numbers"]})
        result = asyncio.run(
            mor.add_phone(
                make_request(pool),
                101,
                mor.Phone(country_code="506", number="8888-5566", kind="mobile"),
            )
        )
        self.assertEqual(len(result["phone_numbers"]), 1)

    def test_delete_phone_not_found_raises_404(self) -> None:
        pool = FakePool()
        pool.row = None
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(
                mor.delete_phone(make_request(pool), 101, "506", "9999-9999")
            )
        self.assertEqual(raised.exception.status_code, 404)


class MorErrorMappingTests(unittest.TestCase):
    def test_unique_violation_maps_to_409(self) -> None:
        pool = FakePool()
        pool.raises = asyncpg.UniqueViolationError("duplicate")
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(
                mor.create_clinic(
                    make_request(pool),
                    mor.ClinicCreate(name="GlobalHealth San Jose"),
                )
            )
        self.assertEqual(raised.exception.status_code, 409)

    def test_foreign_key_violation_maps_to_409(self) -> None:
        pool = FakePool()
        pool.raises = asyncpg.ForeignKeyViolationError("fk")
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(mor.delete_clinic(make_request(pool), 1))
        self.assertEqual(raised.exception.status_code, 409)

    def test_check_violation_maps_to_422(self) -> None:
        pool = FakePool()
        pool.raises = asyncpg.CheckViolationError("check")
        with self.assertRaises(HTTPException) as raised:
            asyncio.run(
                mor.create_doctor(
                    make_request(pool),
                    mor.DoctorCreate(
                        first_name="X",
                        last_name="Y",
                        email="x.y@globalhealth.cr",
                        specialty="D",
                        license="L",
                    ),
                )
            )
        self.assertEqual(raised.exception.status_code, 422)
