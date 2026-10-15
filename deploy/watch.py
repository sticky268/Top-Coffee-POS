#!/usr/bin/env python3
"""External HTTPS monitor: health and failed-login spike alerts with durable cooldown."""
import argparse
import json
import time
import fcntl
from pathlib import Path
from urllib import request, error, parse
from alerts import NoRedirect, deliver
from common import config, atomic_json


def probe(settings, opener=None):
    url = settings['health_url']
    parsed = parse.urlsplit(url)
    token = settings['health_token']
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or len(token) < 32:
        raise ValueError('Require HTTPS URL without credentials/query and a dedicated monitor token.')
    req = request.Request(url, headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/json'})
    opener = opener or request.build_opener(NoRedirect())
    try:
        response = opener.open(req, timeout=15)
    except error.HTTPError as failure:
        if failure.code != 503:
            raise RuntimeError('Health request rejected.') from None
        response = failure
    with response:
        raw = response.read(65537)
        if response.code not in (200, 503) or len(raw) > 65536:
            raise ValueError('Invalid health response.')
    report = json.loads(raw)
    checks = report.get('checks')
    if (not isinstance(checks, dict) or not checks or type(report.get('healthy')) is not bool
            or any(type(value) is not bool for value in checks.values())
            or report['healthy'] != all(checks.values())
            or (response.code == 200) != report['healthy']):
        raise ValueError('Invalid health report.')
    return report


def monitor(settings, state, fetch=probe, send=deliver, now=None):
    now = int(time.time()) if now is None else now
    try:
        report = fetch(settings)
        events = [] if report['healthy'] else ['health_failed']
        if report['checks'].get('failed_login_limit_not_reached') is False:
            events.append('failed_login_spike')
    except Exception:
        events = ['health_failed']
    cooldown = int(settings.get('cooldown_seconds', 900))
    if not 60 <= cooldown <= 86400:
        raise ValueError('Cooldown must be 60-86400 seconds.')
    for event in events:
        last = state.get(event)
        if last is None or now < last or now - last >= cooldown:
            send(config(settings['alerts_config']), event)
            state[event] = now  # Never suppress a retry unless the provider acknowledged.
    return not events


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    try:
        settings = config(args.config)
        path = Path(settings['state_file'])
        if not path.parent.is_dir() or path.parent.stat().st_mode & 0o077:
            raise ValueError('State directory must already exist with mode 700.')
        with open(path.with_suffix('.lock'), 'a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            state = config(path) if path.exists() else {}
            healthy = monitor(settings, state)
            atomic_json(path, state)
        if not healthy:
            parser.exit(1, 'Monitor unhealthy; acknowledged alerts obey the cooldown.\n')
    except Exception:
        parser.exit(1, 'Monitor failed. Inspect configuration/network and independent monitoring service logs.\n')


if __name__ == '__main__':
    main()
