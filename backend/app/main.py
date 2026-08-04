import asyncio
import logging
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

import asyncpg
from fastapi import FastAPI
from fastapi import Request
from fastapi.responses import JSONResponse

from app.mongodb import close_mongodb, connect_mongodb
from app.routers.telemetry import router as telemetry_router

logger = logging.getLogger("app.health")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.write_pool = await asyncpg.create_pool(
        os.environ["POSTGRES_WRITE_URL"],
        min_size=1,
        max_size=5,
    )
    try:
        app.state.read_pool = await asyncpg.create_pool(
            os.environ["POSTGRES_READ_URL"],
            min_size=1,
            max_size=5,
        )
    except Exception:
        await app.state.write_pool.close()
        raise
    connect_mongodb()
    try:
        yield
    finally:
        close_mongodb()
        await app.state.read_pool.close()
        await app.state.write_pool.close()


app = FastAPI(
    title=os.getenv("APP_NAME", "GlobalHealth Unified System"),
    lifespan=lifespan,
)
app.include_router(telemetry_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "healthy"}


async def database_probe(
    pool: asyncpg.Pool,
    expected_recovery: bool,
) -> dict[str, bool | str | None]:
    try:
        in_recovery = await pool.fetchval("SELECT pg_is_in_recovery()")
    except Exception as exc:
        logger.warning("database probe failed: %s", exc)
        return {
            "status": "unhealthy",
            "in_recovery": None,
            "error": "database connection unavailable",
        }
    return {
        "status": "healthy" if in_recovery == expected_recovery else "unhealthy",
        "in_recovery": in_recovery,
    }


@app.get("/health/databases")
async def health_databases(request: Request) -> JSONResponse:
    primary, replica = await asyncio.gather(
        database_probe(request.app.state.write_pool, False),
        database_probe(request.app.state.read_pool, True),
    )
    healthy = primary["status"] == "healthy" and replica["status"] == "healthy"
    return JSONResponse(
        {
            "status": "healthy" if healthy else "unhealthy",
            "primary": primary,
            "replica": replica,
        },
        status_code=200 if healthy else 503,
    )


@app.get("/dashboard")
async def dashboard(request: Request) -> dict[str, object]:
    row = await request.app.state.read_pool.fetchrow(
        """
        SELECT
            pg_is_in_recovery() AS in_recovery,
            current_database() AS database_name,
            current_timestamp AS observed_at,
            pg_database_size(current_database()) AS database_size_bytes,
            (
                SELECT count(*)
                FROM pg_stat_activity
                WHERE datname = current_database()
            ) AS active_connections
        """
    )
    return {
        "source": "replica",
        "in_recovery": row["in_recovery"],
        "database_name": row["database_name"],
        "observed_at": row["observed_at"],
        "database_size_bytes": row["database_size_bytes"],
        "active_connections": row["active_connections"],
    }


@app.post("/chaos/replication/write", status_code=201)
async def chaos_replication_write(
    request: Request,
    probe_id: str,
) -> JSONResponse:
    try:
        await asyncio.wait_for(
            request.app.state.write_pool.execute(
                """
                INSERT INTO chaos_replication_probe (probe_id)
                VALUES ($1)
                """,
                probe_id,
            ),
            timeout=5,
        )
    except Exception:
        return JSONResponse(
            {
                "status": "unavailable",
                "detail": "PostgreSQL Primary is unavailable",
            },
            status_code=503,
        )
    return JSONResponse(
        {"status": "created", "probe_id": probe_id},
        status_code=201,
    )
