import json
from datetime import date
from decimal import Decimal
from typing import Annotated, Any, NoReturn

import asyncpg
from fastapi import APIRouter, HTTPException, Query, Request, status
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/mor", tags=["mor"])


class Address(BaseModel):
    street: str | None = Field(default=None, max_length=120)
    city: str | None = Field(default=None, max_length=80)
    state: str | None = Field(default=None, max_length=80)
    zip: str | None = Field(default=None, max_length=20)
    country: str | None = Field(default=None, max_length=80)


class Phone(BaseModel):
    country_code: str | None = Field(default=None, max_length=6)
    number: str | None = Field(default=None, max_length=20)
    kind: str | None = Field(default=None, max_length=20)


class Equipment(BaseModel):
    brand: str | None = Field(default=None, max_length=60)
    model: str | None = Field(default=None, max_length=60)
    serial_number: str | None = Field(default=None, max_length=60)
    acquisition_year: int | None = Field(default=None, ge=1900, le=2100)
    status: str | None = Field(default=None, max_length=20)
    warranty_months: int | None = Field(default=None, ge=0)


class EquipmentUpdate(Equipment):
    serial_number: str | None = None


class ClinicCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    address: Address | None = None
    equipments: list[Equipment] | None = None


class ClinicUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    address: Address | None = None


class DoctorCreate(BaseModel):
    first_name: str = Field(min_length=1, max_length=60)
    last_name: str = Field(min_length=1, max_length=60)
    email: str = Field(min_length=1, max_length=120)
    hire_date: date | None = None
    address: Address | None = None
    phone: Phone | None = None
    salary: Decimal | None = Field(default=None, ge=0)
    specialty: str = Field(min_length=1, max_length=80)
    license: str = Field(min_length=1, max_length=40)
    specialties: list[str] | None = None
    clinic_id: int | None = None
    phone_numbers: list[Phone] | None = None


class DoctorUpdate(BaseModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=60)
    last_name: str | None = Field(default=None, min_length=1, max_length=60)
    email: str | None = Field(default=None, min_length=1, max_length=120)
    hire_date: date | None = None
    address: Address | None = None
    phone: Phone | None = None
    salary: Decimal | None = Field(default=None, ge=0)
    specialty: str | None = Field(default=None, min_length=1, max_length=80)
    license: str | None = Field(default=None, min_length=1, max_length=40)
    specialties: list[str] | None = None
    clinic_id: int | None = None
    phone_numbers: list[Phone] | None = None


class SpecialtyCreate(BaseModel):
    specialty: str = Field(min_length=1, max_length=80)


def get_pool(request: Request) -> asyncpg.Pool:
    return request.app.state.write_pool


def raise_mor_http(error: Exception) -> NoReturn:
    if isinstance(error, asyncpg.UniqueViolationError):
        raise HTTPException(status_code=409, detail="Integrity conflict: duplicate value")
    if isinstance(error, asyncpg.ForeignKeyViolationError):
        raise HTTPException(
            status_code=409,
            detail="Integrity conflict: invalid or in-use reference",
        )
    if isinstance(
        error,
        (asyncpg.CheckViolationError, asyncpg.NotNullViolationError, asyncpg.DataError),
    ):
        raise HTTPException(status_code=422, detail="Invalid data rejected by the database")
    raise HTTPException(status_code=503, detail="PostgreSQL operation failed")


