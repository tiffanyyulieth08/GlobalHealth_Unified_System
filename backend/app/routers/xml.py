import json
from typing import Any

import asyncpg
from fastapi import APIRouter, HTTPException, Query, Request, Response, status
from pydantic import BaseModel, Field


router = APIRouter(prefix="/api/xml", tags=["XML/XSD"])


class SchemaCreate(BaseModel):
    schema_name: str = Field(min_length=1, max_length=200)
    schema_version: str = Field(min_length=1, max_length=50)
    namespace_uri: str = Field(min_length=1, max_length=500)
    xsd_document: str = Field(min_length=1)


class SchemaUpdate(BaseModel):
    schema_version: str = Field(min_length=1, max_length=50)
    namespace_uri: str = Field(min_length=1, max_length=500)
    xsd_document: str = Field(min_length=1)


class ClinicalRecordCreate(BaseModel):
    schema_name: str = Field(default="clinical-record-v1", min_length=1, max_length=200)
    clinical_document: str = Field(min_length=1)


class ClinicalRecordUpdate(BaseModel):
    schema_name: str = Field(min_length=1, max_length=200)
    clinical_document: str = Field(min_length=1)


class NodeReplace(BaseModel):
    xpath: str = Field(min_length=1)
    value: str
    namespaces: dict[str, str] = Field(default_factory=dict)


class NodeRemove(BaseModel):
    xpath: str = Field(min_length=1)
    namespaces: dict[str, str] = Field(default_factory=dict)


def pool(request: Request) -> asyncpg.Pool:
    return request.app.state.write_pool


