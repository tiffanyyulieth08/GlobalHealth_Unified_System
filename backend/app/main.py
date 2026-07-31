import os

from fastapi import FastAPI


app = FastAPI(title=os.getenv("APP_NAME", "GlobalHealth Unified System"))


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "healthy"}