def parse_row(row: asyncpg.Record | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return json.loads(row["row"])


def find_equipment(
    clinic: dict[str, Any],
    serial_number: str,
) -> dict[str, Any] | None:
    for equipment in clinic.get("equipments") or []:
        if equipment.get("serial_number") == serial_number:
            return equipment
    return None


def doctor_insert_payload(doctor: DoctorCreate) -> dict[str, Any]:
    payload = doctor.model_dump(mode="json")
    if payload.get("hire_date") is None:
        payload["hire_date"] = date.today().isoformat()
    return payload


def merge_payload(current: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any]:
    merged = dict(current)
    merged.update({key: value for key, value in payload.items() if value is not None})
    return merged


CLINIC_INSERT_SQL = """
    INSERT INTO clinic (name, address, equipments)
    SELECT r.name, r.address, r.equipments
    FROM jsonb_populate_record(NULL::clinic_t, $1::jsonb) AS r
    RETURNING to_jsonb(clinic.*) AS row
"""

CLINIC_LIST_SQL = """
    SELECT to_jsonb(c.*) AS row
    FROM clinic c
    ORDER BY c.id
"""

CLINIC_GET_SQL = """
    SELECT to_jsonb(c.*) AS row
    FROM clinic c
    WHERE c.id = $1
"""

CLINIC_UPDATE_SQL = """
    UPDATE clinic c
    SET name = COALESCE($2::varchar, c.name),
        address = COALESCE(jsonb_populate_record(NULL::address_t, $3::jsonb), c.address)
    WHERE c.id = $1
    RETURNING to_jsonb(c.*) AS row
"""

CLINIC_DELETE_SQL = "DELETE FROM clinic WHERE id = $1 RETURNING to_jsonb(clinic.*) AS row"

EQUIPMENT_ADD_SQL = """
    SELECT register_equipment(
        $1,
        jsonb_populate_record(NULL::equipment_t, $2::jsonb)::equipment_t
    ) AS count
"""

EQUIPMENT_UPDATE_SQL = """
    UPDATE clinic c
    SET equipments = (
        SELECT array_agg(
            CASE WHEN e.serial_number = $2
                THEN jsonb_populate_record(NULL::equipment_t, $3::jsonb)::equipment_t
                ELSE e
            END
        )
        FROM unnest(c.equipments) AS e
    )
    WHERE c.id = $1
    RETURNING to_jsonb(c.*) AS row
"""

EQUIPMENT_DELETE_SQL = """
    UPDATE clinic c
    SET equipments = COALESCE(
        (
            SELECT array_agg(e)
            FROM unnest(c.equipments) AS e
            WHERE e.serial_number <> $2
        ),
        ARRAY[]::equipment_t[]
    )
    WHERE c.id = $1
    RETURNING to_jsonb(c.*) AS row
"""

DOCTOR_INSERT_SQL = """
    INSERT INTO doctor
    (first_name, last_name, email, hire_date, address, phone, salary,
     specialty, license, specialties, clinic_id, phone_numbers)
    SELECT first_name, last_name, email, hire_date, address, phone, salary,
           specialty, license, specialties, clinic_id, phone_numbers
    FROM jsonb_populate_record(NULL::doctor, $1::jsonb)
    RETURNING to_jsonb(doctor.*) AS row
"""

DOCTOR_LIST_SQL = """
    SELECT to_jsonb(d.*) AS row
    FROM doctor d
    WHERE ($1::int IS NULL OR d.clinic_id = $1)
      AND ($2::text IS NULL OR d.specialty = $2 OR $2 = ANY(d.specialties))
    ORDER BY d.id
"""

DOCTOR_GET_SQL = """
    SELECT to_jsonb(d.*) AS row
    FROM doctor d
    WHERE d.id = $1
"""

DOCTOR_UPDATE_SQL = """
    UPDATE doctor d
    SET first_name = r.first_name,
        last_name = r.last_name,
        email = r.email,
        hire_date = r.hire_date,
        address = r.address,
        phone = r.phone,
        salary = r.salary,
        specialty = r.specialty,
        license = r.license,
        specialties = r.specialties,
        clinic_id = r.clinic_id,
        phone_numbers = r.phone_numbers
    FROM jsonb_populate_record(NULL::doctor, $1::jsonb) AS r
    WHERE d.id = $2
    RETURNING to_jsonb(d.*) AS row
"""

DOCTOR_DELETE_SQL = "DELETE FROM doctor WHERE id = $1 RETURNING to_jsonb(doctor.*) AS row"

SPECIALTY_ADD_SQL = """
    UPDATE doctor d
    SET specialties = COALESCE(d.specialties, ARRAY[]::varchar[]) || $2::varchar
    WHERE d.id = $1
      AND NOT ($2 = ANY(COALESCE(d.specialties, ARRAY[]::varchar[])))
    RETURNING to_jsonb(d.*) AS row
"""

SPECIALTY_DELETE_SQL = """
    UPDATE doctor d
    SET specialties = COALESCE(
        (
            SELECT array_agg(s)
            FROM unnest(d.specialties) AS s
            WHERE s <> $2
        ),
        ARRAY[]::varchar[]
    )
    WHERE d.id = $1
      AND ($2 = ANY(d.specialties))
    RETURNING to_jsonb(d.*) AS row
"""

PHONE_ADD_SQL = """
    UPDATE doctor d
    SET phone_numbers = COALESCE(d.phone_numbers, ARRAY[]::phone_t[]) ||
        jsonb_populate_record(NULL::phone_t, $2::jsonb)::phone_t
    WHERE d.id = $1
    RETURNING to_jsonb(d.*) AS row
"""

PHONE_DELETE_SQL = """
    UPDATE doctor d
    SET phone_numbers = COALESCE(
        (
            SELECT array_agg(p)
            FROM unnest(d.phone_numbers) AS p
            WHERE NOT (p.country_code = $2 AND p.number = $3)
        ),
        ARRAY[]::phone_t[]
    )
    WHERE d.id = $1
      AND EXISTS (
          SELECT 1
          FROM unnest(d.phone_numbers) AS p
          WHERE p.country_code = $2 AND p.number = $3
      )
    RETURNING to_jsonb(d.*) AS row
"""


@router.get("/clinics")
async def list_clinics(request: Request) -> list[dict[str, Any]]:
    try:
        rows = await get_pool(request).fetch(CLINIC_LIST_SQL)
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    return [parse_row(row) for row in rows]


@router.post("/clinics", status_code=status.HTTP_201_CREATED)
async def create_clinic(request: Request, clinic: ClinicCreate) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(
            CLINIC_INSERT_SQL,
            json.dumps(clinic.model_dump()),
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    return parse_row(row)


@router.get("/clinics/{clinic_id}")
async def get_clinic(request: Request, clinic_id: int) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(CLINIC_GET_SQL, clinic_id)
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    clinic = parse_row(row)
    if clinic is None:
        raise HTTPException(status_code=404, detail="clinic not found")
    return clinic


@router.patch("/clinics/{clinic_id}")
async def update_clinic(
    request: Request,
    clinic_id: int,
    clinic: ClinicUpdate,
) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(
            CLINIC_UPDATE_SQL,
            clinic_id,
            clinic.name,
            json.dumps(clinic.address.model_dump()) if clinic.address is not None else None,
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    updated = parse_row(row)
    if updated is None:
        raise HTTPException(status_code=404, detail="clinic not found")
    return updated


@router.delete("/clinics/{clinic_id}")
async def delete_clinic(request: Request, clinic_id: int) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(CLINIC_DELETE_SQL, clinic_id)
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    deleted = parse_row(row)
    if deleted is None:
        raise HTTPException(status_code=404, detail="clinic not found")
    return deleted


@router.get("/clinics/{clinic_id}/equipments")
async def list_equipments(request: Request, clinic_id: int) -> list[dict[str, Any]]:
    clinic = await get_clinic(request, clinic_id)
    return clinic.get("equipments") or []


@router.post(
    "/clinics/{clinic_id}/equipments",
    status_code=status.HTTP_201_CREATED,
)
async def add_equipment(
    request: Request,
    clinic_id: int,
    equipment: Equipment,
) -> dict[str, Any]:
    if await get_clinic(request, clinic_id) is None:
        raise HTTPException(status_code=404, detail="clinic not found")
    try:
        count = await get_pool(request).fetchval(
            EQUIPMENT_ADD_SQL,
            clinic_id,
            json.dumps(equipment.model_dump()),
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    return {
        "clinic_id": clinic_id,
        "equipment": equipment.model_dump(),
        "equipment_count": count,
    }


@router.put("/clinics/{clinic_id}/equipments/{serial_number}")
async def update_equipment(
    request: Request,
    clinic_id: int,
    serial_number: str,
    equipment: EquipmentUpdate,
) -> dict[str, Any]:
    clinic = await get_clinic(request, clinic_id)
    current = find_equipment(clinic, serial_number)
    if current is None:
        raise HTTPException(status_code=404, detail="equipment not found")
    updated_payload = merge_payload(current, equipment.model_dump())
    updated_payload["serial_number"] = serial_number
    try:
        row = await get_pool(request).fetchrow(
            EQUIPMENT_UPDATE_SQL,
            clinic_id,
            serial_number,
            json.dumps(updated_payload),
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    updated_clinic = parse_row(row)
    updated = find_equipment(updated_clinic, serial_number)
    if updated is None:
        raise HTTPException(status_code=404, detail="equipment not found")
    return updated


@router.delete("/clinics/{clinic_id}/equipments/{serial_number}")
async def delete_equipment(
    request: Request,
    clinic_id: int,
    serial_number: str,
) -> dict[str, Any]:
    clinic = await get_clinic(request, clinic_id)
    current = find_equipment(clinic, serial_number)
    if current is None:
        raise HTTPException(status_code=404, detail="equipment not found")
    try:
        row = await get_pool(request).fetchrow(
            EQUIPMENT_DELETE_SQL,
            clinic_id,
            serial_number,
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    updated_clinic = parse_row(row)
    if find_equipment(updated_clinic, serial_number) is not None:
        raise HTTPException(status_code=503, detail="PostgreSQL operation failed")
    return current


@router.get("/doctors")
async def list_doctors(
    request: Request,
    clinic_id: Annotated[int | None, Query()] = None,
    specialty: Annotated[str | None, Query()] = None,
) -> list[dict[str, Any]]:
    try:
        rows = await get_pool(request).fetch(DOCTOR_LIST_SQL, clinic_id, specialty)
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    return [parse_row(row) for row in rows]


@router.post("/doctors", status_code=status.HTTP_201_CREATED)
async def create_doctor(request: Request, doctor: DoctorCreate) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(
            DOCTOR_INSERT_SQL,
            json.dumps(doctor_insert_payload(doctor)),
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    return parse_row(row)


@router.get("/doctors/{doctor_id}")
async def get_doctor(request: Request, doctor_id: int) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(DOCTOR_GET_SQL, doctor_id)
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    doctor = parse_row(row)
    if doctor is None:
        raise HTTPException(status_code=404, detail="doctor not found")
    return doctor


@router.patch("/doctors/{doctor_id}")
async def update_doctor(
    request: Request,
    doctor_id: int,
    doctor: DoctorUpdate,
) -> dict[str, Any]:
    current = await get_doctor(request, doctor_id)
    merged = merge_payload(current, doctor.model_dump(mode="json"))
    try:
        row = await get_pool(request).fetchrow(
            DOCTOR_UPDATE_SQL,
            json.dumps(merged),
            doctor_id,
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    updated = parse_row(row)
    if updated is None:
        raise HTTPException(status_code=404, detail="doctor not found")
    return updated


@router.delete("/doctors/{doctor_id}")
async def delete_doctor(request: Request, doctor_id: int) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(DOCTOR_DELETE_SQL, doctor_id)
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    deleted = parse_row(row)
    if deleted is None:
        raise HTTPException(status_code=404, detail="doctor not found")
    return deleted


@router.get("/doctors/{doctor_id}/specialties")
async def list_specialties(request: Request, doctor_id: int) -> list[str]:
    doctor = await get_doctor(request, doctor_id)
    return doctor.get("specialties") or []


@router.post(
    "/doctors/{doctor_id}/specialties",
    status_code=status.HTTP_201_CREATED,
)
async def add_specialty(
    request: Request,
    doctor_id: int,
    specialty: SpecialtyCreate,
) -> dict[str, Any]:
    if await get_doctor(request, doctor_id) is None:
        raise HTTPException(status_code=404, detail="doctor not found")
    try:
        row = await get_pool(request).fetchrow(
            SPECIALTY_ADD_SQL,
            doctor_id,
            specialty.specialty,
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    updated = parse_row(row)
    if updated is None:
        raise HTTPException(
            status_code=409,
            detail="Integrity conflict: specialty already exists",
        )
    return {"specialties": updated.get("specialties") or []}


@router.delete("/doctors/{doctor_id}/specialties/{specialty}")
async def delete_specialty(
    request: Request,
    doctor_id: int,
    specialty: str,
) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(
            SPECIALTY_DELETE_SQL,
            doctor_id,
            specialty,
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    updated = parse_row(row)
    if updated is None:
        raise HTTPException(status_code=404, detail="specialty not found")
    return {"specialties": updated.get("specialties") or []}


@router.get("/doctors/{doctor_id}/phones")
async def list_phones(request: Request, doctor_id: int) -> list[dict[str, Any]]:
    doctor = await get_doctor(request, doctor_id)
    return doctor.get("phone_numbers") or []


@router.post(
    "/doctors/{doctor_id}/phones",
    status_code=status.HTTP_201_CREATED,
)
async def add_phone(
    request: Request,
    doctor_id: int,
    phone: Phone,
) -> dict[str, Any]:
    if await get_doctor(request, doctor_id) is None:
        raise HTTPException(status_code=404, detail="doctor not found")
    try:
        row = await get_pool(request).fetchrow(
            PHONE_ADD_SQL,
            doctor_id,
            json.dumps(phone.model_dump()),
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    updated = parse_row(row)
    return {"phone_numbers": updated.get("phone_numbers") or []}


@router.delete("/doctors/{doctor_id}/phones")
async def delete_phone(
    request: Request,
    doctor_id: int,
    country_code: Annotated[str, Query(alias="countryCode", min_length=1, max_length=6)],
    number: Annotated[str, Query(min_length=1, max_length=20)],
) -> dict[str, Any]:
    try:
        row = await get_pool(request).fetchrow(
            PHONE_DELETE_SQL,
            doctor_id,
            country_code,
            number,
        )
    except asyncpg.PostgresError as error:
        raise_mor_http(error)
    updated = parse_row(row)
    if updated is None:
        raise HTTPException(status_code=404, detail="phone not found")
    return {"phone_numbers": updated.get("phone_numbers") or []}
