# Talaria v0.1.0 public release readiness

Prepared 2026-10-05 from the separate sanitized public repository. Product Talaria;
publisher MAJOR//MINOR; backend Hermes. Canonical unsigned IPA bundle ID
`xyz.majorminor.talaria`, version 0.1.0/build 1. At that preparation snapshot, nothing had been pushed,
tagged or published; see the later documentation status below.

## Current installation documentation (after publication)

Talaria supports two routes: [Xcode with your own Apple Developer Team](XCODE_INSTALL.md)
and [official SideStore](SIDESTORE_USER_GUIDE.md). A free Personal Team can use
Xcode; paid membership is optional for personal-device testing. Both routes use
the shared [Mac bridge and pairing setup](INSTALL.md#mac-bridge-setup).
Self-builders may change the bundle ID to a unique identifier under their own
Team. The Keychain service follows the actual runtime ID; different IDs create
separate app/container/preferences/Keychain identities.

Later physical validation on 2026-10-05 installed the published IPA under its
normal Team-suffixed public identity on one Apple Account. Pairing, bot inventory,
streamed normal/bot chat, existing history, Home, Tasks, Settings, Photos/Files,
force quit/relaunch, and ordinary Refresh with a matching renewed profile passed.
It used an existing SideStore build carrying the legacy same-Team fix, so it does
not establish a stock-build or second-account physical result. Refresh All was
skipped in that session to preserve a separate rollback install. Detailed evidence
boundaries are in the [SideStore guide](SIDESTORE_USER_GUIDE.md#identity-and-evidence).
Direct Xcode installation was previously exercised with the development identity;
a new self-builder Team/ID and paid-Team provisioning were not physically retested
for this documentation update.

The published v0.1.0 IPA, checksums, tag and release remain unchanged. The original
`BUILD_METADATA.json` still reports physical validation as NOT_PERFORMED **at
packaging time**. Later suffixed validation does not replace that metadata or
satisfy the packaging script's exact canonical-ID report gate automatically.
The preparation record below retains its original evidence and publication limits.

## Original release-preparation record

## Identity and validation boundary

The public ID is an intentional permanent release decision. The original private
history was not merged. Changes are confined to the public checkout; the private
development repository and valuable legacy physical installation remain untouched.
No phone inventory, signing, deployment, migration or install command was used.

Legacy development identifier: `com.dippo.hermes`. Historical functional acceptance
and SideStore same-Team update/refresh evidence concern that existing installation.
They do **not** establish physical signing or installation of the new public ID.
The historical [physical report](../PHYSICAL_DEVICE_TEST_REPORT.md) is labeled legacy
and cannot authorize new-ID packaging as physically validated.

## Source and signing audit

All app/test product IDs now use the public namespace; the Xcode project generates
Info.plist, version 0.1.0/build 1 and Talaria display name. No custom entitlements,
app groups, explicit Keychain access group, associated domains, iCloud, push or
extensions are configured. Personal Team/signing material remains excluded.
Public LaunchAgent template names/labels use `xyz.majorminor.talaria-mobile-*`.
No installed service was changed by those source edits.

`KeychainBridgeCredentialStore` defaults to `Bundle.main.bundleIdentifier`, with
public-ID fallback only. Queries set generic-password class, service and host-ID
account; no explicit access-group override. Signing determines the default group.
Tokens remain `AfterFirstUnlockThisDeviceOnly`. New tests verify the runtime default
and service isolation; they do not assert cross-Team or legacy/public migration.

## Artifacts and checks

Fresh output is in ignored `build/release/v0.1.0/`:

| Artifact | Verification |
| --- | --- |
| `Talaria-v0.1.0.xcarchive` | New unsigned generic-iOS Release compile/archive, public ID |
| `Talaria-v0.1.0.ipa` | New public-ID Payload, matching archive bytes, no profile/signature |
| `Talaria-v0.1.0.xcarchive.zip` | Normalized GitHub transport, matching archive bytes |
| `hermes-mobile-bridge-v0.1.0.tar.gz` | New public service namespaces, coherent guides/patch, normalized metadata |
| `SHA256SUMS.txt` | Final attachment hashes verified |
| `BUILD_METADATA.json` | Public source-input hashes; physical validation explicitly NOT_PERFORMED |

Run the commands in [release packaging](../RELEASE.md). Full current verification
results and exact hashes are in [the handoff](PUBLIC_RELEASE_HANDOFF.md) and local
release receipt. Build/test logs and raw xcresults remain ignored because they
contain host paths and Simulator IDs. Public summary files omit those values.

## SideStore new users versus legacy

Official SideStore's default Team-ID suffix is the source-derived expected public
install and Refresh path. It does not need the legacy same-Team unsuffixed patch.
The [user guide](SIDESTORE_USER_GUIDE.md) gives install → signing defaults → Tailscale
→ bridge pairing → chat → Refresh → weekly procedure. It never asks new users to
force the maintainer's exact signed identity or Personal Team.

Historical legacy evidence includes update-in-place/data and Keychain retention,
two normal Refreshes and Refresh All with the minimal SideStore patch. Preserve
that [investigation](SIDESTORE_INDEPENDENT_INVESTIGATION.md), [patch](sidestore/0001-restore-preferred-bundle-id-team-rule.patch)
and [upstream draft](sidestore/UPSTREAM_PR.md). No upstream submission, fork or patched
SideStore IPA is included in Talaria's release.

New-ID physical install, second-account portal registration/Refresh, actual expiry,
reboot/cellular/background refresh and legacy-to-public migration are not verified.
These are disclosed prerelease limits; installing on the owner's phone is explicitly
excluded. Source/build validation is not described as physical acceptance.

## Publication

Use only the finalized sanitized public root and artifact set identified by the
handoff/receipt. The existing private development repo remains unsafe to publish.
Choose the MAJOR//MINOR GitHub account/org, approve neutral attribution and the
prerelease, then explicitly authorize publication. No external mutation is performed
by this preparation. MIT and dependency notices remain included.
