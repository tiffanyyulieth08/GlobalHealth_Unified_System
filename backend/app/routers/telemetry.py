from datetime import datetime
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, Field
from pymongo import DESCENDING
from pymongo.database import Database
from pymongo.errors import DuplicateKeyError, PyMongoError

from app.config import get_settings
from app.mongodb import get_database


router = APIRouter(prefix="/api", tags=["medical-telemetry"])
MongoDatabase = Annotated[Database, Depends(get_database)]


class PatientCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    patient_id: str = Field(alias="patientId", min_length=1, max_length=64)
    first_name: str = Field(alias="firstName", min_length=1, max_length=100)
    last_name: str = Field(alias="lastName", min_length=1, max_length=100)
    date_of_birth: datetime = Field(alias="dateOfBirth")
    sex: Literal["female", "male", "other", "unknown"]
    active: bool = True


class PatientUpdate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    first_name: str | None = Field(
        default=None, alias="firstName", min_length=1, max_length=100
    )
    last_name: str | None = Field(
        default=None, alias="lastName", min_length=1, max_length=100
    )
    date_of_birth: datetime | None = Field(default=None, alias="dateOfBirth")
    sex: Literal["female", "male", "other", "unknown"] | None = None
    active: bool | None = None


class SessionCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    session_id: str = Field(alias="sessionId", min_length=1, max_length=64)
    patient_id: str = Field(alias="patientId", min_length=1, max_length=64)
    device_id: str = Field(alias="deviceId", min_length=1, max_length=128)
    started_at: datetime = Field(alias="startedAt")
    ended_at: datetime | None = Field(default=None, alias="endedAt")
    status: Literal["active", "completed", "cancelled"] = "active"


class SensorLogCreate(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    log_id: str = Field(alias="logId", min_length=1, max_length=64)
    session_id: str = Field(alias="sessionId", min_length=1, max_length=64)
    patient_id: str = Field(alias="patientId", min_length=1, max_length=64)
    sensor_type: Literal[
        "heart_rate", "oxygen_saturation", "temperature", "blood_pressure"
    ] = Field(alias="sensorType")
    value: float = Field(allow_inf_nan=False)
    unit: str = Field(min_length=1, max_length=32)
    recorded_at: datetime = Field(alias="recordedAt")


def without_id(document: dict[str, Any] | None) -> dict[str, Any] | None:
    if document is not None:
        document.pop("_id", None)
    return document


@router.get("/mongodb/health")
def mongodb_health(database: MongoDatabase) -> dict[str, str]:
    try:
        database.command("ping")
    except PyMongoError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="MongoDB is unavailable",
        ) from error
    return {
        "status": "healthy",
        "provider": get_settings().mongodb_provider,
        "database": database.name,
    }


@router.post("/patients", status_code=status.HTTP_201_CREATED)
def create_patient(patient: PatientCreate, database: MongoDatabase) -> dict[str, Any]:
    document = patient.model_dump(by_alias=True)
    document["createdAt"] = datetime.now().astimezone()
    try:
        database.patients.insert_one(document)
    except DuplicateKeyError as error:
        raise HTTPException(status_code=409, detail="patientId already exists") from error
    return without_id(document)


