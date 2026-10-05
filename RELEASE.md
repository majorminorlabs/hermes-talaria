# Talaria release packaging

Product: Talaria. Publisher/project: MAJOR//MINOR. Backend: Hermes.
Canonical public IPA bundle identifier: `xyz.majorminor.talaria`.
Version `0.1.0`, build `1`; technical project/target/app folder remains Hermes.
The public Xcode project has no personal Team, profile or certificate.

## Install the published app

Users can [build/install directly with Xcode](docs/XCODE_INSTALL.md) using a free
Personal Team or paid Apple Developer Program Team, or import the published IPA
with [SideStore](docs/SIDESTORE_USER_GUIDE.md). SideStore is optional. Both paths
need Hermes plus the [Mac bridge and pairing setup](docs/INSTALL.md#mac-bridge-setup).
The canonical release ID stays `xyz.majorminor.talaria`; a self-builder can choose
a unique ID under their Team, and SideStore normally appends a Team-ID suffix.
Talaria's runtime Keychain service follows the actual installed bundle ID.

The commands below describe artifact preparation. This documentation update does
not rebuild, replace, retag or republish the existing v0.1.0 artifacts. Later
physical install/Refresh evidence and its limits are recorded in
[release readiness](docs/RELEASE_READINESS.md#current-installation-documentation-after-publication).

## Build unsigned artifacts without using a phone

The public identity differs from the historical development installation. Old
physical-PASS evidence does not validate this new identity. At the original packaging snapshot, the maintainer explicitly
authorized Simulator/build validation and excluded physical phone installation.

```sh
scripts/build-ios-release.sh --output-dir build/release/v0.1.0 \
  --sidestore-ipa --allow-unvalidated-ipa
```

This archives for `generic/platform=iOS` with signing disabled, generates a standard
unsigned `Payload/Hermes.app` IPA, packages the tracked bridge source/guides and
writes checksums. It never installs, migrates, signs or tests an app on a phone.
`BUILD_METADATA.json` records `physical_device_validation: NOT_PERFORMED`, canonical
identity/version and public source-input hashes. Build/debug paths are remapped.
Use a fresh output directory; existing archives are preserved.

A future physical-PASS route uses `--physical-validation-report PATH` instead of
`--allow-unvalidated-ipa`. It requires both `physical_device_validation: PASS` and
`validation_bundle_identifier: xyz.majorminor.talaria`. This prevents reusing the
legacy report as evidence for the new identity. Default packaging creates no IPA.

## Signing and SideStore

The IPA has no signature/entitlements blob or embedded provisioning profile.
Official SideStore supplies the user's own signing and normally appends their
Team ID. Keep its defaults; the source-derived new-user path requires no patch.
See [the user guide](docs/SIDESTORE_USER_GUIDE.md). The original packaging snapshot did not claim new-ID physical installation; later
suffixed validation is documented separately. Second-account signing/Refresh and
actual expiry recovery remain untested.

Direct Xcode device builds use your own Team and an identifier it can register;
see [the practical Xcode guide](docs/XCODE_INSTALL.md). Keep Team settings in ignored
local signing configuration and any project bundle-ID edit uncommitted. Copy `Config/Signing.example.xcconfig` to ignored
`Signing.local.xcconfig`; never commit the populated copy. Selecting a Team in Xcode
may write the project, so inspect changes before committing. The release script
clears Team/signing identity. No physical deployment is part of this preparation.

## Bridge source package

```sh
scripts/package-bridge.sh --output-dir build/release/v0.1.0
```

The normalized archive contains tracked bridge runtime, example configuration,
public guides/evidence/SideStore patch, dependency licenses, launchd templates and
install/update/status scripts. It excludes credentials, local signing, logs,
databases, tests, caches, virtual environments and builds. No live service is
restarted by packaging. The public LaunchAgents use the Talaria namespace; existing
private deployments are not modified or migrated by this source change.

## Verify and prepare attachments

```sh
python3 scripts/test_release_artifacts.py -v
python3 scripts/audit-release-artifacts.py \
  build/release/v0.1.0/Talaria-v0.1.0.ipa \
  build/release/v0.1.0/Talaria-v0.1.0.xcarchive \
  build/release/v0.1.0/hermes-mobile-bridge-v0.1.0.tar.gz
(cd build/release/v0.1.0 && shasum -a 256 -c SHA256SUMS.txt)
```

The final handoff adds a normalized archive ZIP for GitHub transport and regenerates
checksums for all attachments. Artifact hashes, test evidence and remaining actions
are recorded in [release readiness](docs/RELEASE_READINESS.md),
[public handoff](docs/PUBLIC_RELEASE_HANDOFF.md) and the local release receipt.
Keep unsigned packaging/build verification separate from physical signing validation.
Do not push, tag, create a remote repository, submit the SideStore draft or publish
until this exact snapshot and attachment set have been approved.
