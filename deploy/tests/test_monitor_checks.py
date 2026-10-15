from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import common
import daily_backup
import monitor_checks
import watch


class MonitorChecksTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.root.chmod(0o700)
        self.rc = self.root / 'rclone.conf'
        self.rc.write_text('[offsite]\ntype = local\n')
        self.rc.chmod(0o600)
        self.now = datetime(2026, 1, 2, 20, tzinfo=timezone.utc).timestamp()
        self.name = 'top-coffee-20260102T190000000000Z.age'
        self.settings = {'backup_remote': 'offsite:' + str(self.root / 'remote'),
                         'backup_rclone_config': str(self.rc), 'tls_min_days': 14,
                         'backup_max_age_seconds': 93600}
        self.receipt = {'created_at': '2026-01-02T19:00:00+00:00', 'offsite_verified': True,
                        'sha256': 'a' * 64, 'bytes': 23, 'commit': 'b' * 40,
                        'remote': self.settings['backup_remote'] + '/' + self.name}
        self.listing = [{'Name': self.name + '.json', 'IsDir': False}]
        self.snapshot = {'Name': self.name, 'Size': 23, 'IsDir': False}

    def read(self, args, **kwargs):
        self.assertEqual(kwargs['timeout'], 30)
        if 'cat' in args: result = self.receipt
        elif '--stat' in args: result = self.snapshot
        else: result = self.listing
        return json.dumps(result).encode()

    def test_marker_age_matches_name_receipt_and_existing_ciphertext(self):
        self.assertEqual(monitor_checks.completed_backup_age(self.settings, self.now, self.read), 3600)
        self.assertIn('backup_stale', monitor_checks.infrastructure_events(
            self.settings, self.now + 93601, certificate=lambda *_: 90 * 86400,
            backup=lambda s, n: monitor_checks.completed_backup_age(s, n, self.read)))

    def test_missing_corrupt_and_future_markers_do_not_use_an_older_success(self):
        for listing in ([], [{'Name': 'top-coffee-20260103T190000000000Z.age.json'}],
                        [{'Name': '../' + self.name + '.json'}]):
            self.listing = listing
            with self.assertRaises(ValueError): monitor_checks.completed_backup_age(self.settings, self.now, self.read)
        self.listing = [{'Name': self.name + '.json'}]
        original = dict(self.receipt)
        for key, value in (('offsite_verified', False), ('bytes', True), ('sha256', 'bad'),
                           ('remote', 'other:bucket/' + self.name), ('created_at', '2026-01-02T19:00:00'),
                           ('created_at', '2026-01-02T18:00:00+00:00')):
            self.receipt = dict(original, **{key: value})
            with self.assertRaises((ValueError, TypeError)):
                monitor_checks.completed_backup_age(self.settings, self.now, self.read)
        self.receipt = original
        self.snapshot['Size'] = 22
        with self.assertRaises(ValueError): monitor_checks.completed_backup_age(self.settings, self.now, self.read)

    def test_metadata_limits_and_public_credentials_are_rejected(self):
        with self.assertRaises(ValueError):
            monitor_checks.completed_backup_age(self.settings, self.now, lambda *_, **kw: b' ' * (1024 * 1024 + 1))
        self.rc.chmod(0o644)
        with self.assertRaises(ValueError): monitor_checks.completed_backup_age(self.settings, self.now, self.read)

    def test_real_child_output_and_deadline_are_bounded(self):
        self.assertEqual(monitor_checks.bounded_metadata([sys.executable, '-c', 'print("ok")']), b'ok\n')
        with self.assertRaises(ValueError):
            monitor_checks.bounded_metadata([sys.executable, '-c', 'print("x" * 8192)'], max_bytes=4096)
        with self.assertRaises(RuntimeError):
            monitor_checks.bounded_metadata([sys.executable, '-c', 'import time; time.sleep(10)'], timeout=0.2)

    def test_certificate_and_backup_failures_are_independent_of_api_outage(self):
        def fail(*_): raise RuntimeError('synthetic transport failure')
        events, state = [], {}
        alerts = self.root / 'alerts.json'
        alerts.write_text('{}')
        alerts.chmod(0o600)
        settings = dict(self.settings, alerts_config=str(alerts))
        inspect = lambda s, n: monitor_checks.infrastructure_events(s, n, certificate=lambda *_: 13 * 86400, backup=fail)
        send = lambda _, event: events.append(event)
        self.assertFalse(watch.monitor(settings, state, fetch=fail, send=send, now=self.now, inspect=inspect))
        self.assertEqual(events, ['health_failed', 'tls_expiring', 'backup_stale'])
        watch.monitor(settings, state, fetch=fail, send=send, now=self.now + 1, inspect=inspect)
        self.assertEqual(len(events), 3)
        self.assertEqual(monitor_checks.infrastructure_events(settings, self.now, certificate=fail, backup=lambda *_: 0), ['tls_failed'])
        self.assertEqual(monitor_checks.infrastructure_events(settings, self.now, certificate=lambda *_: 15 * 86400, backup=lambda *_: 0), [])
        for bad in (dict(settings, tls_min_days=0), dict(settings, backup_max_age_seconds=True)):
            with self.assertRaises(ValueError): monitor_checks.infrastructure_events(bad, self.now)

    @unittest.skipUnless(shutil.which('rclone'), 'rclone required for independent local-backend observation')
    def test_real_rclone_completion_observation_and_marker_overwrite_refusal(self):
        remote = self.root / 'remote'
        remote.mkdir()
        source = self.root / self.name
        source.write_bytes(b'ciphertext fixture only')
        settings = dict(self.settings, rclone_config=str(self.rc), remote=self.settings['backup_remote'])
        destination = daily_backup.offsite(settings, source)
        marker = self.root / (self.name + '.json')
        common.atomic_json(marker, dict(self.receipt, bytes=source.stat().st_size,
                           sha256=hashlib.sha256(source.read_bytes()).hexdigest(), remote=destination))
        daily_backup.offsite(settings, marker)
        self.assertEqual(monitor_checks.completed_backup_age(self.settings, self.now), 3600)
        marker.write_text('{}')
        with self.assertRaises(RuntimeError): daily_backup.offsite(settings, marker)
        (remote / source.name).unlink()
        with self.assertRaises(RuntimeError): monitor_checks.completed_backup_age(self.settings, self.now)

    @unittest.skipUnless(shutil.which('openssl'), 'openssl required for loopback trust/expiry check')
    def test_real_tls_uses_system_trust_hostname_and_served_certificate(self):
        # Disposable loopback CA/key only; never a production signing/recovery key.
        cert, key = self.root / 'loopback.pem', self.root / 'loopback.key'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '30',
                        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
                        '-keyout', str(key), '-out', str(cert)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            listener.listen(3)
            listener.settimeout(15)
            errors = []
            def serve():
                for _ in range(3):
                    try:
                        connection, _ = listener.accept()
                        with connection:
                            with context.wrap_socket(connection, server_side=True): pass
                    except ssl.SSLError: pass  # Expected untrusted/hostname failures.
                    except Exception as error: errors.append(error)
            thread = threading.Thread(target=serve, daemon=True)
            thread.start()
            url = 'https://localhost:' + str(listener.getsockname()[1]) + '/health'
            import time
            with self.assertRaises(ssl.SSLCertVerificationError):
                monitor_checks.certificate_remaining({'health_url': url}, time.time())
            with patch.dict(os.environ, {'SSL_CERT_FILE': str(cert)}):
                remaining = monitor_checks.certificate_remaining({'health_url': url}, time.time())
                self.assertGreater(remaining, 29 * 86400)
                self.assertLessEqual(remaining, 30 * 86400)
                with self.assertRaises(ssl.SSLCertVerificationError):
                    monitor_checks.certificate_remaining({'health_url': url.replace('localhost', '127.0.0.1')}, time.time())
            thread.join(20)
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, [])


if __name__ == '__main__':
    unittest.main()
