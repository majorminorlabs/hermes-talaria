#!/usr/bin/env python3
"""Focused privacy and reproducibility checks for release packaging."""
import importlib.util
import pathlib
import re
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_audit', ROOT/'scripts/audit-release-artifacts.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

class ReleaseTests(unittest.TestCase):
    def test_bridge_package_reproducible_and_installable(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = pathlib.Path(tmp)
            packages=[]
            for output in (base/'one', base/'two'):
                subprocess.run([str(ROOT/'scripts/package-bridge.sh'), '--output-dir', str(output)], check=True, capture_output=True)
                packages.append(next(output.glob('*.tar.gz')))
            self.assertEqual(packages[0].read_bytes(), packages[1].read_bytes())
            count, findings = audit.audit([packages[0]])
            self.assertGreater(count, 20)
            self.assertEqual(findings, [])
            with tarfile.open(packages[0]) as archive:
                member_names = archive.getnames()
                self.assertEqual(len(member_names), len(set(member_names)), 'Duplicate tar members')
                archive.extractall(base/'extracted', filter='data')
            package_root=base/'extracted/hermes-mobile-bridge-release'
            for command in ('install', 'update', 'uninstall', 'status'):
                result=subprocess.run([str(package_root/f'scripts/{command}-bridge.sh'), '--help'], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((package_root/'hermes-mobile-bridge/src/hermes_mobile_bridge/__init__.py').exists())
            for document in package_root.rglob('*.md'):
                for target in re.findall(r'\[[^\]]*\]\(([^)]+)\)', document.read_text()):
                    if target.startswith(('https:', 'http:', 'mailto:', '#')):
                        continue
                    linked = target.split('#')[0]
                    self.assertTrue((document.parent/linked).is_file(), f'{document.relative_to(package_root)}: {target}')
            self.assertTrue((package_root/'docs/sidestore/0001-restore-preferred-bundle-id-team-rule.patch').is_file())

    def test_old_version_physical_pass_cannot_authorize_current_ipa(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = pathlib.Path(tmp)/'physical.md'
            report.write_text('physical_device_validation: PASS\nvalidation_bundle_identifier: xyz.majorminor.talaria\nvalidation_version: 0.1.0\n')
            result = subprocess.run([str(ROOT/'scripts/build-ios-release.sh'), '--sidestore-ipa',
                                     '--physical-validation-report', str(report)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('validation_version: 0.2.1', result.stderr)

    def test_detects_payload_privacy_and_signing(self):
        with tempfile.TemporaryDirectory() as tmp:
            artifact=pathlib.Path(tmp)/'example.ipa'
            secret=b'credential-fixture-for-audit-only-123456'
            with zipfile.ZipFile(artifact, 'w') as output:
                output.writestr('Payload/App.app/content', b'/Users/example/private\x00'+secret+b'\x00host.tail01234.ts.net')
                output.writestr('Payload/App.app/embedded.mobileprovision', b'fixture')
            _, findings=audit.audit([artifact], [secret], 'example')
            reasons={reason for _,reason in findings}
            self.assertTrue({'personal absolute path','known credential value','private tailnet hostname','excluded/generated or signing file'} <= reasons)

    def test_public_namespace_is_retained(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)/'public'
            p.write_bytes(b'xyz.majorminor.talaria https://your-mac.your-tailnet.ts.net')
            _, findings=audit.audit([p], personal_name=__import__('getpass').getuser())
            self.assertEqual(findings, [])

    def test_unsigned_ipa_needs_a_report_or_explicit_exception(self):
        result = subprocess.run([str(ROOT/'scripts/build-ios-release.sh'), '--sidestore-ipa'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('requires --physical-validation-report', result.stderr)

    def test_other_identity_physical_pass_cannot_authorize_this_ipa(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = pathlib.Path(tmp)/'physical.md'
            report.write_text('physical_device_validation: PASS\nvalidation_bundle_identifier: com.example.legacy\n')
            result = subprocess.run([str(ROOT/'scripts/build-ios-release.sh'), '--sidestore-ipa',
                                     '--physical-validation-report', str(report)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('validation_bundle_identifier: xyz.majorminor.talaria', result.stderr)

    def test_unsigned_exception_cannot_be_misrepresented_as_physical_validation(self):
        for args in (['--allow-unvalidated-ipa'], ['--sidestore-ipa', '--allow-unvalidated-ipa', '--physical-validation-report', 'unused.md']):
            result = subprocess.run([str(ROOT/'scripts/build-ios-release.sh'), *args], capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertIn('requires --sidestore-ipa and excludes a physical report', result.stderr)

    def test_rejects_archive_owner_metadata(self):
        import io
        with tempfile.TemporaryDirectory() as tmp:
            p=pathlib.Path(tmp)/'fixture.tar.gz'
            with tarfile.open(p, 'w:gz') as output:
                m=tarfile.TarInfo('runtime.py');m.uname='fixture-owner';m.size=1
                output.addfile(m, io.BytesIO(b'x'))
            _,findings=audit.audit([p])
            self.assertIn(('runtime.py','non-normalized tar metadata'),findings)

if __name__=='__main__': unittest.main()
