#!/usr/bin/env python3
"""Private MySQL backup and restore rehearsal. Uses native clients; no pip deps."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tarfile
from datetime import datetime, timezone


def database(value):
    if not re.fullmatch(r'[A-Za-z0-9_]+', value):
        raise argparse.ArgumentTypeError('Database names must use letters, numbers and underscores.')
    return value


def client(args, sql, db=None):
    return subprocess.check_output([args.mysql, '--defaults-extra-file=' + str(args.credentials.resolve()),
                                   '--batch', '--skip-column-names', *( [db] if db else []), '-e', sql], text=True)


def counts(args, db):
    tables = client(args, f"SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='{db}' AND TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME")
    return {table: int(client(args, 'SELECT COUNT(*) FROM `' + table.replace('`', '``') + '`', db))
            for table in tables.splitlines()}


def data_hash(args, db):
    command = [args.mysqldump, '--defaults-extra-file=' + str(args.credentials.resolve()),
               '--no-create-info', '--skip-comments', '--skip-extended-insert', '--order-by-primary',
               '--hex-blob', '--no-tablespaces', db]
    # Sort complete INSERT rows so tables lacking a primary key are deterministic.
    with tempfile.TemporaryFile() as errors:
        output = subprocess.check_output(command, stderr=errors)
    lines = sorted(line for line in output.splitlines() if line.startswith(b'INSERT INTO '))
    return hashlib.sha256(b'\n'.join(lines)).hexdigest()


def asset_hashes(root):
    result = {}
    for path in sorted(root.rglob('*')):
        if path.is_symlink():
            raise ValueError('Asset symlinks are not supported; use regular upload files.')
        if path.is_file():
            result[str(path.relative_to(root))] = sha(path)
    return result


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def backup(args, report=True):
    # Writes must be drained: counts/assets and the SQL snapshot share a quiet window.
    if not args.writes_drained:
        raise ValueError('Stop cashier writes, then supply --writes-drained.')
    args.output.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    target = args.output / (args.database + '-' + stamp)
    staging = Path(tempfile.mkdtemp(prefix='.backup-', dir=args.output))
    os.chmod(staging, 0o700)
    try:
        before = counts(args, args.database)
        original_data = data_hash(args, args.database)
        original_assets = asset_hashes(args.assets)
        dump = staging / 'database.sql.gz'
        # Password stays in a private client option file, never command arguments.
        command = [args.mysqldump, '--defaults-extra-file=' + str(args.credentials.resolve()),
                   '--single-transaction', '--quick', '--hex-blob', '--routines', '--triggers', '--events',
                   '--no-tablespaces', args.database]
        with tempfile.TemporaryFile() as stderr, dump.open('wb') as raw:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=stderr)
            with gzip.GzipFile(fileobj=raw, mode='wb') as compressed:
                shutil.copyfileobj(process.stdout, compressed)
            process.stdout.close()
            if process.wait() != 0:
                raise RuntimeError('mysqldump failed; inspect database permissions/configuration. No completed backup created.')
        if counts(args, args.database) != before or data_hash(args, args.database) != original_data:
            raise RuntimeError('Source row counts changed during backup; keep writes stopped and retry.')
        subprocess.run(['tar', '-czf', str(staging / 'assets.tar.gz'), '-C', str(args.assets.resolve()), '.'], check=True)
        if asset_hashes(args.assets) != original_assets:
            raise RuntimeError('Assets changed during backup; keep writes stopped and retry.')
        manifest = {'data_hash': original_data, 'asset_hashes': original_assets, 'database': args.database, 'created_at': stamp, 'commit': args.commit,
                    'mysql_version': client(args, 'SELECT VERSION()').strip(), 'table_counts': before,
                    'sha256': {p.name: sha(p) for p in [dump, staging / 'assets.tar.gz']}}
        (staging / 'manifest.json').write_text(json.dumps(manifest, indent=2))
        staging.rename(target)
        if report:
            print(target)
        return target
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def restore_assets(archive_path, destination):
    """Extract regular files only; never follow archive links or traversal."""
    destination = destination.resolve()
    with tarfile.open(archive_path, "r:gz") as archive:
        members = archive.getmembers()
        for member in members:
            target = (destination / member.name).resolve()
            if not target.is_relative_to(destination) or not (member.isfile() or member.isdir()):
                raise ValueError("Unsafe asset archive member.")
        destination.mkdir(parents=True, mode=0o700)
        for member in members:
            target = destination / member.name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.extractfile(member) as source, target.open("xb") as output:
                    shutil.copyfileobj(source, output)


def validate_bundle(root):
    required = {'manifest.json', 'database.sql.gz', 'assets.tar.gz'}
    if root.is_symlink() or not root.is_dir():
        raise ValueError('Backup must be a regular directory.')
    if any((root / name).is_symlink() or not (root / name).is_file() for name in required):
        raise ValueError('Backup files must be regular files, not links.')
    if (root / 'manifest.json').stat().st_size > 1024 * 1024:
        raise ValueError('Backup manifest exceeds the supported limit.')
    manifest = json.loads((root / 'manifest.json').read_text())
    if not isinstance(manifest, dict):
        raise ValueError('Backup manifest must be an object.')
    hashes = manifest.get('sha256', {})
    if not isinstance(hashes, dict) or set(hashes) != required - {'manifest.json'}:
        raise ValueError('Backup manifest must checksum both payloads.')
    if not isinstance(manifest.get('database'), str) or not re.fullmatch(r'[A-Za-z0-9_]+', manifest['database']):
        raise ValueError('Invalid source database in backup manifest.')
    if not isinstance(manifest.get('table_counts'), dict) or not isinstance(manifest.get('asset_hashes'), dict):
        raise ValueError('Missing backup comparison evidence.')
    if not isinstance(manifest.get('commit'), str) or not manifest['commit']:
        raise ValueError('Missing backup source commit.')
    if not re.fullmatch(r'[a-f0-9]{64}', str(manifest.get('data_hash', ''))):
        raise ValueError('Missing backup data hash.')
    for name, expected in hashes.items():
        if not re.fullmatch(r'[a-f0-9]{64}', str(expected)) or sha(root / name) != expected:
            raise ValueError('Backup checksum mismatch.')
    return manifest


def restore(args):
    manifest = validate_bundle(args.backup)
    # Never overwrites a database. Dedicated empty rehearsal names only.
    if args.database == manifest['database'] or not args.database.endswith('_restore'):
        raise ValueError('Use a different, empty database whose name ends with _restore.')
    exists = client(args, f"SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='{args.database}'").strip()
    if exists != '1' or counts(args, args.database):
        raise ValueError('Create an empty rehearsal database first. Existing tables are never overwritten.')
    if args.assets.exists():
        raise ValueError('Restore assets into a new directory; existing paths are never overwritten.')
    with gzip.open(args.backup / 'database.sql.gz', 'rb') as stream:
        process = subprocess.Popen([args.mysql, '--defaults-extra-file=' + str(args.credentials.resolve()), args.database], stdin=subprocess.PIPE)
        shutil.copyfileobj(stream, process.stdin)
        process.stdin.close()
        if process.wait() != 0:
            raise RuntimeError('Restore failed. Partial rehearsal database retained for inspection.')
    restored = counts(args, args.database)
    if restored != manifest['table_counts'] or data_hash(args, args.database) != manifest['data_hash']:
        raise RuntimeError('Restored table counts differ. Rehearsal is not accepted.')
    restore_assets(args.backup / 'assets.tar.gz', args.assets)
    if asset_hashes(args.assets) != manifest['asset_hashes']:
        raise RuntimeError('Restored assets differ. Rehearsal is not accepted.')
    print(json.dumps({'restored': True, 'database': args.database, 'tables': len(restored),
                      'rows': sum(restored.values()), 'source_commit': manifest['commit']}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials', type=Path, required=True, help='Private MySQL [client] option file, outside Git')
    parser.add_argument('--mysql', default='mysql')
    parser.add_argument('--mysqldump', default='mysqldump')
    commands = parser.add_subparsers(dest='command', required=True)
    save = commands.add_parser('backup')
    save.add_argument('--database', type=database, required=True)
    save.add_argument('--assets', type=Path, required=True)
    save.add_argument('--output', type=Path, required=True)
    save.add_argument('--commit', required=True)
    save.add_argument('--writes-drained', action='store_true')
    replay = commands.add_parser('restore-rehearsal')
    replay.add_argument('--database', type=database, required=True)
    replay.add_argument('--assets', type=Path, required=True)
    replay.add_argument('--backup', type=Path, required=True)
    args = parser.parse_args()
    if not args.credentials.is_file():
        parser.error('Private client option file not found.')
    if os.name != 'nt' and args.credentials.stat().st_mode & 0o077:
        parser.error('Credential file must have permissions 600.')
    try:
        (backup if args.command == 'backup' else restore)(args)
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