def schema_dict(row: asyncpg.Record) -> dict[str, Any]:
    return {
        "schema_name": row["schema_name"],
        "schema_version": row["schema_version"],
        "namespace_uri": row["namespace_uri"],
        "xsd_document": row["xsd_document"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def record_dict(row: asyncpg.Record) -> dict[str, Any]:
    return dict(row)


def raise_xml_http(error: asyncpg.PostgresError) -> None:
    message = str(error)
    if isinstance(error, asyncpg.UniqueViolationError):
        raise HTTPException(status_code=409, detail="schema already exists") from error
    if isinstance(error, asyncpg.ForeignKeyViolationError):
        raise HTTPException(status_code=409, detail="schema is in use") from error
    if (
        "invalid XML" in message
        or "XML or XSD parsing error" in message
        or "XML does not conform" in message
        or "XPath" in message
    ):
        raise HTTPException(status_code=422, detail=message) from error
    raise error


@router.get("/schemas")
async def list_schemas(request: Request) -> list[dict[str, Any]]:
    rows = await pool(request).fetch(
        """
        SELECT schema_name, schema_version, namespace_uri, xsd_document::text,
               created_at, updated_at
        FROM xml_schema_registry
        ORDER BY schema_name
        """
    )
    return [schema_dict(row) for row in rows]


@router.post("/schemas", status_code=status.HTTP_201_CREATED)
async def create_schema(request: Request, payload: SchemaCreate) -> dict[str, Any]:
    connection = await pool(request).acquire()
    try:
        async with connection.transaction():
            await connection.execute(
                "SELECT register_xml_schema($1, $2, $3, $4)",
                payload.schema_name,
                payload.schema_version,
                payload.namespace_uri,
                payload.xsd_document,
            )
            row = await connection.fetchrow(
                """
                SELECT schema_name, schema_version, namespace_uri,
                       xsd_document::text, created_at, updated_at
                FROM get_xml_schema($1)
                """,
                payload.schema_name,
            )
    except asyncpg.PostgresError as error:
        raise_xml_http(error)
    finally:
        await pool(request).release(connection)
    return schema_dict(row)


@router.get("/schemas/{schema_name}")
async def get_schema(request: Request, schema_name: str) -> dict[str, Any]:
    row = await pool(request).fetchrow(
        """
        SELECT schema_name, schema_version, namespace_uri, xsd_document::text,
               created_at, updated_at
        FROM get_xml_schema($1)
        """,
        schema_name,
    )
    if row is None:
        raise HTTPException(status_code=404, detail="schema not found")
    return schema_dict(row)


@router.put("/schemas/{schema_name}")
async def update_schema(
    request: Request, schema_name: str, payload: SchemaUpdate
) -> dict[str, Any]:
    connection = await pool(request).acquire()
    try:
        async with connection.transaction():
            updated = await connection.fetchval(
                "SELECT update_xml_schema($1, $2, $3, $4)",
                schema_name,
                payload.schema_version,
                payload.namespace_uri,
                payload.xsd_document,
            )
            if not updated:
                raise HTTPException(status_code=404, detail="schema not found")
            await connection.execute(
                """
                SELECT validate_xml_against_schema(clinical_document, schema_name)
                FROM clinical_records_xml
                WHERE schema_name = $1
                """,
                schema_name,
            )
            row = await connection.fetchrow(
                """
                SELECT schema_name, schema_version, namespace_uri,
                       xsd_document::text, created_at, updated_at
                FROM get_xml_schema($1)
                """,
                schema_name,
            )
    except asyncpg.PostgresError as error:
        raise_xml_http(error)
    finally:
        await pool(request).release(connection)
    return schema_dict(row)


@router.delete("/schemas/{schema_name}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_schema(request: Request, schema_name: str) -> Response:
    connection = await pool(request).acquire()
    try:
        async with connection.transaction():
            dependent = await connection.fetchval(
                """
                SELECT EXISTS (
                    SELECT 1 FROM clinical_records_xml WHERE schema_name = $1
                )
                """,
                schema_name,
            )
            if dependent:
                raise HTTPException(status_code=409, detail="schema is in use")
            deleted = await connection.fetchval(
                "SELECT delete_xml_schema($1)", schema_name
            )
            if not deleted:
                raise HTTPException(status_code=404, detail="schema not found")
    except asyncpg.PostgresError as error:
        raise_xml_http(error)
    finally:
        await pool(request).release(connection)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


RECORD_COLUMNS = """
record_id, schema_name, clinical_document::text AS clinical_document,
created_at, updated_at
"""


@router.get("/records")
async def list_records(request: Request) -> list[dict[str, Any]]:
    rows = await pool(request).fetch(
        f"SELECT {RECORD_COLUMNS} FROM clinical_records_xml ORDER BY record_id"
    )
    return [record_dict(row) for row in rows]


@router.post("/records", status_code=status.HTTP_201_CREATED)
async def create_record(
    request: Request, payload: ClinicalRecordCreate
) -> dict[str, Any]:
    try:
        row = await pool(request).fetchrow(
            f"""
            INSERT INTO clinical_records_xml (schema_name, clinical_document)
            VALUES ($1, xmlparse(document $2))
            RETURNING {RECORD_COLUMNS}
            """,
            payload.schema_name,
            payload.clinical_document,
        )
    except asyncpg.PostgresError as error:
        raise_xml_http(error)
    return record_dict(row)


@router.get("/records/relational")
async def relational_records(request: Request) -> list[dict[str, Any]]:
    rows = await pool(request).fetch(
        "SELECT * FROM clinical_record_relational ORDER BY record_id"
    )
    return [record_dict(row) for row in rows]


@router.get("/records/high-severity")
async def high_severity_records(request: Request) -> list[dict[str, Any]]:
    rows = await pool(request).fetch(
        """
        SELECT record_id, clinical_document::text AS clinical_document
        FROM clinical_record_high_severity
        ORDER BY record_id
        """
    )
    return [record_dict(row) for row in rows]


@router.get("/records/{record_id}")
async def get_record(request: Request, record_id: int) -> dict[str, Any]:
    row = await pool(request).fetchrow(
        f"SELECT {RECORD_COLUMNS} FROM clinical_records_xml WHERE record_id = $1",
        record_id,
    )
    if row is None:
        raise HTTPException(status_code=404, detail="clinical record not found")
    return record_dict(row)


@router.put("/records/{record_id}")
async def update_record(
    request: Request, record_id: int, payload: ClinicalRecordUpdate
) -> dict[str, Any]:
    try:
        row = await pool(request).fetchrow(
            f"""
            UPDATE clinical_records_xml
            SET schema_name = $2, clinical_document = xmlparse(document $3)
            WHERE record_id = $1
            RETURNING {RECORD_COLUMNS}
            """,
            record_id,
            payload.schema_name,
            payload.clinical_document,
        )
    except asyncpg.PostgresError as error:
        raise_xml_http(error)
    if row is None:
        raise HTTPException(status_code=404, detail="clinical record not found")
    return record_dict(row)


@router.delete("/records/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_record(request: Request, record_id: int) -> Response:
    result = await pool(request).execute(
        "DELETE FROM clinical_records_xml WHERE record_id = $1", record_id
    )
    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="clinical record not found")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.patch("/records/{record_id}/content")
async def replace_record_content(
    request: Request, record_id: int, payload: NodeReplace
) -> dict[str, Any]:
    try:
        row = await pool(request).fetchrow(
            f"""
            UPDATE clinical_records_xml
            SET clinical_document = xml_replace_node_text(
                clinical_document, $2, $3, $4::jsonb
            )
            WHERE record_id = $1
            RETURNING {RECORD_COLUMNS}
            """,
            record_id,
            payload.xpath,
            payload.value,
            json.dumps(payload.namespaces),
        )
    except asyncpg.PostgresError as error:
        raise_xml_http(error)
    if row is None:
        raise HTTPException(status_code=404, detail="clinical record not found")
    return record_dict(row)


@router.delete("/records/{record_id}/content")
async def remove_record_content(
    request: Request, record_id: int, payload: NodeRemove
) -> dict[str, Any]:
    try:
        row = await pool(request).fetchrow(
            f"""
            UPDATE clinical_records_xml
            SET clinical_document = xml_remove_nodes(
                clinical_document, $2, $3::jsonb
            )
            WHERE record_id = $1
            RETURNING {RECORD_COLUMNS}
            """,
            record_id,
            payload.xpath,
            json.dumps(payload.namespaces),
        )
    except asyncpg.PostgresError as error:
        raise_xml_http(error)
    if row is None:
        raise HTTPException(status_code=404, detail="clinical record not found")
    return record_dict(row)


@router.get("/records/{record_id}/nodes")
async def extract_record_nodes(
    request: Request,
    record_id: int,
    xpath_expression: str = Query(alias="xpath", min_length=1),
    namespaces: str = Query(default="{}"),
) -> dict[str, Any]:
    try:
        parsed_namespaces = json.loads(namespaces)
        if not isinstance(parsed_namespaces, dict) or not all(
            isinstance(key, str) and isinstance(value, str)
            for key, value in parsed_namespaces.items()
        ):
            raise ValueError
    except (json.JSONDecodeError, ValueError) as error:
        raise HTTPException(status_code=422, detail="namespaces must be a JSON object") from error
    try:
        row = await pool(request).fetchrow(
            """
            SELECT ARRAY(
                SELECT node::text
                FROM unnest(xpath(
                    $2,
                    clinical_document,
                    COALESCE(
                        (SELECT array_agg(ARRAY[key, value])
                         FROM jsonb_each_text($3::jsonb)),
                        ARRAY[]::text[][]
                    )
                )) AS node
            ) AS nodes
            FROM clinical_records_xml
            WHERE record_id = $1
            """,
            record_id,
            xpath_expression,
            json.dumps(parsed_namespaces),
        )
    except asyncpg.PostgresError as error:
        raise_xml_http(error)
    if row is None:
        raise HTTPException(status_code=404, detail="clinical record not found")
    return {"record_id": record_id, "nodes": row["nodes"]}
