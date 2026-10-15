import contextlib
from datetime import datetime, timezone, timedelta
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import alerts
import common
import daily_backup
import release
import watch
import check_signing_files


class Response(io.BytesIO):
    status = code = 200


class Opener:
    def __init__(self, payload):
        self.payload = payload
        self.requests = []

    def open(self, req, timeout):
        self.requests.append(req)
        return Response(json.dumps(self.payload).encode())


class OperationsTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.root.chmod(0o700)

    def private(self, name, text='{}'):
        path = self.root / name
        path.write_text(text)
        path.chmod(0o600)
        return path

    def test_telegram_requires_actual_acknowledgement_and_uses_fixed_text(self):
        # Synthetic transport fixture only: never a request to Telegram.
        settings = {'bot_token': '12345:' + 'x' * 30, 'chat_id': '-1'}
        opener = Opener({'ok': True, 'result': {'message_id': 12}})
        alerts.deliver(settings, 'test', opener)
        self.assertEqual(json.loads(opener.requests[0].data)['text'], alerts.EVENTS['test'])
        for payload in ({'ok': False}, {'ok': True}, {'ok': True, 'result': {'message_id': 'no'}}):
            with self.assertRaises(RuntimeError):
                alerts.deliver(settings, 'test', Opener(payload))
        with self.assertRaises(ValueError):
            alerts.deliver({'bot_token': '', 'chat_id': ''}, 'test', opener)
        self.assertIsNone(alerts.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://other.invalid'))

    def test_monitor_requires_https_and_valid_boolean_consistency(self):
        settings = {'health_url': 'https://api.example.invalid/api/v1/operations/health', 'health_token': 'h' * 40}
        valid = {'healthy': True, 'checks': {'database_available': True}}
        self.assertTrue(watch.probe(settings, Opener(valid))['healthy'])
        with self.assertRaises(ValueError):
            watch.probe(dict(settings, health_url='http://api.example.invalid'), Opener(valid))
        for payload in ({'healthy': True, 'checks': {}}, {'healthy': True, 'checks': {'db': False}}, {'healthy': True, 'checks': {'db': 1}}):
            with self.assertRaises(ValueError):
                watch.probe(settings, Opener(payload))

    def test_monitor_spike_cooldown_and_retry_after_failed_delivery(self):
        settings = {'alerts_config': str(self.private('alert.json')), 'cooldown_seconds': 900}
        report = lambda _: {'healthy': False, 'checks': {'failed_login_limit_not_reached': False}}
        events, state = [], {}
        send = lambda _, event: events.append(event)
        self.assertFalse(watch.monitor(settings, state, fetch=report, send=send, now=1000))
        self.assertEqual(events, ['health_failed', 'failed_login_spike'])
        watch.monitor(settings, state, fetch=report, send=send, now=1001)
        self.assertEqual(len(events), 2)
        watch.monitor(settings, state, fetch=report, send=send, now=1900)
        self.assertEqual(len(events), 4)
        state = {}
        def fail(*_):
            raise RuntimeError('delivery failed')
        with self.assertRaises(RuntimeError):
            watch.monitor(settings, state, fetch=report, send=fail, now=1000)
        self.assertEqual(state, {})

    def test_private_configuration_rejects_public_or_symlinked_files(self):
        path = self.private('private.json')
        self.assertEqual(common.config(path), {})
        path.chmod(0o644)
        with self.assertRaises(ValueError):
            common.config(path)
        path.chmod(0o600)
        link = self.root / 'link.json'
        link.symlink_to(path)
        with self.assertRaises(ValueError):
            common.config(link)

    def backup_settings(self):
        assets = self.root / 'assets'
        assets.mkdir()
        return {'closed_window_approved': True, 'utc_hour': 20, 'commit': 'a' * 40,
                'writer_units': ['top-coffee-scheduler.timer', 'top-coffee-scheduler.service', 'top-coffee-queue.service', 'php8.3-fpm.service'],
                'all_writers_listed': True, 'credentials': str(self.private('client.cnf')),
                'rclone_config': str(self.private('rclone.conf')), 'spool': str(self.root / 'spool'),
                'assets': str(assets), 'recipients': str(self.private('recipients.txt')),
                'database': 'fixture', 'remote': 'offsite:bucket/pos'}

    def test_backup_failure_always_attempts_all_writer_restarts(self):
        settings = self.backup_settings()
        calls = []
        def runner(argv, **_):
            calls.append([str(x) for x in argv])
            if argv[0] == 'systemctl':
                return b'active\n'
            raise RuntimeError('encryption failed')
        with self.assertRaises(RuntimeError):
            daily_backup.backup(settings, runner=runner, now=datetime(2026, 1, 1, 20, tzinfo=timezone.utc))
        self.assertEqual([x[2] for x in calls if x[:2] == ['systemctl', 'start']], list(reversed(settings['writer_units'])))
        self.assertEqual(list(Path(settings['spool']).glob('*.json')), [])

    def test_backup_refuses_unapproved_wrong_hour_or_missing_scheduler_before_services(self):
        settings = self.backup_settings()
        now = datetime(2026, 1, 1, 20, tzinfo=timezone.utc)
        for bad in (dict(settings, closed_window_approved=False), dict(settings, utc_hour=19), dict(settings, writer_units=['php8.3-fpm.service'])):
            with self.assertRaises(ValueError):
                daily_backup.backup(bad, runner=lambda *_: self.fail('No service calls allowed'), now=now)

    def test_failed_upload_retains_local_ciphertext_and_no_success_receipt(self):
        settings = self.backup_settings()
        def runner(argv, **_):
            if argv[0] == 'systemctl':
                return b'active\n'
            Path(argv[-1]).write_bytes(b'ciphertext fixture')
        def upload(*_):
            raise RuntimeError('offsite unavailable')
        with self.assertRaises(RuntimeError):
            daily_backup.backup(settings, runner=runner, upload=upload, now=datetime(2026, 1, 1, 20, tzinfo=timezone.utc))
        self.assertEqual(len(list(Path(settings['spool']).glob('*.age'))), 1)
        self.assertEqual(len(list(Path(settings['spool']).glob('*.json'))), 0)

    def test_successful_backup_publishes_verified_receipt_after_restart(self):
        settings = self.backup_settings()
        started = []
        def runner(argv, **_):
            if argv[0] == 'systemctl':
                if argv[1] == 'start': started.append(argv[-1])
                return b'active\n'
            Path(argv[-1]).write_bytes(b'ciphertext fixture')
        def upload(settings, output):
            self.assertEqual(len(started), len(settings['writer_units']))
            return 'offsite:bucket/' + output.name
        output = daily_backup.backup(settings, runner=runner, upload=upload, now=datetime(2026, 1, 1, 20, tzinfo=timezone.utc))
        self.assertTrue(common.config(str(output) + '.json')['offsite_verified'])

    @unittest.skipUnless(shutil.which('rclone'), 'rclone required for real local-backend upload/readback')
    def test_offsite_copy_readback_and_immutable_no_overwrite(self):
        remote = self.root / 'remote'
        remote.mkdir()
        config_file = self.private('rclone.conf', '[offsite]\ntype = local\n')
        settings = {'rclone_config': str(config_file), 'remote': 'offsite:' + str(remote)}
        source = self.private('snapshot.age', 'ciphertext fixture')
        destination = daily_backup.offsite(settings, source)
        self.assertTrue(destination.endswith(source.name))
        self.assertEqual((remote / source.name).read_bytes(), source.read_bytes())
        source.write_bytes(b'different ciphertext')
        with self.assertRaises(RuntimeError):
            daily_backup.offsite(settings, source)

    def prepared_release(self, sha):
        path = self.root / 'releases' / sha
        backend = path / 'backend-skeleton'
        (backend / 'vendor').mkdir(parents=True)
        (backend / 'artisan').touch()
        (backend / 'vendor/autoload.php').touch()
        (backend / '.env').symlink_to(self.root / 'shared/.env')
        (backend / 'storage').symlink_to(self.root / 'shared/storage')
        return path

    def releases(self):
        (self.root / 'shared/storage').mkdir(parents=True)
        (self.root / 'shared/.env').touch()
        old, new = self.prepared_release('a' * 40), self.prepared_release('b' * 40)
        (self.root / 'current').symlink_to(old)
        proof = self.private('receipt.json', json.dumps({'offsite_verified': True, 'sha256': 'f' * 64,
                             'created_at': datetime.now(timezone.utc).isoformat(), 'commit': old.name}))
        return old, new, proof

    def test_release_missing_pin_gate_fails_before_maintenance_or_activation(self):
        old, new, proof = self.releases()
        calls = []
        def runner(argv, **_):
            calls.append(argv)
            if 'pos:business-settings-check' in argv: raise RuntimeError('PIN missing')
            return b'inactive\n'
        with self.assertRaises(RuntimeError):
            release.activate(self.root, new.name, proof, writes_drained=True, schema_compatible=True, runner=runner)
        self.assertEqual((self.root / 'current').resolve(), old)
        self.assertFalse(any('down' in x for x in calls))

    def test_release_health_failure_rolls_back_code_and_resumes_old(self):
        old, new, proof = self.releases()
        calls = []
        def runner(argv, **_):
            calls.append(argv)
            if 'pos:operations-health' in argv: raise RuntimeError('health failure')
            return b'active\n'
        with self.assertRaises(RuntimeError):
            release.activate(self.root, new.name, proof, writes_drained=True, schema_compatible=True, runner=runner)
        self.assertEqual((self.root / 'current').resolve(), old)
        self.assertTrue(any('up' in x for x in calls))
        self.assertFalse(any('migrate' in x for x in calls))

    def test_release_success_records_previous_and_refuses_missing_ack_or_stale_backup(self):
        old, new, proof = self.releases()
        with self.assertRaises(ValueError):
            release.activate(self.root, new.name, proof, writes_drained=False, schema_compatible=True)
        def runner(argv, **_): return b'inactive\n'
        release.activate(self.root, new.name, proof, writes_drained=True, schema_compatible=True, runner=runner)
        self.assertEqual((self.root / 'current').resolve(), new)
        self.assertEqual((self.root / 'previous').resolve(), old)
        with self.assertRaises(ValueError):
            release.release_path(self.root, '../../arbitrary')

    def test_retention_keeps_two_newest_and_every_unverified_file(self):
        import os
        now = datetime.now(timezone.utc)
        for i in range(4):
            source = self.private('top-coffee-' + str(i) + '.age', 'ciphertext fixture')
            os.utime(source, (0, 0))
            self.private(source.name + '.json', json.dumps({'offsite_verified': True}))
        unverified = self.private('top-coffee-unverified.age', 'keep')
        daily_backup.prune(self.root, 7, now)
        self.assertTrue(unverified.exists())
        self.assertTrue((self.root / 'top-coffee-3.age').exists())
        self.assertTrue((self.root / 'top-coffee-2.age').exists())
        self.assertFalse((self.root / 'top-coffee-0.age').exists())

    def test_signing_guard_checks_content_even_when_filename_is_renamed(self):
        subprocess.run(['git', 'init', '-q', self.root], check=True)
        self.private('innocent.bin').write_bytes(b'\xfe\xed\xfe\xed' + b'fixture')
        subprocess.run(['git', 'add', '.'], cwd=self.root, check=True)
        self.assertEqual(check_signing_files.violations(self.root), ['innocent.bin'])


if __name__ == '__main__':
    unittest.main()
