from decimal import Decimal
from typing import Annotated, Any

import asyncpg
from fastapi import APIRouter, Query, Request


router = APIRouter(prefix="/api/fragmentation", tags=["fragmentation"])

PUBLIC_FIELDS = [
    "patientId",
    "fullName",
    "phone",
    "email",
    "address",
    "emergencyContact",
]
FINANCIAL_FIELDS = [
    "insuranceProvider",
    "insuranceNumber",
    "billingStatus",
    "outstandingBalance",
    "paymentMethod",
]


def serialize_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    return value


def serialize_row(row: asyncpg.Record) -> dict[str, Any]:
    return {key: serialize_value(value) for key, value in row.items()}


@router.get("/horizontal")
async def horizontal_fragmentation(
    request: Request,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> dict[str, Any]:
    rows = await request.app.state.horizontal_fragmentation_pool.fetch(
        """
        SELECT
            patient_id AS "patientId",
            full_name AS "fullName",
            phone,
            email,
            address,
            region
        FROM patients_all
        ORDER BY patient_id
        LIMIT $1
        """,
        limit,
    )
    return {
        "coordinator": "fragmentation-coordinator-horizontal",
        "view": "patients_all",
        "count": len(rows),
        "limit": limit,
        "patients": [serialize_row(row) for row in rows],
    }


@router.get("/horizontal/summary")
async def horizontal_fragmentation_summary(request: Request) -> dict[str, Any]:
    row = await request.app.state.horizontal_fragmentation_pool.fetchrow(
        """
        SELECT
            count(*) AS total,
            count(*) FILTER (WHERE region = 'NORTH') AS north,
            count(*) FILTER (WHERE region = 'SOUTH') AS south
        FROM patients_all
        """
    )
    return {
        "coordinator": "fragmentation-coordinator-horizontal",
        "view": "patients_all",
        "total": row["total"],
        "regions": {"NORTH": row["north"], "SOUTH": row["south"]},
    }


@router.get("/vertical")
async def vertical_fragmentation(
    request: Request,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> dict[str, Any]:
    rows = await request.app.state.vertical_fragmentation_pool.fetch(
        """
        SELECT
            patient_id AS "patientId",
            full_name AS "fullName",
            phone,
            email,
            address,
            emergency_contact AS "emergencyContact",
            insurance_provider AS "insuranceProvider",
            insurance_number AS "insuranceNumber",
            billing_status AS "billingStatus",
            outstanding_balance AS "outstandingBalance",
            payment_method AS "paymentMethod"
        FROM patients_full
        ORDER BY patient_id
        LIMIT $1
        """,
        limit,
    )
    return {
        "coordinator": "fragmentation-coordinator",
        "view": "patients_full",
        "fieldSources": {
            "public": PUBLIC_FIELDS,
            "financial": FINANCIAL_FIELDS,
        },
        "count": len(rows),
        "limit": limit,
        "patients": [serialize_row(row) for row in rows],
    }


@router.get("/vertical/summary")
async def vertical_fragmentation_summary(request: Request) -> dict[str, Any]:
    total = await request.app.state.vertical_fragmentation_pool.fetchval(
        "SELECT count(*) FROM patients_full"
    )
    return {
        "coordinator": "fragmentation-coordinator",
        "view": "patients_full",
        "reconstructedPatients": total,
        "fieldSources": {
            "public": PUBLIC_FIELDS,
            "financial": FINANCIAL_FIELDS,
        },
    }