@router.get("/patients")
def list_patients(
    database: MongoDatabase,
    active: bool | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> list[dict[str, Any]]:
    filters = {} if active is None else {"active": active}
    cursor = database.patients.find(filters, {"_id": 0}).sort("lastName", 1).limit(limit)
    return list(cursor)


@router.get("/patients/{patient_id}")
def get_patient(patient_id: str, database: MongoDatabase) -> dict[str, Any]:
    document = database.patients.find_one({"patientId": patient_id}, {"_id": 0})
    if document is None:
        raise HTTPException(status_code=404, detail="patientId does not exist")
    return document


@router.patch("/patients/{patient_id}")
def update_patient(
    patient_id: str,
    patient: PatientUpdate,
    database: MongoDatabase,
) -> dict[str, Any]:
    updates = patient.model_dump(exclude_unset=True, by_alias=True)
    if not updates:
        raise HTTPException(status_code=422, detail="no patient fields to update")
    updates["updatedAt"] = datetime.now().astimezone()
    document = database.patients.find_one_and_update(
        {"patientId": patient_id},
        {"$set": updates},
        return_document=True,
        projection={"_id": 0},
    )
    if document is None:
        raise HTTPException(status_code=404, detail="patientId does not exist")
    return document


@router.post("/sessions", status_code=status.HTTP_201_CREATED)
def create_session(session: SessionCreate, database: MongoDatabase) -> dict[str, Any]:
    if not database.patients.find_one({"patientId": session.patient_id}):
        raise HTTPException(status_code=404, detail="patientId does not exist")
    document = session.model_dump(by_alias=True)
    document["createdAt"] = datetime.now().astimezone()
    try:
        database.sessions.insert_one(document)
    except DuplicateKeyError as error:
        raise HTTPException(status_code=409, detail="sessionId already exists") from error
    return without_id(document)


@router.get("/sessions")
def list_sessions(
    database: MongoDatabase,
    patient_id: Annotated[str | None, Query(alias="patientId")] = None,
    session_status: Annotated[
        Literal["active", "completed", "cancelled"] | None,
        Query(alias="status"),
    ] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> list[dict[str, Any]]:
    filters: dict[str, Any] = {}
    if patient_id:
        filters["patientId"] = patient_id
    if session_status:
        filters["status"] = session_status
    cursor = (
        database.sessions.find(filters, {"_id": 0})
        .sort("startedAt", DESCENDING)
        .limit(limit)
    )
    return list(cursor)


@router.patch("/sessions/{session_id}/complete")
def complete_session(session_id: str, database: MongoDatabase) -> dict[str, Any]:
    document = database.sessions.find_one_and_update(
        {"sessionId": session_id},
        {"$set": {"status": "completed", "endedAt": datetime.now().astimezone()}},
        return_document=True,
        projection={"_id": 0},
    )
    if document is None:
        raise HTTPException(status_code=404, detail="sessionId does not exist")
    return document


@router.post("/sensor-logs", status_code=status.HTTP_201_CREATED)
def create_sensor_log(log: SensorLogCreate, database: MongoDatabase) -> dict[str, Any]:
    session = database.sessions.find_one(
        {"sessionId": log.session_id, "patientId": log.patient_id}
    )
    if session is None:
        raise HTTPException(
            status_code=404,
            detail="sessionId and patientId relationship does not exist",
        )
    document = log.model_dump(by_alias=True)
    try:
        database.sensor_logs.insert_one(document)
    except DuplicateKeyError as error:
        raise HTTPException(status_code=409, detail="logId already exists") from error
    return without_id(document)


@router.get("/sensor-logs")
def list_sensor_logs(
    database: MongoDatabase,
    session_id: Annotated[str | None, Query(alias="sessionId")] = None,
    sensor_type: Annotated[
        Literal[
            "heart_rate",
            "oxygen_saturation",
            "temperature",
            "blood_pressure",
        ]
        | None,
        Query(alias="sensorType"),
    ] = None,
    recorded_from: Annotated[datetime | None, Query(alias="recordedFrom")] = None,
    recorded_to: Annotated[datetime | None, Query(alias="recordedTo")] = None,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> list[dict[str, Any]]:
    if recorded_from and recorded_to and recorded_from > recorded_to:
        raise HTTPException(
            status_code=422,
            detail="recordedFrom must be before or equal to recordedTo",
        )
    filters: dict[str, Any] = {}
    if session_id:
        filters["sessionId"] = session_id
    if sensor_type:
        filters["sensorType"] = sensor_type
    if recorded_from or recorded_to:
        recorded_at: dict[str, datetime] = {}
        if recorded_from:
            recorded_at["$gte"] = recorded_from
        if recorded_to:
            recorded_at["$lte"] = recorded_to
        filters["recordedAt"] = recorded_at
    cursor = (
        database.sensor_logs.find(filters, {"_id": 0})
        .sort("recordedAt", DESCENDING)
        .limit(limit)
    )
    return list(cursor)


@router.get("/telemetry/summary")
def telemetry_summary(
    database: MongoDatabase,
    patient_id: Annotated[str | None, Query(alias="patientId")] = None,
    recorded_from: Annotated[datetime | None, Query(alias="recordedFrom")] = None,
    recorded_to: Annotated[datetime | None, Query(alias="recordedTo")] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> dict[str, Any]:
    if recorded_from and recorded_to and recorded_from > recorded_to:
        raise HTTPException(
            status_code=422,
            detail="recordedFrom must be before or equal to recordedTo",
        )
    match: dict[str, Any] = {}
    if patient_id:
        match["patientId"] = patient_id
    if recorded_from or recorded_to:
        match["recordedAt"] = {}
        if recorded_from:
            match["recordedAt"]["$gte"] = recorded_from
        if recorded_to:
            match["recordedAt"]["$lte"] = recorded_to

    pipeline: list[dict[str, Any]] = []
    if match:
        pipeline.append({"$match": match})
    pipeline.extend(
        [
            {
                "$group": {
                    "_id": {
                        "patientId": "$patientId",
                        "sensorType": "$sensorType",
                        "unit": "$unit",
                    },
                    "sampleCount": {"$sum": 1},
                    "minimum": {"$min": "$value"},
                    "maximum": {"$max": "$value"},
                    "average": {"$avg": "$value"},
                    "firstRecordedAt": {"$min": "$recordedAt"},
                    "lastRecordedAt": {"$max": "$recordedAt"},
                    "sessionIds": {"$addToSet": "$sessionId"},
                }
            },
            {
                "$lookup": {
                    "from": "patients",
                    "localField": "_id.patientId",
                    "foreignField": "patientId",
                    "as": "patient",
                }
            },
            {"$unwind": {"path": "$patient", "preserveNullAndEmptyArrays": True}},
            {
                "$project": {
                    "_id": 0,
                    "patientId": "$_id.patientId",
                    "patientName": {
                        "$cond": [
                            {"$ne": [{"$type": "$patient"}, "missing"]},
                            {
                                "$concat": [
                                    "$patient.firstName",
                                    " ",
                                    "$patient.lastName",
                                ]
                            },
                            None,
                        ]
                    },
                    "sensorType": "$_id.sensorType",
                    "unit": "$_id.unit",
                    "sampleCount": 1,
                    "minimum": 1,
                    "maximum": 1,
                    "average": {"$round": ["$average", 2]},
                    "firstRecordedAt": 1,
                    "lastRecordedAt": 1,
                    "sessionIds": 1,
                }
            },
            {"$sort": {"patientId": 1, "sensorType": 1}},
            {"$limit": limit},
        ]
    )
    results = list(database.sensor_logs.aggregate(pipeline))
    return {
        "aggregation": "sensor_logs grouped by patient and sensor with patient lookup",
        "count": len(results),
        "limit": limit,
        "results": results,
    }


@router.get("/patients/{patient_id}/telemetry")
def patient_telemetry(
    patient_id: str,
    database: MongoDatabase,
    session_limit: Annotated[int, Query(alias="sessionLimit", ge=1, le=100)] = 20,
    logs_per_session: Annotated[
        int,
        Query(alias="logsPerSession", ge=1, le=500),
    ] = 100,
) -> dict[str, Any]:
    pipeline = [
        {"$match": {"patientId": patient_id}},
        {
            "$lookup": {
                "from": "sessions",
                "let": {"patientId": "$patientId"},
                "pipeline": [
                    {"$match": {"$expr": {"$eq": ["$patientId", "$$patientId"]}}},
                    {"$sort": {"startedAt": -1}},
                    {"$limit": session_limit},
                    {
                        "$lookup": {
                            "from": "sensor_logs",
                            "let": {"sessionId": "$sessionId"},
                            "pipeline": [
                                {
                                    "$match": {
                                        "$expr": {
                                            "$eq": ["$sessionId", "$$sessionId"]
                                        }
                                    }
                                },
                                {"$sort": {"recordedAt": -1}},
                                {"$limit": logs_per_session},
                                {"$project": {"_id": 0}},
                            ],
                            "as": "logs",
                        }
                    },
                    {"$project": {"_id": 0}},
                ],
                "as": "sessions",
            }
        },
        {"$project": {"_id": 0}},
    ]
    result = list(database.patients.aggregate(pipeline))
    if not result:
        raise HTTPException(status_code=404, detail="patientId does not exist")
    return result[0]
