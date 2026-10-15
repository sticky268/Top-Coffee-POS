#!/usr/bin/env python3
"""age-encrypted MySQL backup and isolated recovery. No production keys generated."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

import mysql_backup

MEMBERS = {'manifest.json', 'database.sql.gz', 'assets.tar.gz'}


def private_directory(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink() or (os.name != 'nt' and path.stat().st_mode & 0o077):
        raise ValueError('Use a private directory with permissions 700.')


def recipients(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Recipients must be a regular public-key file.')
    values = [line.strip() for line in path.read_text().splitlines()
              if line.strip() and not line.lstrip().startswith('#')]
    # No passphrases, plugins, SSH keys or private identities on backup hosts.
    if not values or any(not re.fullmatch(r'age1[023456789acdefghjklmnpqrstuvwxyz]+', value) for value in values):
        raise ValueError('Supply native age public recipients only; never a private identity.')
    return values


def seal(source, output, recipient_file, age='age'):
    mysql_backup.validate_bundle(source)
    keys = recipients(recipient_file)
    private_directory(output.parent)
    if output.exists() or output.is_symlink() or output.suffix != '.age':
        raise ValueError('Choose a new .age output; existing backups are never overwritten.')
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.encrypt-', dir=output.parent, delete=False) as encrypted:
            temporary = Path(encrypted.name)
            with tempfile.TemporaryFile() as errors:
                command = [age, '--encrypt']
                for key in keys:
                    command.extend(['--recipient', key])
                process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=encrypted, stderr=errors)
                try:
                    with tarfile.open(fileobj=process.stdin, mode='w|') as archive:
                        for name in sorted(MEMBERS):
                            archive.add(source / name, arcname=name, recursive=False)
                    process.stdin.close()
                    if process.wait() != 0:
                        raise RuntimeError('age encryption failed; no completed backup published.')
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
            encrypted.flush()
            os.fsync(encrypted.fileno())
        # Atomic no-replace publication on the same filesystem.
        os.link(temporary, output)
        if os.name != 'nt':
            directory = os.open(output.parent, os.O_DIRECTORY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        return {'encrypted': True, 'sha256': mysql_backup.sha(output), 'bytes': output.stat().st_size}
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def extract_bundle(archive_path, destination):
    with tarfile.open(archive_path, 'r:') as archive:
        found = set()
        members = []
        for member in archive:
            if member.name not in MEMBERS or member.name in found or not member.isfile():
                raise ValueError('Encrypted bundle contains an unexpected member, duplicate or link.')
            if member.name == 'manifest.json' and member.size > 1024 * 1024:
                raise ValueError('Backup manifest exceeds the supported limit.')
            found.add(member.name)
            members.append(member)
        if found != MEMBERS:
            raise ValueError('Encrypted backup is incomplete.')
        destination.mkdir(mode=0o700)
        for member in members:
            with archive.extractfile(member) as source, (destination / member.name).open('xb') as target:
                shutil.copyfileobj(source, target)
    mysql_backup.validate_bundle(destination)


@contextlib.contextmanager
def opened_bundle(backup, identity, work_root, age='age', max_bytes=20 * 1024 ** 3):
    if identity.is_symlink() or not identity.is_file():
        raise ValueError('A private recovery identity file is required.')
    if os.name != 'nt' and identity.stat().st_mode & 0o077:
        raise ValueError('Recovery identity must have permissions 600.')
    if max_bytes <= 0:
        raise ValueError('Archive size limit must be positive.')
    private_directory(work_root)
    with tempfile.TemporaryDirectory(prefix='.recovery-', dir=work_root) as work:
        archive_path = Path(work) / 'bundle.tar'
        with archive_path.open('xb') as target, tempfile.TemporaryFile() as errors:
            process = subprocess.Popen([age, '--decrypt', '--identity', str(identity), str(backup)],
                                       stdout=subprocess.PIPE, stderr=errors, stdin=subprocess.DEVNULL)
            try:
                total = 0
                while block := process.stdout.read(1024 * 1024):
                    total += len(block)
                    if total > max_bytes:
                        raise ValueError('Decrypted archive exceeds the configured size limit.')
                    target.write(block)
                if process.wait() != 0:
                    raise ValueError('Decryption/authentication failed. No database connection attempted.')
            finally:
                process.stdout.close()
                if process.poll() is None:
                    process.kill()
                    process.wait()
        bundle = Path(work) / 'bundle'
        extract_bundle(archive_path, bundle)
        yield bundle


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--age', default='age')
    commands = parser.add_subparsers(dest='command', required=True)
    save = commands.add_parser('backup')
    save.add_argument('--database', type=mysql_backup.database, required=True)
    save.add_argument('--assets', type=Path, required=True)
    save.add_argument('--commit', required=True)
    save.add_argument('--writes-drained', action='store_true')
    for command in [save, commands.add_parser('seal')]:
        command.add_argument('--recipients', type=Path, required=True)
        command.add_argument('--output', type=Path, required=True)
    commands.choices['seal'].add_argument('--source', type=Path, required=True)
    replay = commands.add_parser('restore-rehearsal')
    replay.add_argument('--backup', type=Path, required=True)
    replay.add_argument('--identity', type=Path, required=True)
    replay.add_argument('--work-root', type=Path, required=True)
    replay.add_argument('--max-archive-bytes', type=int, default=20 * 1024 ** 3)
    replay.add_argument('--database', type=mysql_backup.database, required=True)
    replay.add_argument('--assets', type=Path, required=True)
    for command in [save, replay]:
        command.add_argument('--credentials', type=Path, required=True)
        command.add_argument('--mysql', default='mysql')
        command.add_argument('--mysqldump', default='mysqldump')
    args = parser.parse_args()
    try:
        if args.command == 'seal':
            print(json.dumps(seal(args.source, args.output, args.recipients, args.age)))
            return
        if args.credentials.is_symlink() or not args.credentials.is_file():
            raise ValueError('Private MySQL client file is required.')
        if os.name != 'nt' and args.credentials.stat().st_mode & 0o077:
            raise ValueError('MySQL client file must have permissions 600.')
        if args.command == 'backup':
            recipients(args.recipients)
            output = args.output
            private_directory(output.parent)
            if output.exists() or output.is_symlink() or output.suffix != '.age':
                raise ValueError('Choose a new .age output.')
            with tempfile.TemporaryDirectory(prefix='.private-backup-', dir=output.parent) as work:
                args.output = Path(work)
                bundle = mysql_backup.backup(args, report=False)
                print(json.dumps(seal(bundle, output, args.recipients, args.age)))
        else:
            with opened_bundle(args.backup, args.identity, args.work_root, args.age, args.max_archive_bytes) as bundle:
                args.backup = bundle
                mysql_backup.restore(args)
    except (ValueError, RuntimeError) as error:
        parser.exit(1, str(error) + '\n')
    except (OSError, subprocess.SubprocessError, tarfile.TarError):
        parser.exit(1, 'Encrypted backup/recovery failed. Preserve inputs; inspect private operator diagnostics.\n')


if __name__ == '__main__':
    main()
