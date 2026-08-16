import json
import math
import os
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from pymongo import ASCENDING, MongoClient


LATENCY_SAMPLES = int(os.getenv("MONGODB_BENCHMARK_LATENCY_SAMPLES", "100"))
THROUGHPUT_OPERATIONS = int(os.getenv("MONGODB_BENCHMARK_THROUGHPUT_OPERATIONS", "200"))
CONCURRENCY = int(os.getenv("MONGODB_BENCHMARK_CONCURRENCY", "8"))
SEED_DOCUMENTS = int(os.getenv("MONGODB_BENCHMARK_SEED_DOCUMENTS", "500"))
PAYLOAD = "x" * 512


def percentile(values: list[float], percentage: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * percentage
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def summarize(values: list[float], errors: int) -> dict:
    if not values:
        return {"successful_operations": 0, "errors": errors}
    return {
        "successful_operations": len(values),
        "errors": errors,
        "mean_ms": round(sum(values) / len(values), 3),
        "p50_ms": round(percentile(values, 0.50), 3),
        "p95_ms": round(percentile(values, 0.95), 3),
        "p99_ms": round(percentile(values, 0.99), 3),
        "min_ms": round(min(values), 3),
        "max_ms": round(max(values), 3),
    }


def timed(operation) -> tuple[float | None, bool]:
    started = time.perf_counter_ns()
    try:
        operation()
        return (time.perf_counter_ns() - started) / 1_000_000, True
    except Exception:
        return None, False


def run_latency(collection) -> dict:
    operations = {
        "insert": lambda index: collection.insert_one(
            {
                "logId": f"LATENCY-{index}-{uuid.uuid4().hex}",
                "patientId": f"PATIENT-{index % 50:04d}",
                "sensorType": "heart_rate",
                "value": 70 + index % 30,
                "sequence": SEED_DOCUMENTS + index,
                "payload": PAYLOAD,
            }
        ),
        "read": lambda index: collection.find_one(
            {"logId": f"SEED-{index % SEED_DOCUMENTS:06d}"}, {"_id": 0}
        ),
        "aggregation": lambda index: list(
            collection.aggregate(
                [
                    {"$match": {"patientId": f"PATIENT-{index % 50:04d}"}},
                    {
                        "$group": {
                            "_id": "$sensorType",
                            "samples": {"$sum": 1},
                            "average": {"$avg": "$value"},
                        }
                    },
                ]
            )
        ),
    }
    results = {}
    for name, operation in operations.items():
        values = []
        errors = 0
        for index in range(LATENCY_SAMPLES):
            duration, successful = timed(lambda i=index: operation(i))
            if successful:
                values.append(duration)
            else:
                errors += 1
        results[name] = summarize(values, errors)
    return results


def run_throughput(collection) -> dict:
    operations = {
        "insert": lambda index: collection.insert_one(
            {
                "logId": f"THROUGHPUT-{index}-{uuid.uuid4().hex}",
                "patientId": f"PATIENT-{index % 50:04d}",
                "sensorType": "heart_rate",
                "value": 70 + index % 30,
                "sequence": SEED_DOCUMENTS + LATENCY_SAMPLES + index,
                "payload": PAYLOAD,
            }
        ),
        "read": lambda index: collection.find_one(
            {"logId": f"SEED-{index % SEED_DOCUMENTS:06d}"}, {"_id": 0}
        ),
        "aggregation": lambda index: list(
            collection.aggregate(
                [
                    {"$match": {"patientId": f"PATIENT-{index % 50:04d}"}},
                    {
                        "$group": {
                            "_id": "$sensorType",
                            "samples": {"$sum": 1},
                            "average": {"$avg": "$value"},
                        }
                    },
                ]
            )
        ),
    }
    results = {}
    for name, operation in operations.items():
        started = time.perf_counter()
        with ThreadPoolExecutor(max_workers=CONCURRENCY) as executor:
            outcomes = list(
                executor.map(
                    lambda index: timed(lambda i=index: operation(i))[1],
                    range(THROUGHPUT_OPERATIONS),
                )
            )
        elapsed = time.perf_counter() - started
        successes = sum(outcomes)
        errors = len(outcomes) - successes
        results[name] = {
            "attempted_operations": len(outcomes),
            "successful_operations": successes,
            "errors": errors,
            "error_rate_percent": round(errors * 100 / len(outcomes), 3),
            "elapsed_seconds": round(elapsed, 3),
            "operations_per_second": round(successes / elapsed, 3),
        }
    return results


def database_stats(database) -> dict:
    stats = database.command({"dbStats": 1, "scale": 1})
    return {
        "collections": stats.get("collections"),
        "objects": stats.get("objects"),
        "data_size_bytes": stats.get("dataSize"),
        "storage_size_bytes": stats.get("storageSize"),
        "index_size_bytes": stats.get("indexSize"),
    }


def benchmark(client, database_name: str) -> dict:
    database = client[database_name]
    collection = database["sensor_logs"]
    collection.create_index([("logId", ASCENDING)], unique=True)
    collection.create_index([("patientId", ASCENDING), ("sensorType", ASCENDING)])
    collection.insert_many(
        [
            {
                "logId": f"SEED-{index:06d}",
                "patientId": f"PATIENT-{index % 50:04d}",
                "sensorType": "heart_rate" if index % 2 == 0 else "oxygen_saturation",
                "value": 70 + index % 30,
                "sequence": index,
                "payload": PAYLOAD,
            }
            for index in range(SEED_DOCUMENTS)
        ]
    )
    for index in range(20):
        collection.find_one({"logId": f"SEED-{index:06d}"})
    return {
        "latency": run_latency(collection),
        "throughput": run_throughput(collection),
        "temporary_database_stats": database_stats(database),
    }


def main() -> None:
    atlas_uri = os.getenv("MONGODB_URI", "")
    if not atlas_uri.startswith("mongodb+srv://"):
        raise SystemExit("MONGODB_URI de Atlas no está disponible")
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    local_database = f"gh_benchmark_{run_id}_local"
    atlas_database = f"gh_benchmark_{run_id}_atlas"
    local_client = MongoClient(
        "mongodb://mongodb:27017",
        serverSelectionTimeoutMS=10000,
        connectTimeoutMS=10000,
        socketTimeoutMS=30000,
    )
    atlas_client = MongoClient(
        atlas_uri,
        tls=True,
        serverSelectionTimeoutMS=15000,
        connectTimeoutMS=15000,
        socketTimeoutMS=30000,
    )
    report = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "method": {
            "client": "same PyMongo process in the backend Docker container",
            "latency_samples_per_operation": LATENCY_SAMPLES,
            "throughput_attempts_per_operation": THROUGHPUT_OPERATIONS,
            "concurrency": CONCURRENCY,
            "seed_documents": SEED_DOCUMENTS,
            "payload_bytes": len(PAYLOAD),
            "operations": ["insert", "indexed read", "aggregation"],
        },
    }
    try:
        local_client.admin.command("ping")
        atlas_client.admin.command("ping")
        report["local"] = benchmark(local_client, local_database)
        report["atlas"] = benchmark(atlas_client, atlas_database)
        print(json.dumps(report, indent=2, sort_keys=True))
    finally:
        if local_database.startswith("gh_benchmark_"):
            local_client.drop_database(local_database)
        if atlas_database.startswith("gh_benchmark_"):
            atlas_client.drop_database(atlas_database)
        local_client.close()
        atlas_client.close()


if __name__ == "__main__":
    main()
