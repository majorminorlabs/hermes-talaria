#!/usr/bin/env python3
"""Fail closed on private paths, local identity, credentials, or signing payloads.

Reads files, tar/IPA contents and archive directories without extracting them.
Explicit --secret-file inputs remain in memory and are never printed.
Public bundle/launchd namespaces are intentionally retained.
"""
import argparse
import getpass
import io
import pathlib
import plistlib
import re
import tarfile
import zipfile

FORBIDDEN_PARTS = {'.git', '.venv', '__pycache__', '.pytest_cache', 'xcuserdata', '_CodeSignature'}
FORBIDDEN_SUFFIXES = ('.mobileprovision', '.p12', '.pfx', '.key', '.pem', '.log', '.xcresult')
PRIVATE_PATH = re.compile(rb'(?:/Users/[^/\s"\x00]+/|/Volumes/[^/\s"\x00]+/|/(?:private/)?var/folders/)' )
PRIVATE_HOST = re.compile(rb'[A-Za-z0-9-]+\.tail[a-z0-9]+\.ts\.net')
DEVICE_ID = re.compile(rb'\b00008[0-9A-Fa-f]{3}-[0-9A-Fa-f]{16}\b')
SECRET_MARKER = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{30,}')


def audit(paths, secrets=(), personal_name=None):
    findings = []
    inspected = 0
    name = (personal_name or getpass.getuser()).encode()
    identity = re.compile(rb'(?<![A-Za-z0-9_.])' + re.escape(name) + rb'(?![A-Za-z0-9_])')

    def check(label, data):
        nonlocal inspected
        inspected += 1
        path = pathlib.PurePosixPath(label)
        if any(p in FORBIDDEN_PARTS for p in path.parts) or path.name.lower().endswith(FORBIDDEN_SUFFIXES):
            findings.append((label, 'excluded/generated or signing file'))
        encoded_label = label.encode()
        for pattern, reason in [(PRIVATE_PATH, 'personal absolute path'), (PRIVATE_HOST, 'private tailnet hostname'),
                                (DEVICE_ID, 'physical device identifier'), (SECRET_MARKER, 'secret material'),
                                (identity, 'local user identity')]:
            if pattern.search(data) or pattern.search(encoded_label):
                findings.append((label, reason))
        if any(secret and len(secret) >= 16 and secret in data for secret in secrets):
            findings.append((label, 'known credential value'))
        if path.name == 'Info.plist':
            try:
                info = plistlib.loads(data)
            except Exception:
                return
            if 'ApplicationProperties' in info and info['ApplicationProperties'].get('SigningIdentity'):
                findings.append((label, 'archive signing identity'))

    for item in paths:
        p = pathlib.Path(item)
        if p.is_symlink():
            findings.append((p.name, 'symbolic link input')); continue
        if p.is_dir():
            for f in sorted(p.rglob('*')):
                if f.is_symlink(): findings.append((str(f.relative_to(p)), 'symbolic link'))
                elif f.is_file(): check(str(f.relative_to(p)), f.read_bytes())
        elif p.name.endswith('.tar.gz'):
            with tarfile.open(p) as archive:
                for m in archive.getmembers():
                    if m.uid or m.gid or m.uname or m.gname or m.mtime:
                        findings.append((m.name, 'non-normalized tar metadata'))
                    if not m.isfile():
                        findings.append((m.name, 'non-file archive member')); continue
                    check(m.name, archive.extractfile(m).read())
        elif zipfile.is_zipfile(p):
            with zipfile.ZipFile(p) as archive:
                for m in archive.infolist():
                    if not m.is_dir(): check(m.filename, archive.read(m))
        else:
            check(p.name, p.read_bytes())
    return inspected, sorted(set(findings))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifacts', nargs='+')
    parser.add_argument('--secret-file', action='append', default=[])
    args = parser.parse_args()
    secrets = [pathlib.Path(p).read_bytes().strip() for p in args.secret_file]
    count, findings = audit(args.artifacts, secrets)
    print(f'Inspected {count} payload files; privacy/signing findings: {len(findings)}.')
    # Only relative member names and classifications are printed, never matched data.
    for label, reason in findings:
        print(f'{reason}: {label}')
    return 1 if findings else 0

if __name__ == '__main__':
    raise SystemExit(main())
