import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

from encrypted_backup import extract_bundle, opened_bundle, seal
from mysql_backup import sha, validate_bundle
from runtime_grants import statements


class BundleValidationTest(unittest.TestCase):
    def test_manifest_cannot_skip_one_payload_checksum(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            fixture(root)
            manifest = json.loads((root / 'manifest.json').read_text())
            del manifest['sha256']['assets.tar.gz']
            (root / 'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'both payloads'):
                validate_bundle(root)

    def test_unexpected_archive_members_and_duplicate_names_write_nothing(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            for names in [['../outside'], ['manifest.json', 'manifest.json']]:
                archive = root / 'input.tar'
                with tarfile.open(archive, 'w') as stream:
                    for name in names:
                        member = tarfile.TarInfo(name)
                        member.size = 4
                        stream.addfile(member, io.BytesIO(b'data'))
                with self.assertRaises(ValueError):
                    extract_bundle(archive, root / 'result')
                self.assertFalse((root / 'result').exists())

    def test_grants_keep_audit_append_only_and_migrations_read_only(self):
        sql = statements('cafe', ['orders', 'audit_logs', 'migrations'], 'pos_runtime', 'localhost')
        self.assertIn('GRANT SELECT, INSERT ON `cafe`.`audit_logs`', sql)
        self.assertIn('GRANT SELECT ON `cafe`.`migrations`', sql)
        self.assertNotIn('`cafe`.*', sql)
        self.assertNotIn('WITH GRANT OPTION', sql)
        for user, host, tables in [("x'; DROP USER root;--", 'localhost', ['audit_logs', 'migrations']),
                                   ('pos', '%', ['audit_logs', 'migrations']), ('pos', 'localhost', ['orders'])]:
            with self.assertRaises(ValueError):
                statements('cafe', tables, user, host)


def fixture(root):
    (root / 'database.sql.gz').write_bytes(b'PRIVATE CUSTOMER SQL')
    (root / 'assets.tar.gz').write_bytes(b'PRIVATE CUSTOMER ASSET')
    manifest = {'database': 'source', 'commit': 'synthetic', 'data_hash': 'a' * 64,
                'table_counts': {'orders': 2}, 'asset_hashes': {},
                'sha256': {name: sha(root / name) for name in ['database.sql.gz', 'assets.tar.gz']}}
    (root / 'manifest.json').write_text(json.dumps(manifest))


@unittest.skipUnless(shutil.which('age') and shutil.which('age-keygen'), 'Install age for real encryption acceptance.')
class AgeRecoveryTest(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        self.source = self.root / 'source'
        self.source.mkdir(mode=0o700)
        fixture(self.source)
        self.identity = self.root / 'identity'
        subprocess.run(['age-keygen', '-o', str(self.identity)], check=True, capture_output=True)
        os.chmod(self.identity, 0o600)
        public = subprocess.check_output(['age-keygen', '-y', str(self.identity)], text=True)
        self.recipients = self.root / 'recipients'
        self.recipients.write_text(public)
        self.output = self.root / 'snapshot.age'

    def test_real_ciphertext_round_trip_and_no_overwrite(self):
        receipt = seal(self.source, self.output, self.recipients)
        self.assertTrue(receipt['encrypted'])
        self.assertEqual(receipt['sha256'], sha(self.output))
        self.assertNotIn(b'PRIVATE CUSTOMER', self.output.read_bytes())
        with opened_bundle(self.output, self.identity, self.root) as recovered:
            self.assertEqual((recovered / 'database.sql.gz').read_bytes(), b'PRIVATE CUSTOMER SQL')
        self.assertFalse(list(self.root.glob('.recovery-*')))
        with self.assertRaises(ValueError):
            seal(self.source, self.output, self.recipients)

    def test_corruption_truncation_and_wrong_identity_never_yield_a_bundle(self):
        seal(self.source, self.output, self.recipients)
        data = self.output.read_bytes()
        invalid = self.root / 'invalid.age'
        for changed in [data[:-10], data[:-1] + bytes([data[-1] ^ 1])]:
            invalid.write_bytes(changed)
            with self.assertRaises(ValueError):
                with opened_bundle(invalid, self.identity, self.root):
                    self.fail('Unauthenticated archive was released.')
        wrong = self.root / 'wrong-identity'
        subprocess.run(['age-keygen', '-o', str(wrong)], check=True, capture_output=True)
        os.chmod(wrong, 0o600)
        with self.assertRaises(ValueError):
            with opened_bundle(self.output, wrong, self.root):
                self.fail('Wrong key was accepted.')
        self.assertFalse(list(self.root.glob('.recovery-*')))

    def test_size_limit_and_missing_recipient_publish_no_backup(self):
        seal(self.source, self.output, self.recipients)
        with self.assertRaisesRegex(ValueError, 'size limit'):
            with opened_bundle(self.output, self.identity, self.root, max_bytes=10):
                self.fail('Limit was ignored.')
        self.recipients.write_text('AGE-SECRET-KEY-DO-NOT-UPLOAD')
        target = self.root / 'refused.age'
        with self.assertRaises(ValueError):
            seal(self.source, target, self.recipients)
        self.assertFalse(target.exists())
