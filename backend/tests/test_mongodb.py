import unittest
from unittest.mock import MagicMock, patch

from app import mongodb


class MongoConnectionTests(unittest.TestCase):
    def tearDown(self) -> None:
        mongodb.close_mongodb()

    @patch("app.mongodb.time.sleep")
    @patch("app.mongodb.MongoClient")
    def test_connection_retries_after_transient_ping_failure(
        self,
        mongo_client: MagicMock,
        sleep: MagicMock,
    ) -> None:
        first = MagicMock()
        second = MagicMock()
        first.admin.command.side_effect = TimeoutError("temporary")
        mongo_client.side_effect = [first, second]

        result = mongodb.connect_mongodb()

        self.assertIs(result, second)
        first.close.assert_called_once_with()
        second.admin.command.assert_called_once_with("ping")
        sleep.assert_called_once_with(2)

    @patch("app.mongodb.time.sleep")
    @patch("app.mongodb.MongoClient")
    def test_connection_raises_after_three_failures(
        self,
        mongo_client: MagicMock,
        sleep: MagicMock,
    ) -> None:
        clients = [MagicMock(), MagicMock(), MagicMock()]
        for client in clients:
            client.admin.command.side_effect = TimeoutError("temporary")
        mongo_client.side_effect = clients

        with self.assertRaises(TimeoutError):
            mongodb.connect_mongodb()

        self.assertEqual(sleep.call_count, 2)
        for client in clients:
            client.close.assert_called_once_with()
