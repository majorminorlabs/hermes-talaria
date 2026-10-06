# Talaria 0.2.0 physical acceptance

physical_device_validation: PASS
validation_bundle_identifier: xyz.majorminor.talaria
validation_version: 0.2.0
validation_build: 2

Accepted 2026-10-06 on a physical iPhone running iOS 26.6.2. The identifier above
is the canonical release identity; the device used its existing Team-suffixed
installed identity and existing signing configuration. The exact installed/signing
identifiers are retained only in private local evidence. Xcode built public runtime
source `417999dcc056b3afa33a37d56a0f17ce9b521a47`; final release changes add only
acceptance/install/release documentation. No product fixes were required.

## Device results

| Check | Result |
| --- | --- |
| In-place Xcode upgrade to 0.2.0/build 2 | PASS; device inventory verified version/build, no uninstall |
| Existing history, host and pairing retained | PASS; reconnected to the real Hermes stack |
| Keyboard/input | PASS; mirrored Ask/Capture/Agent editing worked, owner confirmed physical typing and paste |
| Now / Threads / Agents | PASS; real inventory, Working, completed history and routing |
| Two independent threads for one Agent | PASS; distinct Alpha/Beta sessions reopened separately with correct histories |
| Global and targeted Ask | PASS; real responses and streaming/progress |
| Voice Ask and camera Capture | PASS; owner confirmed the physical checklist; macOS blocks microphone access through Mirroring |
| Durable text Capture | PASS; bridge Markdown persisted, no Ask started |
| Offline Capture / explicit Ask Outbox | PASS; Capture synced after recovery, Ask remained unsent across reconnect/relaunch |
| Needs You | PASS representative physical fixtures; clarification answer, expired informational state and Later with explicit no-notification wording |
| Unsafe tool approval guard | PASS automated representative test; dangerous approvals remain Mac-only |
| Model-default change and Revert | PASS; original default independently verified restored on the bridge |
| Steering / Stop | PASS real timed work; steering retained, Stopping/current-step state followed by Stopped/incomplete outcome |
| Connection recovery | PASS; only mobile bridge interrupted/restored, last-known/offline state truthful |
| Aggregate Live Activity | PASS physical synthetic fixture; Dynamic Island Needs you state and cleanup observed |
| Accessibility/device sanity | Larger Dynamic Type and portrait controls PASS; primary accessibility labels checked in source/tests, physical VoiceOver session not certified |

The physical camera/voice/keyboard checks requiring interaction outside Mirroring
were confirmed by the owner. No private screenshots, host values, pairing tokens,
conversations, capture contents or signing identifiers are part of this report.

## Release validation

- Bridge: 72 passed, 1 installed-Hermes opt-in skip.
- Swift: 90 passed, 3 opt-in skips (93 discovered).
- UI: 22 distinct tests with passing evidence, 18 physical/integration opt-in skips.
  The full run initially had one Ask-to-Capture screenshot-tour failure; the
  unchanged focused rerun passed. The first failure remains in local evidence.
- Service safety: 9 passed. Packaging/privacy regressions: 8 passed.
- Fresh signed physical device build and unsigned device Release archive passed.
- Embedded extension identity/version/build parity and absence of public signing
  payload passed. Artifact audit inspected 105 payload files with zero findings.
- Packaged bridge installed in a clean virtual environment and CLI help passed.

## Nonblocking limits

Only iOS 26.5 Simulator is installed; iOS 18 deployment compiles, runtime unverified.
No APNs or guaranteed background Live Activity delivery; the physical fixture is
not proof of indefinite production background monitoring. Stock SideStore/new-account
signing, actual expiry/recovery and previously documented refresh cases were not
retested. No Phase 2 functionality is claimed. See [release notes](RELEASE_NOTES_v0.2.0.md).
