# Release packaging

Current source is **0.2.0 / build 2**, including the app, Live Activity extension and
bridge. Canonical app ID is `xyz.majorminor.talaria`; the extension derives
`<app ID>.LiveActivity`. Personal Team/signing belongs in ignored local configuration.
The existing **v0.1.0 prerelease** and its artifacts remain unchanged.
The **v0.2.0 prerelease** includes an unsigned IPA, archive ZIP, bridge package
and checksums after [physical acceptance](docs/PHYSICAL_ACCEPTANCE_v0.2.0.md).

## Build and verify

```sh
scripts/build-ios-release.sh --output-dir build/release/v0.2.0 \
  --sidestore-ipa --physical-validation-report docs/PHYSICAL_ACCEPTANCE_v0.2.0.md
python3 scripts/test_release_artifacts.py -v
python3 scripts/audit-release-artifacts.py \
  build/release/v0.2.0/Talaria-v0.2.0.xcarchive \
  build/release/v0.2.0/hermes-mobile-bridge-v0.2.0.tar.gz
```

The build makes an unsigned device Release archive with the embedded extension and
normalized tracked bridge source package. DerivedData is temporary, signing is
cleared and compiler/debug paths remapped. Existing archive output is never overwritten.
No IPA is made by default. Verify app/extension IDs, version/build parity, absent
signatures/profiles, packaged links and privacy scan before distribution.

The optional `--sidestore-ipa --physical-validation-report PATH` gate requires the
exact `physical_device_validation: PASS`,
`validation_bundle_identifier: xyz.majorminor.talaria` and
`validation_version: 0.2.0` markers. **Do not reuse the old 0.1.0 report
as acceptance for 0.2.0.** Current Xcode installation, voice, camera and Live Activity
acceptance passed; untested SideStore refresh/expiry cases remain documented. The marker is human evidence, not a cryptographic device attestation.
After current acceptance, the same command packages an unsigned Payload/Hermes.app
for SideStore signing and writes SHA256SUMS.txt. Signed artifacts stay outside Git.

Bridge packaging alone: `scripts/package-bridge.sh --output-dir build/release/v0.2.0`.
It includes source, service scripts and linked public guides; excludes runtime state,
captures, databases, credentials, environments and caches. The archive should be
installed and CLI-tested in a clean virtual environment before distribution.

Keep installed app ID/Team stable to retain local state. Xcode source installation
and SideStore signing/expiry guidance remain in [installation](docs/INSTALL.md) and
[Xcode](docs/XCODE_INSTALL.md). Choosing another TALARIA_APP_BUNDLE_ID creates a
separate app identity and matching extension. Do not override PRODUCT_BUNDLE_IDENTIFIER
globally: that would give the app and extension the same ID.

Review [current readiness](docs/RELEASE_READINESS.md), [changelog](CHANGELOG.md) and
[privacy](docs/PRIVACY_SECURITY.md). Publication was authorized by the owner after current physical acceptance;
release scripts themselves publish nothing.
