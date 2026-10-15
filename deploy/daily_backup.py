#!/usr/bin/env python3
"""Closed-shop encrypted backup, verified off-site copy and conservative local retention."""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys
from alerts import deliver
from common import atomic_json, config, private_file, run

TOOLS = Path(__file__).resolve().parents[1] / 'backend-skeleton' / 'tools'


def digest(path):
    value = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def offsite(settings, source, runner=run):
    private_file(settings['rclone_config'])
    destination = settings['remote'].rstrip('/') + '/' + source.name
    if not re.fullmatch(r'[A-Za-z0-9_-]+:[A-Za-z0-9_./-]+', settings['remote']) or '..' in settings['remote'].split('/'):
        raise ValueError('Use a configured named remote and fixed bucket/directory prefix.')
    base = ['rclone', '--config', settings['rclone_config'], '--timeout', '2m', '--retries', '2']
    runner(base + ['copyto', '--immutable', str(source), destination])
    value = hashlib.sha256()
    # Re-read ciphertext from the remote; success is not inferred from upload exit alone.
    with subprocess.Popen(base + ['cat', destination], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
        for block in iter(lambda: process.stdout.read(1024 * 1024), b''):
            value.update(block)
        if process.wait(timeout=180) != 0 or value.hexdigest() != digest(source):
            raise RuntimeError('Off-site ciphertext read-back did not match.')
    return destination


def validate(settings, now):
    if settings.get('closed_window_approved') is not True:
        raise ValueError('Owner must approve a daily closed-shop maintenance window first.')
    hour = settings.get('utc_hour')
    if type(hour) is not int or not 0 <= hour <= 23 or now.hour != hour:
        raise ValueError('Outside the approved UTC maintenance hour.')
    if not re.fullmatch(r'[a-f0-9]{40}', settings.get('commit', '')):
        raise ValueError('Record the deployed source commit, not a moving branch.')
    units = settings.get('writer_units', [])
    if not units or not any(re.fullmatch(r'php[0-9.]+-fpm.service', x) for x in units):
        raise ValueError('Include the dedicated PHP-FPM service among all writer units.')
    if len(set(units)) != len(units) or any(not re.fullmatch(r'(?:php[0-9.]+-fpm\.service|top-coffee-(?:queue|scheduler)\.service|top-coffee-scheduler\.timer)', unit) for unit in units):
        raise ValueError('Use explicit PHP-FPM, queue and scheduler unit names.')
    if not {'top-coffee-scheduler.timer', 'top-coffee-scheduler.service'}.issubset(units):
        raise ValueError('Stop both the scheduler timer and its current service invocation.')
    if settings.get('all_writers_listed') is not True:
        raise ValueError('Operator must inventory scheduler, workers and every other DB/asset writer.')
    for key in ('credentials', 'rclone_config'):
        private_file(settings[key])
    for key in ('spool', 'assets', 'recipients'):
        if not Path(settings[key]).is_absolute():
            raise ValueError('Use absolute operator paths.')
    if not Path(settings['assets']).is_dir():
        raise ValueError('Assets directory missing.')
    if settings.get('local_retention_days', 7) < 2:
        raise ValueError('Keep at least two days locally.')


def prune(spool, days, now):
    verified = []
    for receipt in spool.glob('top-coffee-*.age.json'):
        try:
            data = json.loads(receipt.read_text())
            source = Path(str(receipt)[:-5])
            if data.get('offsite_verified') is True and source.is_file() and not source.is_symlink():
                verified.append((source, receipt))
        except (ValueError, OSError):
            continue
    # Never remove the two newest verified local restore points, or unverified files.
    for source, receipt in sorted(verified, key=lambda pair: pair[0].name, reverse=True)[2:]:
        if now.timestamp() - source.stat().st_mtime > days * 86400:
            source.unlink()
            receipt.unlink()


def backup(settings, runner=run, upload=offsite, now=None):
    now = now or datetime.now(timezone.utc)
    validate(settings, now)
    spool = Path(settings['spool'])
    spool.mkdir(mode=0o700, parents=True, exist_ok=True)
    if spool.is_symlink() or spool.stat().st_mode & 0o077:
        raise ValueError('Spool must be a private mode-700 directory.')
    output = spool / ('top-coffee-' + now.strftime('%Y%m%dT%H%M%S%fZ') + '.age')
    with open(spool / '.backup.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        active = []
        restart_errors = []
        try:
            for unit in settings['writer_units']:
                state = runner(['systemctl', 'show', '--property=ActiveState', '--value', unit]).strip()
                if state not in (b'active', b'inactive', b'failed'):
                    raise RuntimeError('Writer unit has an unknown or transitional state.')
                if state == b'active':
                    active.append(unit)
                    runner(['systemctl', 'stop', unit])
            runner([sys.executable, TOOLS / 'encrypted_backup.py', 'backup',
                    '--credentials', settings['credentials'], '--database', settings['database'],
                    '--assets', settings['assets'], '--commit', settings['commit'], '--writes-drained',
                    '--recipients', settings['recipients'], '--output', output])
        finally:
            # Always attempt every restart, even if an earlier restart fails.
            for unit in reversed(active):
                try:
                    runner(['systemctl', 'start', unit])
                except Exception:
                    restart_errors.append(unit)
            if restart_errors:
                raise RuntimeError('One or more writer services could not be restarted.')
        destination = upload(settings, output)
        atomic_json(Path(str(output) + '.json'), {'offsite_verified': True, 'sha256': digest(output),
                    'remote': destination, 'created_at': now.isoformat(), 'commit': settings['commit']})
        if settings.get('retention_approved') is True:
            prune(spool, settings.get('local_retention_days', 7), now)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('--execute', action='store_true', help='Actually pause writers, back up and upload')
    args = parser.parse_args()
    settings = None
    try:
        settings = config(args.config)
        if not args.execute:
            print('PLAN ONLY: pause inventoried writers during approved UTC hour; encrypt; restart; upload/read-back; retain verified snapshots.')
            return
        output = backup(settings)
        print(json.dumps({'backup': output.name, 'offsite_verified': True}))
    except Exception:
        if settings and settings.get('alerts_config'):
            try:
                deliver(config(settings['alerts_config']), 'backup_failed')
            except Exception:
                print('Backup alert delivery also failed; inspect independent monitor and system journal.', file=sys.stderr)
        parser.exit(1, 'Backup job failed. Check private configuration, service state and last verified snapshot; no failed backup was pruned.\n')


if __name__ == '__main__':
    main()
