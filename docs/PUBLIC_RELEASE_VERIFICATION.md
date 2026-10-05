# Talaria public-identity verification

Verified 2026-10-05. Product Talaria; publisher MAJOR//MINOR; backend Hermes.
Canonical unsigned IPA bundle ID `xyz.majorminor.talaria`, version 0.1.0/build 1.
**Ready for approval to publish an explicitly limited prerelease. No push, tag,
remote repository, release, SideStore submission or phone deployment occurred.**

## Current tests and builds

| Check | Final result |
| --- | --- |
| Swift unit/integration | 60 passed, 3 explicit live opt-in skips, zero final failures |
| Swift UI | 12 passed, 18 explicit live/physical opt-in skips, zero failures |
| Bridge | 59 passed, 1 installed-Hermes opt-in skip |
| Service/deployment safety | 9 passed; tests only, no live service changes |
| Packaging/privacy | 7 passed, including identity-specific physical-report gate and documentation closure |
| Distinct current tests | **147 passed, 22 explicit skips, zero unresolved failures** |
| Simulator Debug | Built/ran new public identity; successful final unit suite |
| Generic device Release compile/archive | ARCHIVE SUCCEEDED, unsigned; no device selected/installed |
| IPA identity/version | Public bundle ID, 0.1.0/build 1; Payload layout valid |
| IPA/archive app parity | All 6 app payload files byte-identical |
| Archive ZIP parity | All 10 archived files represented with normalized transport metadata |
| App build-input parity | 103 relative-path input SHA-256 values match current source |
| dSYM | Generated, executable/dSYM UUID match |
| Extracted bridge install/CLI | Fresh isolated venv install and CLI/help passed |
| Packaging | Byte-reproducible bridge tar, relocated README and all local guide links pass |
| Privacy | Final complete public-history/tracked/attachment scan passes with no private findings |
| Physical new-ID install/signing | **NOT PERFORMED — explicitly excluded** |

The first complete Simulator run used signing disabled and returned three Keychain
errors, including the pre-existing round-trip test. Its UI suite nevertheless passed
all 12 non-opt-in cases. The final unit/integration rerun used Xcode's local ad-hoc
Simulator signing and passed all 60 cases, including those three. No personal Team,
certificate, provisioning profile or product workaround was used. Final totals use
the passing unit rerun and passing UI cases without double-counting overlap.
The initial failed result is retained as local evidence, not hidden or called PASS.

Xcode emitted one AppIntents metadata warning (no AppIntents dependency), plus 18
dSYM module-cache warnings for privacy-remapped `.pcm` paths. The executable/archive
and dSYM were produced and their UUIDs match; no Swift compiler errors/warnings were
reported. Those module-cache warnings limit auxiliary SDK debug-module availability;
they do not change signing, packaged app behavior or source/UUID parity.

## Keychain, signing and source parity

Keychain service uses the running bundle ID, falling back to the canonical public
ID only if unavailable. No explicit Keychain access group, application identifier
or Team is hard-coded. Simulator tests verify runtime lookup and service separation,
not Apple portal signing or cross-Team access-group migration.

Generated Info.plist and project/app/test IDs use the public namespace. No custom
entitlement file, app group, extension, iCloud/push/associated domain or populated
personal Team setting is configured. `codesign` confirms the released device binary
is not signed at all; archive Team/signing identity are empty. No profiles,
certificates or signature directories occur in the IPA/archive/source.

The reviewed SideStore patch and upstream draft are byte-identical to the prior
sanitized snapshot. Guides retain Opus's source/physical distinction while using
the new base for public installation. Source/product changes are limited to public
app/test identity, the Keychain fallback, public service labels/templates and the
packaging validation boundary. No Talaria redesign was performed.

## Source-derived SideStore result

Pinned official SideStore `6032424a` defaults Append Team ID to true and customization
off; the first install constructs the public base plus the user's Team ID. The saved
resigned ID then contains that Team ID, so the same-Team Refresh rule reuses it.
The default public path requires no patch by source analysis. The same-Team unsuffixed
case still hits the separately documented legacy regression.

This is not a physical second-account result. New public-ID install/signing/Refresh,
expiry/reboot/cellular/background refresh and legacy migration remain untested.
The owner's legacy phone installation was untouched: no inventory, install,
migration, delete, re-sign or other physical-device operation was performed.
Private development HEAD remains `c198f24efd56a25d718ea816e4f1f988ff5c0842` and its
tracked checkout is clean. The existing private bridge/services were not changed.

## Privacy and legacy inventory

All available objects in the finalized one-root public Git database, author/message
metadata, filenames/content, patch, fixtures, six PNGs including their metadata,
IPA/archive/dSYMs, archive ZIP, bridge tar and checksums are included in the final scan.
Known private signing Team and six credential values are compared in memory without
printing or writing matched values. No private signing/account/email/device/host/IP,
backup path, certificate/profile or known credential finding remains.

Reviewed broad matches are neutral public/patch attribution, synthetic negative-test
paths/hosts/credentials and scanner regexes. Public service namespaces are now Talaria's
reverse-domain namespace. The old identifier remains in **81 occurrences across nine
explicitly historical/advanced documents**, individually enumerated in
[the legacy inventory](LEGACY_IDENTIFIER_AUDIT.md); no runtime/project/test/script
literal remains. Historical traces are retained, not relabeled as new-ID validation.
Pattern/known-value scanning does not prove the absence of an unknown-format secret.

Artifact hashes, exact finalized root/tree, raw-result locations and input/ZIP manifests
are recorded in ignored local receipt/audit output. Build metadata explicitly records
physical validation as NOT_PERFORMED. Public readiness means readiness to publish the
disclosed unsigned prerelease, not proof of a physical new-user signing workflow.

See [the handoff](PUBLIC_RELEASE_HANDOFF.md) for the exact proposed publication and
owner decisions. No publication authorization is inferred from completion of tests.
