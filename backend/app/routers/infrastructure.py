import asyncio
import logging
from typing import Annotated, Any

import asyncpg
from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse
from pymongo.database import Database

from app.config import get_settings
from app.mongodb import get_database


router = APIRouter(prefix="/api/infrastructure", tags=["infrastructure"])
MongoDatabase = Annotated[Database, Depends(get_database)]
logger = logging.getLogger("app")


async def database_probe(
    pool: asyncpg.Pool,
    expected_recovery: bool,
) -> dict[str, bool | str | None]:
    try:
        in_recovery = await pool.fetchval("SELECT pg_is_in_recovery()")
    except Exception:
        logger.warning("database probe failed")
        return {"status": "unhealthy", "inRecovery": None}
    return {
        "status": "healthy" if in_recovery == expected_recovery else "unhealthy",
        "inRecovery": in_recovery,
    }


def mongodb_probe(database: Database) -> dict[str, str]:
    try:
        database.command("ping")
    except Exception:
        logger.warning("MongoDB infrastructure probe failed")
        return {
            "status": "unhealthy",
            "provider": get_settings().mongodb_provider,
        }
    return {
        "status": "healthy",
        "provider": get_settings().mongodb_provider,
    }


@router.get("/status")
async def infrastructure_status(
    request: Request,
    database: MongoDatabase,
) -> JSONResponse:
    primary, replica, mongodb = await asyncio.gather(
        database_probe(request.app.state.write_pool, False),
        database_probe(request.app.state.read_pool, True),
        asyncio.to_thread(mongodb_probe, database),
    )
    result: dict[str, Any] = {
        "primary": primary,
        "replica": replica,
        "mongodb": mongodb,
    }
    healthy = all(component["status"] == "healthy" for component in result.values())
    return JSONResponse(result, status_code=200 if healthy else 503)
