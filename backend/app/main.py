import asyncio
import logging
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator

import asyncpg
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pymongo.errors import PyMongoError

from app.config import get_settings
from app.mongodb import close_mongodb, connect_mongodb
from app.routers.telemetry import router as telemetry_router

logger = logging.getLogger("app")
settings = get_settings()


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
    try:
        connect_mongodb()
        yield
    finally:
        close_mongodb()
        await app.state.read_pool.close()
        await app.state.write_pool.close()


app = FastAPI(
    title=settings.app_name,
    debug=settings.app_debug,
    lifespan=lifespan,
)
app.include_router(telemetry_router)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.frontend_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(PyMongoError)
async def mongodb_error_handler(
    request: Request,
    exception: PyMongoError,
) -> JSONResponse:
    logger.warning("MongoDB operation failed")
    return JSONResponse(
        {"detail": "MongoDB operation failed"},
        status_code=503,
    )


@app.exception_handler(asyncpg.PostgresError)
async def postgres_error_handler(
    request: Request,
    exception: asyncpg.PostgresError,
) -> JSONResponse:
    logger.warning("PostgreSQL operation failed")
    return JSONResponse(
        {"detail": "PostgreSQL operation failed"},
        status_code=503,
    )


@app.exception_handler(Exception)
async def unhandled_exception_handler(
    request: Request,
    exception: Exception,
) -> JSONResponse:
    logger.exception("Unhandled error while processing %s", request.url.path)
    return JSONResponse(
        {"detail": "Internal server error"},
        status_code=500,
    )


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "healthy"}


async def database_probe(
    pool: asyncpg.Pool,
    expected_recovery: bool,
) -> dict[str, bool | str | None]:
    try:
        in_recovery = await pool.fetchval("SELECT pg_is_in_recovery()")
    except Exception:
        logger.warning("database probe failed")
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
