import unittest
from types import SimpleNamespace
from unittest.mock import patch
from fastapi.testclient import TestClient
import app as recovery


class RecoveryLookupTests(unittest.TestCase):
    def setUp(self):
        recovery.limiter = recovery.LookupLimiter()
        self.client = TestClient(recovery.app)

    def lookup(self, email):
        return self.client.post('/auth/email-registered', json={'email': email})

    def mock_admin(self, pages):
        admin = SimpleNamespace(auth=SimpleNamespace(admin=SimpleNamespace(
            list_users=lambda **kwargs: pages[kwargs['page'] - 1])))
        return patch.object(recovery, 'admin_client', return_value=admin)

    def test_unknown_returns_false_without_user_details(self):
        with self.mock_admin([[]]):
            result = self.lookup('unknown@example.com')
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json(), {'registered': False})

    def test_registered_case_and_whitespace(self):
        with self.mock_admin([[SimpleNamespace(email='Known@example.com')]]):
            result = self.lookup(' KNOWN@example.com ')
        self.assertEqual(result.json(), {'registered': True})

    def test_pagination(self):
        with self.mock_admin([
            [SimpleNamespace(email='other@example.com')] * 200,
            [SimpleNamespace(email='known@example.com')],
        ]):
            result = self.lookup('known@example.com')
        self.assertEqual(result.json(), {'registered': True})

    def test_unavailable_is_not_unknown(self):
        with patch.object(recovery, 'admin_client', side_effect=RuntimeError('secret')):
            result = self.lookup('known@example.com')
        self.assertEqual(result.status_code, 503)
        self.assertNotIn('secret', result.text)

    def test_invalid_email(self):
        for email in ['bad', 'name+tag@example.com', 'a@' + 'x' * 64 + '.com']:
            self.assertEqual(self.lookup(email).status_code, 400)

    def test_rate_limit(self):
        with self.mock_admin([[]]):
            for _ in range(5):
                self.assertEqual(self.lookup('unknown@example.com').status_code, 200)
            self.assertEqual(self.lookup('unknown@example.com').status_code, 429)


if __name__ == '__main__':
    unittest.main()
