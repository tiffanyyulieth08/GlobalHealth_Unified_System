import os
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.mongodb import close_mongodb, connect_mongodb
from app.routers.telemetry import router as telemetry_router


@asynccontextmanager
async def lifespan(_: FastAPI):
    connect_mongodb()
    yield
    close_mongodb()


app = FastAPI(
    title=os.getenv("APP_NAME", "GlobalHealth Unified System"),
    lifespan=lifespan,
)
app.include_router(telemetry_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "healthy"}
