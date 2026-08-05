from pymongo import MongoClient
from pymongo.database import Database

from app.config import get_settings


_client: MongoClient | None = None


def connect_mongodb() -> MongoClient:
    global _client
    if _client is None:
        settings = get_settings()
        options = {
            "serverSelectionTimeoutMS": 5000,
            "connectTimeoutMS": 5000,
            "socketTimeoutMS": 10000,
            "appname": settings.app_name,
        }
        if settings.mongodb_provider == "atlas":
            options["tls"] = True
        candidate = MongoClient(settings.mongodb_uri, **options)
        try:
            candidate.admin.command("ping")
        except Exception:
            candidate.close()
            raise
        _client = candidate
    return _client


def close_mongodb() -> None:
    global _client
    if _client is not None:
        _client.close()
        _client = None


def get_database() -> Database:
    return connect_mongodb()[get_settings().mongodb_db]
