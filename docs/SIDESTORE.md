# Install Talaria with SideStore

Talaria is MAJOR//MINOR's iPhone companion for Hermes. The public unsigned IPA
contains `xyz.majorminor.talaria` (0.1.0/build 1). SideStore supplies your own
Personal Team signing and normally appends your Team ID when installing it.

Use **official SideStore**, leave **Customize AppID off** (or **Append Team ID on**
if the customization dialog appears), and import the release IPA. Then reconnect
Tailscale, pair with your own Hermes bridge and verify chat and Refresh.
Follow the [SideStore user guide](SIDESTORE_USER_GUIDE.md) for the complete sequence.
Normal weekly maintenance is LocalDevVPN → Refresh All → Tailscale → Talaria.

This new-user behavior is verified from pinned official source, not a physical
second-account installation. No patch is required by that source-derived suffixed
path. The maintainer's existing phone was not used for the new public identity.

## Advanced legacy/exact-ID case

Legacy development identifier: `com.dippo.hermes`. The existing installation at
that identity remains untouched. Same-team **unsuffixed** installs encounter the
SideStore profile-selection regression; the [minimal patch](sidestore/0001-restore-preferred-bundle-id-team-rule.patch)
and manual re-import workaround apply to that case. Historical physical evidence
records two Refreshes plus Refresh All with preserved data and Keychain.

See the [independent investigation](SIDESTORE_INDEPENDENT_INVESTIGATION.md),
[historical validation](SIDESTORE_VALIDATION.md) and [upstream draft](sidestore/UPSTREAM_PR.md).
The patch/draft are retained for later contribution; no upstream submission,
SideStore fork or patched SideStore binary is part of this release.

## Packaging (maintainers)

The release is unsigned and deliberately has no new-ID physical validation:

```sh
scripts/build-ios-release.sh --output-dir build/release/v0.1.0 \
  --sidestore-ipa --allow-unvalidated-ipa
```

The explicit option packages only; it never installs on a phone and records
`physical_device_validation: NOT_PERFORMED` in `BUILD_METADATA.json`.
A physical-PASS path instead requires a report explicitly covering the canonical
public identifier. The legacy report cannot satisfy that gate.
