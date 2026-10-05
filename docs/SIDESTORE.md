# Install Talaria with SideStore

Talaria is MAJOR//MINOR's iPhone companion for Hermes. The public unsigned IPA
contains `xyz.majorminor.talaria` (0.1.0/build 1). SideStore supplies your own
Personal Team signing and normally appends your Team ID when installing it.

This is the alternative to [Xcode installation](XCODE_INSTALL.md); SideStore is
not required if you build/install with your own Apple Developer Team. Paid
membership is not required for the free-account SideStore route.

Use **official SideStore**, leave **Customize AppID off** (or **Append Team ID on**
if the customization dialog appears), and import the release IPA. The installed
ID may be `xyz.majorminor.talaria.<YOUR TEAM ID>`; that is expected.

**LocalDevVPN is for SideStore installation/refresh. Tailscale is for Talaria ↔
Hermes bridge connectivity.** Turn Tailscale off, enable LocalDevVPN on Wi-Fi,
install/refresh, then disable LocalDevVPN and restore Tailscale before Talaria use.
Weekly maintenance is **SideStore → My Apps → Refresh All**, followed by checking
the refreshed signing period and a fresh Talaria chat. Free signing expires after
seven days; SideStore consumes one of three free-profile installed-app slots.

Follow the [SideStore user guide](SIDESTORE_USER_GUIDE.md) for the complete import,
bridge pairing, validation, capacity and refresh procedure. It also distinguishes
physical public-ID validation on one account with an existing patched build from
source-derived official behavior and untested stock-build/second-account cases.

## Advanced legacy/exact-ID case

Legacy development identifier: `com.dippo.hermes`. The existing installation at
that identity is separate from the public release. Same-team **unsuffixed** installs encounter the
SideStore profile-selection regression; the [minimal patch](sidestore/0001-restore-preferred-bundle-id-team-rule.patch)
and manual re-import workaround apply to that case. Historical physical evidence
records two Refreshes plus Refresh All with preserved data and Keychain.

See the [independent investigation](SIDESTORE_INDEPENDENT_INVESTIGATION.md),
[historical validation](SIDESTORE_VALIDATION.md) and [upstream draft](sidestore/UPSTREAM_PR.md).
The patch/draft are retained for later contribution; no upstream submission,
SideStore fork or patched SideStore binary is part of this release.

## Packaging (maintainers)

The published artifacts remain unsigned. The original release was packaged
without public-ID physical validation using:

```sh
scripts/build-ios-release.sh --output-dir build/release/v0.1.0 \
  --sidestore-ipa --allow-unvalidated-ipa
```

The explicit option packages only; it never installs on a phone and records
`physical_device_validation: NOT_PERFORMED` in `BUILD_METADATA.json`.
A packaging physical-PASS path requires a report explicitly covering the canonical
public identifier. Later suffixed phone validation does not rewrite the original
metadata or automatically satisfy that exact-ID packaging gate. The legacy report
cannot satisfy it either; see [release readiness](RELEASE_READINESS.md).
