"""Independent certificate and off-site completion checks; no decryption keys."""
from datetime import datetime, timezone
import json
import re
import socket
import ssl
import subprocess
import threading
from urllib import parse
from common import private_file


def bounded_metadata(argv, *, timeout=30, max_bytes=4096):
    """Bound memory and elapsed time even for a hostile off-site listing."""
    with subprocess.Popen([str(x) for x in argv], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as process:
        def stop():
            try:
                process.kill()
            except ProcessLookupError:
                pass
        timer = threading.Timer(timeout, stop)
        timer.daemon = True
        timer.start()
        try:
            raw = process.stdout.read(max_bytes + 1)
            if len(raw) > max_bytes:
                raise ValueError('Oversized off-site metadata.')
            if process.wait(timeout=5) != 0:
                raise RuntimeError('Off-site metadata read failed or timed out.')
            return raw
        finally:
            timer.cancel()
            if process.poll() is None:
                stop()
            process.wait(timeout=5)


def certificate_remaining(settings, now):
    url = parse.urlsplit(settings['health_url'])
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('Require a plain HTTPS health URL.')
    # Use system trust, hostname verification and SNI. Never accept an unverified
    # certificate merely to extract its date.
    context = ssl.create_default_context()
    with socket.create_connection((url.hostname, url.port or 443), timeout=15) as connection:
        with context.wrap_socket(connection, server_hostname=url.hostname) as secured:
            return ssl.cert_time_to_seconds(secured.getpeercert()['notAfter']) - now


def completed_backup_age(settings, now, runner=bounded_metadata):
    remote = settings['backup_remote']
    if not re.fullmatch(r'[A-Za-z0-9_-]+:[A-Za-z0-9_./-]+', remote) or '..' in remote.split('/'):
        raise ValueError('Require the exact named off-site remote/prefix.')
    private_file(settings['backup_rclone_config'])
    base = ['rclone', '--config', settings['backup_rclone_config'], '--timeout', '15s', '--retries', '1']

    def read_json(arguments, limit):
        raw = runner(base + arguments, timeout=30, max_bytes=limit)
        if len(raw) > limit:
            raise ValueError('Oversized off-site metadata.')
        return json.loads(raw)

    entries = read_json(['lsjson', '--files-only', '--max-depth', '1', '--include', '/top-coffee-*.age.json', remote], 1024 * 1024)
    if not isinstance(entries, list) or len(entries) > 10000:
        raise ValueError('Invalid off-site listing.')
    candidates = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ValueError('Invalid off-site entry.')
        name = entry.get('Name', '')
        match = re.fullmatch(r'top-coffee-(\d{8}T\d{12}Z)\.age\.json', name)
        if not match:
            continue
        stamp = datetime.strptime(match[1], '%Y%m%dT%H%M%S%fZ').replace(tzinfo=timezone.utc).timestamp()
        if stamp > now + 300:
            raise ValueError('Future-dated completion marker.')
        candidates.append((stamp, name))
    if not candidates:
        raise ValueError('No completed off-site snapshot.')
    stamp, name = max(candidates)
    prefix = remote.rstrip('/') + '/'
    receipt = read_json(['cat', prefix + name], 4096)
    if not isinstance(receipt, dict):
        raise ValueError('Invalid completion marker.')
    created = datetime.fromisoformat(receipt['created_at'])
    if (created.tzinfo is None or abs(created.timestamp() - stamp) > 1
            or receipt.get('offsite_verified') is not True
            or not re.fullmatch(r'[a-f0-9]{64}', receipt.get('sha256', ''))
            or not re.fullmatch(r'[a-f0-9]{40}', receipt.get('commit', ''))
            or type(receipt.get('bytes')) is not int or receipt['bytes'] <= 0
            or receipt.get('remote') != prefix + name[:-5]):
        raise ValueError('Invalid completion evidence.')
    snapshot = read_json(['lsjson', '--stat', prefix + name[:-5]], 16384)
    if (not isinstance(snapshot, dict) or snapshot.get('IsDir') is not False
            or snapshot.get('Name') != name[:-5] or type(snapshot.get('Size')) is not int
            or snapshot['Size'] != receipt['bytes']):
        raise ValueError('Completed ciphertext is missing or its size changed.')
    # This checks independent arrival/age, not decryption, producer identity or
    # current whole-object integrity. Restore drills still verify those separately.
    return max(0, now - stamp)


def infrastructure_events(settings, now, certificate=certificate_remaining, backup=completed_backup_age):
    days, age = settings['tls_min_days'], settings['backup_max_age_seconds']
    if type(days) is not int or not 1 <= days <= 60 or type(age) is not int or not 3600 <= age <= 172800:
        raise ValueError('Require TLS threshold 1-60 days and backup age 1-48 hours.')
    events = []
    try:
        remaining = certificate(settings, now)
        if remaining <= 0:
            events.append('tls_failed')
        elif remaining <= days * 86400:
            events.append('tls_expiring')
    except Exception:
        events.append('tls_failed')
    try:
        if backup(settings, now) > age:
            events.append('backup_stale')
    except Exception:
        events.append('backup_stale')
    return events
