import os
import unittest
from unittest.mock import patch

from app.config import get_settings


class SettingsTests(unittest.TestCase):
    def test_atlas_requires_srv_uri(self) -> None:
        with patch.dict(
            os.environ,
            {
                "MONGODB_PROVIDER": "atlas",
                "MONGODB_URI": "mongodb://localhost:27017/globalhealth",
            },
            clear=False,
        ):
            with self.assertRaisesRegex(ValueError, "mongodb\\+srv"):
                get_settings()

    def test_atlas_settings_do_not_transform_uri(self) -> None:
        uri = "mongodb+srv://placeholder.invalid/globalhealth"
        with patch.dict(
            os.environ,
            {
                "APP_ENV": "production",
                "APP_DEBUG": "false",
                "MONGODB_PROVIDER": "atlas",
                "MONGODB_URI": uri,
                "MONGODB_DB": "globalhealth",
            },
            clear=False,
        ):
            settings = get_settings()
        self.assertEqual(settings.mongodb_provider, "atlas")
        self.assertEqual(settings.mongodb_uri, uri)
        self.assertFalse(settings.app_debug)

    def test_invalid_debug_value_is_rejected(self) -> None:
        with patch.dict(os.environ, {"APP_DEBUG": "sometimes"}, clear=False):
            with self.assertRaisesRegex(ValueError, "APP_DEBUG"):
                get_settings()

    def test_frontend_origins_default_when_unset(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            settings = get_settings()
        self.assertEqual(
            settings.frontend_origins,
            ["http://localhost:3000"],
        )

    def test_frontend_origins_parses_custom_list(self) -> None:
        with patch.dict(
            os.environ,
            {"FRONTEND_ORIGINS": "https://app.example.com, http://localhost:5173 "},
            clear=False,
        ):
            settings = get_settings()
        self.assertEqual(
            settings.frontend_origins,
            ["https://app.example.com", "http://localhost:5173"],
        )

    def test_frontend_origins_rejects_wildcard_in_production(self) -> None:
        with patch.dict(
            os.environ,
            {"APP_ENV": "production", "FRONTEND_ORIGINS": "*"},
            clear=False,
        ):
            with self.assertRaisesRegex(ValueError, "FRONTEND_ORIGINS"):
                get_settings()
