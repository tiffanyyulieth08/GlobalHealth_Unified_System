import os

from pymongo import MongoClient
from pymongo.database import Database


_client: MongoClient | None = None


def connect_mongodb() -> MongoClient:
    global _client
    if _client is None:
        uri = os.getenv("MONGODB_URI", "mongodb://mongodb:27017/globalhealth")
        _client = MongoClient(uri, serverSelectionTimeoutMS=5000)
    return _client


def close_mongodb() -> None:
    global _client
    if _client is not None:
        _client.close()
        _client = None


def get_database() -> Database:
    database_name = os.getenv("MONGODB_DB", "globalhealth")
    return connect_mongodb()[database_name]
