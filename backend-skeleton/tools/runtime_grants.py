#!/usr/bin/env python3
"""Render per-table grants for a NEW MySQL account; never apply privileges."""
import argparse
from pathlib import Path
import os
import re
import subprocess
import mysql_backup


def statements(database, tables, user, host):
    if any(not re.fullmatch(r'[A-Za-z0-9_]+', value) for value in [database, user, *tables]):
        raise ValueError('Only simple database, account and table identifiers are supported.')
    if host not in ['localhost', '127.0.0.1']:
        raise ValueError('Reference grants allow local database connections only.')
    if 'audit_logs' not in tables or 'migrations' not in tables:
        raise ValueError('Migrate the isolated target before rendering runtime grants.')
    result = ['-- NEW account only: any broader existing grant defeats table restrictions.',
              '-- Create its private password separately. This output never creates an account.']
    for table in sorted(set(tables)):
        privilege = 'SELECT, INSERT' if table == 'audit_logs' else ('SELECT' if table == 'migrations' else 'SELECT, INSERT, UPDATE, DELETE')
        result.append(f"GRANT {privilege} ON `{database}`.`{table}` TO '{user}'@'{host}';")
    result.append(f"SHOW GRANTS FOR '{user}'@'{host}';")
    return '\n'.join(result) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--credentials', type=Path, required=True)
    parser.add_argument('--mysql', default='mysql')
    parser.add_argument('--database', type=mysql_backup.database, required=True)
    parser.add_argument('--user', default='pos_runtime')
    parser.add_argument('--host', default='localhost')
    args = parser.parse_args()
    if args.credentials.is_symlink() or not args.credentials.is_file():
        parser.error('Private MySQL option file is required.')
    if os.name != 'nt' and args.credentials.stat().st_mode & 0o077:
        parser.error('MySQL option file must have permissions 600.')
    try:
        tables = mysql_backup.client(args, f"SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA='{args.database}' AND TABLE_TYPE='BASE TABLE'").splitlines()
        print(statements(args.database, tables, args.user, args.host), end='')
    except (ValueError, OSError, subprocess.SubprocessError):
        parser.exit(1, 'Could not render runtime grants. No permissions changed.\n')


if __name__ == '__main__':
    main()
