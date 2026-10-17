#!/usr/bin/env python3
"""Fail CI if tracked paths or JKS/JCEKS/PEM contents include private signing material."""
from pathlib import Path
import re
import subprocess
import sys


def violations(root):
    paths = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
    bad = []
    for name in filter(None, paths):
        path = Path(name)
        if path.name == 'key.properties' or path.suffix.lower() in ('.jks', '.keystore', '.p12', '.pfx', '.agekey'):
            bad.append(name)
            continue
        full = root / path
        if full.is_file():
            with full.open('rb') as stream:
                prefix = stream.read(4096)
            if prefix[:4] in (b'\xfe\xed\xfe\xed', b'\xce\xce\xce\xce') or re.search(rb'(?m)^-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----\r?$', prefix):
                bad.append(name)
    return bad


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[1]
    bad = violations(root)
    if bad:
        print('FAIL: tracked signing/private key material at ' + ', '.join(bad), file=sys.stderr)
        sys.exit(1)
    print('PASS: no tracked signing keys or key.properties.')
