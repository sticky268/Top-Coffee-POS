"""Private operator configuration and bounded, secret-free subprocess execution."""
import json
import os
from pathlib import Path
import subprocess


def private_file(path):
    path = Path(path)
    if path.is_symlink() or not path.is_file() or (os.name != 'nt' and path.stat().st_mode & 0o077):
        raise ValueError('Require a regular private file with mode 600 outside Git.')
    return path


def config(path):
    value = json.loads(private_file(path).read_text())
    if not isinstance(value, dict):
        raise ValueError('Configuration must be an object.')
    return value


def run(argv, *, cwd=None, timeout=1200):
    # Child diagnostics can contain credentials or row data; never echo them.
    result = subprocess.run([str(x) for x in argv], cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError('Operator command failed; inspect the relevant private service logs.')
    return result.stdout


def atomic_json(path, value):
    path = Path(path)
    temp = path.with_name(path.name + '.tmp')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)
