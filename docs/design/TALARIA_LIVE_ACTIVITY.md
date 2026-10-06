# Hermes aggregate Live Activity

One ActivityKit activity projects the current host's observed runs. The shared local Swift package `TalariaActivityShared` owns the Codable attributes, derivations and static fixtures; the app and `TalariaLiveActivity` widget extension import the same module. The deployment target remains iOS 18.

The ring excludes completed runs and prioritizes blocked over needs input over running. Expanded and Lock Screen views show up to three active rows, prioritizing requests for input/blockers. Totals are displayed only when known; ordinary local runs without a known total show their state. Production data updates while Talaria is running; no APNs registration, push tokens, remote background delivery or actions are included. Production snapshots carry a 60-second stale date. Disconnects do not pretend that the work finished.

## Filming

In Xcode's Hermes scheme, add launch arguments `-TalariaDemo YES`. Launch once, then go Home. The gated **Run Live Activity demo** button starts another sequence after the previous one finishes. This flag isolates the activity from real run projections; it does not change bots, conversations or the bridge.

Frames are scheduled from a monotonic start at 0, 3, 7, 12, 16 and 19 seconds. The finite UIKit background assertion is released at 27 seconds (or on expiration/cancellation). Prior Talaria activities are dismissed before the demo starts, so reruns do not accumulate activities. The demo's needs-input thread ID is a fixture, not a real bridge conversation; a complete demo conversation environment is intentionally outside this task.

The final frame ends the activity with a green check and **All done**, using `.after(now + 8 seconds)`. ActivityKit controls the actual rendering/dismissal timing. This policy retains the final Lock Screen presentation; an ended activity may leave the Dynamic Island immediately. It cannot guarantee eight seconds of completed Island presentation. See [Apple's dismissal contract](https://developer.apple.com/documentation/activitykit/activity/end(_:dismissalpolicy:)).

**Open** uses `talaria://threads`; needs-input rows use `talaria://thread/<conversationID>`. The app now registers the existing URL scheme and supports the Threads index route. There are no approve or Stop actions.

For the previously approved installed phone identity, use a build-only `TALARIA_APP_BUNDLE_ID=com.example.talaria` override. The extension derives `<app ID>.LiveActivity` from the same setting. Personal Team values remain in ignored local signing configuration. Do not globally override `PRODUCT_BUNDLE_IDENTIFIER`, since that would assign the same identifier to both targets.

## Verification — October 6, 2026

- Simulator build passed; signed physical-device Debug build passed, including the embedded widget extension. Deep signature verification passed.
- Three focused tests passed: priority/completed-run exclusion, exact fixture sequence and Codable round-trip, and Threads URL routing.
- Two consecutive demo-button runs in the same Simulator process completed all six frames. Recorded counts were 1, 2, 3, 3, 2, 0; frames after going Home continued in the background through the final update.
- At the largest standard Dynamic Type size, compact running/needs-input presentations and all three Lock Screen rows were visually inspected without truncation. Tapping the activity opened Threads. Expanded/minimal configurations compile and have static SwiftUI previews, but their visual acceptance remains pending.
- Static widget previews cover running, needsInput, blocked and done for compact, minimal, expanded and Lock Screen, plus all six Lock Screen demo frames and a largest-standard-size card preview.
- Logs: `/tmp/talaria-live-activity-tests.log`, `/tmp/talaria-live-activity-final-build.log`, `/tmp/talaria-live-activity-phone-final-build.log`, `/tmp/talaria-live-activity-demo.log`. Simulator images are in `/tmp/talaria-live-activity-screens`.

**Physical acceptance is blocked, not passed.** The install connection closed with CoreDevice error 3002 / IXRemoteErrorDomain 6, “Connection interrupted”. A retry returned CoreDevice error 1011, unable to locate the device. The test iPhone subsequently showed unavailable in Xcode tooling; iPhone Mirroring reported “iPhone Not Found”. The phone must return within reach and reconnect before installation, two physical background runs, and all four physical presentations can be verified. No uninstall, public release modification or push was performed.
