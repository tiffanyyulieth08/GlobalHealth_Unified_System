import os
from dataclasses import dataclass
from typing import Literal


def parse_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"{name} must be a boolean")


def parse_origins(name: str, default: str) -> list[str]:
    raw = os.getenv(name, default)
    return [origin.strip() for origin in raw.split(",") if origin.strip()]


@dataclass(frozen=True)
class Settings:
    app_name: str
    app_env: Literal["development", "test", "production"]
    app_debug: bool
    frontend_origins: list[str]
    mongodb_provider: Literal["local", "atlas"]
    mongodb_uri: str
    mongodb_db: str


def get_settings() -> Settings:
    app_env = os.getenv("APP_ENV", "development").strip().lower()
    if app_env not in {"development", "test", "production"}:
        raise ValueError("APP_ENV must be development, test, or production")

    provider = os.getenv("MONGODB_PROVIDER", "local").strip().lower()
    if provider not in {"local", "atlas"}:
        raise ValueError("MONGODB_PROVIDER must be local or atlas")

    uri = os.getenv("MONGODB_URI", "mongodb://mongodb:27017/globalhealth").strip()
    if provider == "atlas" and not uri.startswith("mongodb+srv://"):
        raise ValueError("Atlas requires a mongodb+srv URI")
    if provider == "local" and not uri.startswith("mongodb://"):
        raise ValueError("Local MongoDB requires a mongodb URI")

    database = os.getenv("MONGODB_DB", "globalhealth").strip()
    if not database or any(character in database for character in '/\\" .$*<>:|?'):
        raise ValueError("MONGODB_DB is invalid")

    default_origins = "http://localhost:5173,http://localhost:3000"
    frontend_origins = parse_origins("FRONTEND_ORIGINS", default_origins)
    if app_env == "production" and "*" in frontend_origins:
        raise ValueError("FRONTEND_ORIGINS must not contain '*' in production")

    return Settings(
        app_name=os.getenv("APP_NAME", "GlobalHealth Unified System"),
        app_env=app_env,
        app_debug=parse_bool("APP_DEBUG", app_env != "production"),
        frontend_origins=frontend_origins,
        mongodb_provider=provider,
        mongodb_uri=uri,
        mongodb_db=database,
    )
