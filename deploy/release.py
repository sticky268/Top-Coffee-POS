#!/usr/bin/env python3
"""Atomic code activation/rollback for prebuilt releases. Never migrates or restores a database."""
import argparse
from datetime import datetime, timezone
import fcntl
import os
from pathlib import Path
import re
from common import config, run


def release_path(root, sha):
    if not re.fullmatch(r'[a-f0-9]{40}', sha):
        raise ValueError('Use an exact reviewed 40-character commit SHA.')
    parent = root / 'releases'
    path = parent / sha
    if parent.is_symlink() or path.is_symlink() or not path.is_dir() or path.resolve().parent != parent.resolve():
        raise ValueError('Require a prebuilt real release directory within releases/.')
    for relative in ('backend-skeleton/artisan', 'backend-skeleton/vendor/autoload.php'):
        if not (path / relative).is_file():
            raise ValueError('Release dependencies are missing.')
    backend = path / 'backend-skeleton'
    if (backend / '.env').resolve() != (root / 'shared/.env').resolve() or not (backend / '.env').is_symlink():
        raise ValueError('Release .env must point at the shared private configuration.')
    if (backend / 'storage').resolve() != (root / 'shared/storage').resolve() or not (backend / 'storage').is_symlink():
        raise ValueError('All releases must share maintenance state, logs, sessions and assets.')
    return path


def swap(link, target):
    temp = link.with_name(link.name + '.next')
    if temp.exists() or temp.is_symlink():
        raise ValueError('Stale activation link exists; inspect it before retrying.')
    temp.symlink_to(target)
    os.replace(temp, link)


def activate(root, sha, evidence, *, writes_drained, schema_compatible, runner=run):
    if not writes_drained or not schema_compatible:
        raise ValueError('Require both reviewed write drain and code/schema compatibility. No automatic down-migrations.')
    root = root.resolve()
    target = release_path(root, sha)
    current = root / 'current'
    if not current.is_symlink():
        raise ValueError('Bootstrap a reviewed staging release first; current must be a release symlink.')
    old = release_path(root, current.resolve().name)
    if current.resolve() != old or old == target:
        raise ValueError('Current release must be valid and different from target.')
    proof = config(evidence)
    created = datetime.fromisoformat(proof.get('created_at', ''))
    age = (datetime.now(timezone.utc) - created).total_seconds()
    if (proof.get('offsite_verified') is not True or not re.fullmatch(r'[a-f0-9]{64}', proof.get('sha256', ''))
            or proof.get('commit') != old.name or not 0 <= age <= 86400):
        raise ValueError('Require a verified off-site backup receipt for the current commit, less than 24 hours old.')

    def artisan(release, *args):
        return runner(['runuser', '-u', 'posapp', '--', '/usr/bin/php', 'artisan', *args], cwd=release / 'backend-skeleton')

    with open(root / '.release.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if current.resolve() != old:
            raise ValueError('Current changed during preparation; review again.')
        artisan(target, 'config:cache')
        artisan(target, 'pos:production-check', '--json')
        artisan(target, 'pos:business-settings-check', '--json')  # Missing PIN currently blocks here.
        stopped = []
        down = False
        switched = False
        try:
            for unit in ('top-coffee-scheduler.timer', 'top-coffee-scheduler.service', 'top-coffee-queue.service'):
                state = runner(['systemctl', 'show', '--property=ActiveState', '--value', unit]).strip()
                if state not in (b'active', b'inactive', b'failed'):
                    raise RuntimeError('Cannot establish writer service state.')
                if state == b'active':
                    stopped.append(unit)
                    runner(['systemctl', 'stop', unit])
            artisan(old, 'down', '--retry=60')
            down = True
            swap(current, target)
            switched = True
            runner(['systemctl', 'reload', 'php8.3-fpm.service'])
            artisan(target, 'pos:operations-health', '--json')
            artisan(target, 'up')
            down = False
            swap(root / 'previous', old)
        except Exception:
            if switched:
                swap(current, old)
                runner(['systemctl', 'reload', 'php8.3-fpm.service'])
            if down:
                artisan(old, 'up')
            raise
        finally:
            errors = []
            for unit in reversed(stopped):
                try:
                    runner(['systemctl', 'start', unit])
                except Exception:
                    errors.append(unit)
            if errors:
                raise RuntimeError('Writer restart failed. Keep the incident open and inspect service state.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['deploy', 'rollback'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--release', help='Prepared exact commit SHA for deploy')
    parser.add_argument('--backup-receipt', type=Path)
    parser.add_argument('--writes-drained', action='store_true')
    parser.add_argument('--schema-compatible', action='store_true')
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    try:
        sha = args.release
        if args.action == 'rollback':
            previous = args.root / 'previous'
            if not previous.is_symlink():
                raise ValueError('No recorded previous release.')
            sha = previous.resolve().name
        if not sha:
            raise ValueError('Choose an exact prepared release.')
        release_path(args.root.resolve(), sha)
        if not args.execute:
            print('PLAN ONLY: validate gates; stop writers; maintenance; atomic code switch; reload FPM; health; resume. No DB migrations.')
            return
        if not args.backup_receipt:
            raise ValueError('A private verified backup receipt is required.')
        activate(args.root, sha, args.backup_receipt, writes_drained=args.writes_drained, schema_compatible=args.schema_compatible)
        print('Code activation completed. Verify external HTTPS and business smoke checks; no database rollback was performed.')
    except Exception:
        parser.exit(1, 'Release refused or failed. Inspect private gate output/service state and current symlink. Do not run database down-migrations.\n')


if __name__ == '__main__':
    main()
