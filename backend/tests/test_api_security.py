import asyncio
import unittest
from unittest.mock import Mock

from fastapi import Request
from fastapi.middleware.cors import CORSMiddleware
from pymongo.errors import PyMongoError

from app import main as app_main
from app.config import get_settings


def asgi_scope(
    path: str,
    method: str = "GET",
    origin: str | None = None,
    extra_headers: list[tuple[bytes, bytes]] | None = None,
) -> dict:
    headers: list[tuple[bytes, bytes]] = []
    if origin is not None:
        headers.append((b"origin", origin.encode("ascii")))
    headers.extend(extra_headers or [])
    return {
        "type": "http",
        "asgi": {"version": "3.0", "spec_version": "2.3"},
        "http_version": "1.1",
        "server": ("testserver", 80),
        "client": ("testclient", 50000),
        "scheme": "http",
        "method": method,
        "root_path": "",
        "path": path,
        "raw_path": path.encode("ascii"),
        "query_string": b"",
        "headers": headers,
        "state": {},
    }


async def asgi_request(
    path: str,
    method: str = "GET",
    origin: str | None = None,
    extra_headers: list[tuple[bytes, bytes]] | None = None,
) -> tuple[int, dict[bytes, bytes], bytes]:
    sent: list[dict] = []

    async def receive() -> dict:
        return {"type": "http.request", "body": b"", "more_body": False}

    async def send(message: dict) -> None:
        sent.append(message)

    await app_main.app(
        asgi_scope(path, method, origin, extra_headers),
        receive,
        send,
    )
    start = next(m for m in sent if m["type"] == "http.response.start")
    body = b"".join(
        m.get("body", b"") for m in sent if m["type"] == "http.response.body"
    )
    return start["status"], dict(start["headers"]), body


class CorsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.origins = get_settings().frontend_origins
        self.allowed = self.origins[0] if self.origins else "http://localhost:5173"

    def test_middleware_uses_settings_origins(self) -> None:
        middleware = next(
            (m for m in app_main.app.user_middleware if m.cls is CORSMiddleware),
            None,
        )
        self.assertIsNotNone(middleware)
        self.assertEqual(middleware.kwargs["allow_origins"], self.origins)

    def test_wildcard_is_not_a_default_origin(self) -> None:
        self.assertNotIn("*", self.origins)

    def test_allowed_origin_receives_cors_header(self) -> None:
        status, headers, _ = asyncio.run(asgi_request("/health", origin=self.allowed))
        self.assertEqual(status, 200)
        self.assertEqual(
            headers[b"access-control-allow-origin"], self.allowed.encode("ascii")
        )

    def test_disallowed_origin_gets_no_cors_header(self) -> None:
        status, headers, _ = asyncio.run(
            asgi_request("/health", origin="http://evil.example")
        )
        self.assertEqual(status, 200)
        self.assertNotIn(b"access-control-allow-origin", headers)

    def test_preflight_from_allowed_origin(self) -> None:
        status, headers, _ = asyncio.run(
            asgi_request(
                "/health",
                method="OPTIONS",
                origin=self.allowed,
                extra_headers=[(b"access-control-request-method", b"GET")],
            )
        )
        self.assertEqual(status, 200)
        self.assertEqual(
            headers[b"access-control-allow-origin"], self.allowed.encode("ascii")
        )
        self.assertIn(b"GET", headers[b"access-control-allow-methods"])


class ErrorSanitizationTests(unittest.TestCase):
    def request(self) -> Request:
        return Request(asgi_scope("/api/patients"))

    def test_unhandled_error_is_sanitized(self) -> None:
        response = asyncio.run(
            app_main.unhandled_exception_handler(
                self.request(),
                RuntimeError(
                    "boom postgresql://user:secret@primary:5432/db "
                    "mongodb+srv://user:secret@atlas.invalid/db"
                ),
            )
        )
        self.assertEqual(response.status_code, 500)
        body = response.body.decode()
        self.assertIn("Internal server error", body)
        for leaked in ("postgresql", "mongodb", "secret", "atlas", "Traceback"):
            self.assertNotIn(leaked, body)

    def test_mongodb_error_does_not_leak_uri(self) -> None:
        uri = "mongodb+srv://user:secret@atlas.invalid/db"
        response = asyncio.run(
            app_main.mongodb_error_handler(self.request(), PyMongoError(uri))
        )
        self.assertEqual(response.status_code, 503)
        self.assertNotIn(uri, response.body.decode())
        self.assertNotIn("secret", response.body.decode())

    def test_postgres_error_is_generic(self) -> None:
        response = asyncio.run(
            app_main.postgres_error_handler(
                self.request(),
                Mock(),
            )
        )
        self.assertEqual(response.status_code, 503)
        self.assertEqual(
            response.body.decode(),
            '{"detail":"PostgreSQL operation failed"}',
        )
