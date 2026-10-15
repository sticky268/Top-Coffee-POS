#!/usr/bin/env python3
"""Recovery-host-only rehearsal: authenticate first, restore fresh scratch DB, compare every table and asset."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import time
from types import SimpleNamespace
import encrypted_backup
import mysql_backup


def restore(args):
    started = time.monotonic()
    if args.credentials.is_symlink() or not args.credentials.is_file() or args.credentials.stat().st_mode & 0o077:
        raise ValueError('Use a private recovery-host MySQL client file with mode 600.')
    # Never contact MySQL until age has authenticated the complete archive.
    with encrypted_backup.opened_bundle(args.backup, args.identity, args.work_root, args.age, args.max_archive_bytes) as bundle:
        manifest = mysql_backup.validate_bundle(bundle)
        name = 'pos_recovery_' + datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S%f') + '_restore'
        target = args.work_root / (name + '_assets')
        options = SimpleNamespace(credentials=args.credentials, mysql=args.mysql, mysqldump=args.mysqldump,
                                  database=name, assets=target, backup=bundle)
        mysql_backup.client(options, 'CREATE DATABASE `' + name + '` CHARACTER SET utf8mb4')
        mysql_backup.restore(options)  # Exact row counts, deterministic data hash, asset hashes.
        if args.drop_on_success:
            mysql_backup.client(options, 'DROP DATABASE `' + name + '`')
            shutil.rmtree(target)
        print(json.dumps({'scratch_database': name, 'row_counts': manifest['table_counts'],
                          'elapsed_seconds': round(time.monotonic() - started, 3),
                          'dropped_on_success': args.drop_on_success}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('credentials', 'backup', 'identity', 'work-root'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--mysql', default='mysql')
    parser.add_argument('--mysqldump', default='mysqldump')
    parser.add_argument('--age', default='age')
    parser.add_argument('--max-archive-bytes', type=int, default=20 * 1024 ** 3)
    parser.add_argument('--drop-on-success', action='store_true', help='Drop ONLY this command-generated scratch DB and its restored assets after all comparisons pass')
    args = parser.parse_args()
    try:
        restore(args)
    except Exception:
        parser.exit(1, 'Restore test failed. Preserve scratch DB/assets for private investigation. No existing DB was overwritten.\n')


if __name__ == '__main__':
    main()
