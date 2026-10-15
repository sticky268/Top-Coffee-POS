#!/usr/bin/env python3
"""Disposable loopback Nginx acceptance; no PHP server, real cert or public host."""
import os
from pathlib import Path
import ssl
import subprocess
import tempfile
import time
import urllib.error
import urllib.request


def main():
    template = Path(__file__).resolve().parents[2] / 'deploy/nginx.conf.example'
    with tempfile.TemporaryDirectory() as work:
        root = Path(work)
        # Nginx workers run as the current CI user; no public interfaces used.
        (root / 'public/storage').mkdir(parents=True)
        (root / '.env').write_text('SYNTHETIC-SECRET-OUTSIDE-PUBLIC')
        (root / 'public/storage/blocked.php').write_text('SYNTHETIC-PHP-SOURCE')
        (root / 'public/storage/blocked.PHP').write_text('SYNTHETIC-PHP-SOURCE')
        (root / 'public/storage/logo.txt').write_text('public-product-image-fixture')
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=api.example.invalid', '-keyout', str(root / 'key.pem'),
                        '-out', str(root / 'cert.pem')], check=True, capture_output=True)
        config = template.read_text().replace('listen 80;', 'listen 127.0.0.1:18080;')
        config = config.replace('listen 443 ssl;', 'listen 127.0.0.1:18443 ssl;')
        config = config.replace('/srv/top-coffee/current/backend-skeleton/public', str(root / 'public'))
        config = config.replace('/etc/letsencrypt/live/api.example.invalid/fullchain.pem', str(root / 'cert.pem'))
        config = config.replace('/etc/letsencrypt/live/api.example.invalid/privkey.pem', str(root / 'key.pem'))
        config = config.replace('/var/log/nginx/top-coffee-access.log', str(root / 'access.log'))
        config = config.replace('/var/log/nginx/top-coffee-error.log', str(root / 'error.log'))
        (root / 'site.conf').write_text(config)
        (root / 'nginx.conf').write_text(f'pid {root}/nginx.pid;\nerror_log stderr;\nevents {{}}\nhttp {{ access_log off; include {root}/site.conf; }}\n')
        command = ['nginx', '-p', str(root), '-c', str(root / 'nginx.conf')]
        subprocess.run(command + ['-t'], check=True)
        server = subprocess.Popen(command + ['-g', 'daemon off;'], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        # The self-signed certificate and disabled verification are CI-only.
        context = ssl._create_unverified_context()
        def request(path):
            req = urllib.request.Request('https://127.0.0.1:18443' + path, headers={'Host': 'api.example.invalid'})
            try:
                response = urllib.request.urlopen(req, context=context, timeout=3)
            except urllib.error.HTTPError as error:
                response = error
            with response:
                return response.status, response.read()
        try:
            for attempt in range(30):
                try:
                    if request('/storage/logo.txt')[0] == 200:
                        break
                except OSError:
                    pass
                time.sleep(0.1)
            else:
                raise RuntimeError('Loopback Nginx did not become ready.')
            assert request('/storage/logo.txt')[1] == b'public-product-image-fixture'
            for path in ['/.env', '/.git/HEAD', '/storage/blocked.php', '/storage/blocked.PHP', '/storage/blocked.php/extra']:
                status, body = request(path)
                assert status in [403, 404], (path, status)
                assert b'SYNTHETIC-' not in body
            request('/storage/logo.txt?token=DO-NOT-LOG-THIS')
            assert 'DO-NOT-LOG-THIS' not in (root / 'access.log').read_text()
            print('PASS: Nginx syntax, public assets, hidden-file/PHP denial and query-free access logs on loopback.')
        finally:
            server.terminate()
            server.communicate(timeout=10)


if __name__ == '__main__':
    main()
