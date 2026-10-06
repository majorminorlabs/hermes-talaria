> The source-update preparation below is historical. Current 0.2.0 binary release
> acceptance and remaining limits are in [physical acceptance](PHYSICAL_ACCEPTANCE_v0.2.0.md).

# Talaria 0.2.0 source update readiness

Prepared 2026-10-06 against public main `d24c1b4` and the existing v0.1.0 prerelease.
App/extension: **0.2.0 / build 2**. Bridge: **0.2.0**. Public app identity remains
`xyz.majorminor.talaria`, extension `.LiveActivity`. This is a source/documentation
update; the old tag, release and downloads remain unchanged. No new IPA is published.

## Exact implementation delta

Nine development implementation commits after the release-preparation baseline
were transferred as separate commits onto existing public history, with neutral
attribution and private Live Activity evidence identifiers removed before committing.
Original private development history is retained locally and is not pushed.
Runtime/test source matches development HEAD except public identity adaptation,
versioning and the three UI automation corrections described below.

- B1 independent Agent sessions; B2 durable device-owned Capture/media; command receipts.
- Now / Threads / Agents, global deterministic Ask, Needs You, work/results/steps,
  search/unread/pin/archive and Agent/source filters; secondary Studio/Board/Scheduled.
- Durable local Capture with automatic sync; explicit-send Ask Outbox and receipt
  checks for uncertainty. Voice Capture includes reviewed text and audio.
- Agent operational/model controls with guarded default Revert and actual routine
  interventions; model/reasoning/project settings retain session scope.
- One aggregate Live Activity/shared extension package, excluding terminal/uncertain
  runs; stale observations remain distinct from completion. No APNs delivery.
- SSE health-probe resilience and expired-replay-cursor recovery, unified headers,
  down-to-lock voice Ask with release sending, removal of duplicated work status.

Phase 2 structured decisions/delegation, Agent pause/reasoning defaults, mid-thread
model changes and TTS are not implemented. The design spec is a roadmap, not a
feature inventory. See [changelog](../CHANGELOG.md) and [user guide](USING_TALARIA.md).

## Validation in this preparation

| Check | Result |
| --- | --- |
| Bridge pytest | 72 passed, 1 installed-Hermes opt-in skip |
| Swift Testing | 90 passed, 3 explicit opt-in skips (93 discovered) |
| Simulator UI | 22 practical tests passed, 18 physical/integration opt-in skips |
| Service/deployment safety | 9 passed |
| Release packaging/privacy regressions | 8 passed |
| Python compile/static syntax and shell syntax | Passed |
| Fresh unsigned device Release archive | Passed, embedded extension included |
| App/extension identity, version/build and absent signing payload | Passed |
| Artifact privacy/signing scan | No findings |
| Internal Markdown file links | 149 file/anchor links checked, none missing |
| Public source/history privacy scan | No actionable findings |
| Gitleaks 8.30.1 | One reviewed synthetic credential fixture, no real secret finding |

The full simulator run initially exposed three UI automation failures: the old
Studio-header selector, a direct tap on a collapsed Now tab and Apply behind the
model picker's bottom search accessory despite XCTest reporting it hittable. The
selector/navigation/visibility handling was corrected, with original assertions
retained. Host form and screen tour passed their focused rerun; model change,
confirmation and Revert passed after the visibility correction. Product runtime
was not changed to accommodate tests. Counts above are distinct tests, not added
rerun totals. A parameterized Swift test generates an additional execution.

The system Python was too old for the tar extraction test; the supported Python
3.11 environment passed. No test was weakened or removed. Installed-Hermes/live
production tests were not newly enabled; historical opt-in evidence is in the
[Phase 1 implementation report](design/TALARIA_VNEXT_PHASE1_IMPLEMENTATION.md).

## Security, privacy and media

Every transferred commit and the final public tree were reviewed. The personal
signing suffix and device name in unpublished Live Activity notes were replaced
before transfer. Private development author metadata and older Git objects were
not imported. No public history was rewritten and no actual published secret was
found. Gitleaks' fixture is a deterministic security-negative-test literal; ignored
BUILD_METADATA hashes are hashes rather than credentials.

Capture storage defaults outside Git, in the private service state and iPhone
Application Support. Ignore rules additionally cover Capture/upload/Outbox/cache
stores, databases, signing and scratch files. No real captures, audio, host configs,
logs, credentials, device identifiers or signed artifacts enter the public index.
See [privacy/security](PRIVACY_SECURITY.md). Arbitrary custom capture roots must
also remain outside the checkout.

Fresh Now and Agents screenshots use only synthetic simulator fixtures. Visual and
PNG metadata/privacy review found no private values. Earlier v0.1.0 images remain as
historical assets, without a current-interface claim. The website social card now
labels 0.2.0 source. Public browser-served site assets passed private-path, tailnet,
identifier and configured-credential comparisons.

## Current installation documentation after publication

Both Xcode and SideStore remain documented. Xcode installs current source; the
available SideStore IPA is still v0.1.0. Set TALARIA_APP_BUNDLE_ID locally for a
unique self-build identity; the extension derives its suffix and needs the same
Team. Keep the installed ID and Team stable for updates. The IPA physical gate now
requires both the public bundle ID and the exact version, so old acceptance cannot
certify a new build. Free signing still requires periodic renewal.

Historical phone acceptance and SideStore refresh evidence apply to their named
builds, not 0.2.0. Stock SideStore and second-account signing remain physically
unverified. Current physical microphone/recognition/audio, camera/picker permissions,
input, accessibility, Wi-Fi/cellular reconnect, Live Activity presentations/background,
installation/data retention and refresh checks remain pending. iOS 18 runtime is
unavailable locally; its deployment target compiles but runtime behavior is unverified.

No APNs/background-monitoring guarantee. The Mac must be awake, logged in and
reachable. Capability-gating and the non-atomic review-note/transition contract remain.
Formal 0.2.0 Release/IPA publication should follow current physical acceptance and a
separate owner decision; it is intentionally outside this source push.
