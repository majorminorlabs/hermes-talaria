# Talaria vNext Phase 1 implementation

> Current release update: v0.2.1 supports in-app Hermes command approvals when
> Hermes advertises server-request approvals (4bb9e57 or newer). Older Hermes
> retains “Approve on your Mac.” Mac-only approval references below describe
> the earlier design or release.

Historical Phase 1 evidence. Current 0.2.0 source also includes the
[Live Activity extension](TALARIA_LIVE_ACTIVITY.md), unified headers, down-to-lock
voice gestures, held Ask send-on-release and SSE recovery fixes. See the
[current user guide](../USING_TALARIA.md); historical limitations below apply to
this original implementation revision.

The implementation follows [TALARIA_VNEXT_UX.md](TALARIA_VNEXT_UX.md), with the product decisions in the supplied Phase 1 brief: independent Agent threads, dedicated bridge-managed captures, deterministic Auto routing to Hermes, and iOS 18 support. This is unreleased development work; the public v0.1.0 IPA and physical iPhone installation are unchanged.

## Implemented boundary

- **Now / Threads / Agents** navigation, secondary Studio, shared destinations and `talaria://` routes. iOS 26 uses the native tab accessory; iOS 18 uses a bottom safe-area inset. The 26.1 `isEnabled` accessory API has a separate 26.0 availability branch.
- **Work and Needs You** projections, host-scoped seen/snooze state, unread/pin/archive/search/filter controls, Board entry, real clarification deadlines, confirmation before removal, Mac-only dangerous approvals, task review and routine interventions. Now limits grouped requests, Working, Done and Next Up rather than presenting host metrics as work.
- **Threads** retain streaming, steer, follow-up, artifacts and message history. Work status, collapsed steps, result footers, handoff markers and Steps/Details replace the separate Run Detail shell. Unknown outcomes remain distinct from lost connectivity; stale snapshots cannot flip a terminal run back to running.
- **Agents** retain the real configuration editor and expose independent Ask, current work, recent threads, model scope, local change history/Revert and real routine pause/resume. Revert checks the current server default before changing it. Session reasoning is shown only when reported; Agent reasoning remains a Mac handoff.
- **Ask** exposes deterministic name/alias routing and the destination before sending. Ambiguous aliases require a choice. Model/provider, reasoning and project overrides apply at creation. Sending returns to the prior screen with an Open toast. Offline Asks require explicit Send now; uncertain commands require receipt inspection and are never automatically replayed.
- **Voice** wraps the existing dictation engine with hold, slide-left cancellation, slide-down lock (updated after this report), a 60-second fuse, transcript review and optional 1.5-second automatic Ask sending. Capture and clarification answers require explicit confirmation. Global holds keep the native accessory in place and open the voice sheet after release, avoiding gesture cancellation during presentation. Voice sheets open at the large detent. The hold modifier uses native long-press/tap recognizers behind the SwiftUI content rather than the proposed sequenced SwiftUI gesture: the native accessory intermittently interpreted short taps as holds with the combined SwiftUI recognizers. The 250 ms threshold and lock/cancel semantics are unchanged. Drag deltas use the original finger-down position; actual touch timestamps distinguish a delayed short tap from a hold.
- **Capture** preserves text exactly, with separate kind/context/attachments, Photos/Files/camera entry points, voice audio and on-device recognition metadata. The private local file-backed queue survives relaunch and syncs captures automatically. “Saved to Hermes” requires an acknowledged stable capture ID. Plain links are stored without fetching.

## Bridge additions

**B1** adds `POST /bots/{id}/conversations` and lists/resolves those sessions with their mobile `bot_id`. It uses existing native-profile `session.create`/`session.list` APIs and leaves each Agent's canonical Bot Chat intact. Native Kanban assignees are mapped to mobile Agent IDs in reads and resolved back to the correct backend source on writes.

**B2** adds a dedicated `captures_root`, dated UTF-8 Markdown and JSON sidecars, authenticated audio/media uploads, stable IDs and replay-safe capture writes. Directories are 0700, files 0600; symlink/hardlink and owner checks protect the store. Files and directory entries are synchronized before confirming persistence. Text is limited to 200 KB, attachments to four at 10 MiB each, with a 256 MiB media quota per device. See the bridge README and BRIDGE_API.md for the contract. This uses neither Obsidian nor Kanban as the capture store. Hosts lacking B2 retain captures locally rather than claiming they were saved remotely.

The authenticated, read-only `GET /commands/{id}` receipt route lets Outbox distinguish confirmed, pending, rejected and not-received commands without replaying an uncertain Ask.

**B3–B5** remain limited to actual observable data: clarification recommendation/default/timeout metadata, delegate-tool handoff markers, and supported task review transitions/notes. A review send-back note uses the existing comment API before the status transition; those upstream operations are not atomic. The bridge command receipt preserves the uncertain outcome rather than blindly repeating both operations. No structured decision system or tracked delegation was invented.

## Verification

- Final Swift Testing: **77 tests / 13 suites passed**, with two explicitly gated checks skipped (production Studio HTTPS and isolated installed-Hermes integration, which had already passed in the enabled integration run). The temporary simulator pairing and Keychain credential cleanup passed. The earlier enabled production-client run passed against the isolated installed-Hermes stack, including streamed responses/history, steer/Stop, reconnect/replay, unknown outcomes after restart, independent Agent threads and stable Capture replay.
- Bridge pytest: **73 passed**, including installed-Hermes integration, independent Agent sessions, review notes/native assignment, capture ownership, filesystem durability, media uploads, quota isolation and interrupted-write replay.
- Production app UI: **1 end-to-end test passed**. Normal Ask and independent Agent Ask streamed responses; Capture received the bridge confirmation. The resulting Markdown was independently checked for exact leading spaces, Markdown characters, newline and trailing spaces.
- Fresh build from a new DerivedData directory: **BUILD SUCCEEDED**, retaining the iOS 18.0 deployment target.
- Native form regression checks passed for typed/pasted Agent text, typed/pasted Tailscale-style HTTPS URL, typed/pasted port and typed/pasted secure bridge token. Host form validation cancels without saving or pairing.
- Full simulator UI suite: **39 tests, 18 gated skips, zero failures** (21 practical tests passed). The skipped checks require a physical phone or the isolated production fixture, whose app end-to-end test passed separately. Light and accessibility-size screenshots were reviewed.
- A focused immediate-cancel test reproduced and fixed a deferred voice-start race. The final startup guard keeps cancelled sessions from starting the microphone or producing transcript text. **Five focused voice/dark-mode UI checks passed after this final guard**, and the corrected dark screenshots were reviewed.

Evidence is retained outside the repository in `/tmp/talaria-vnext-unit-final.log` (enabled integration), `/tmp/talaria-vnext-unit-verified.log` (final units and cleanup), `/tmp/talaria-vnext-bridge.log`, `/tmp/talaria-vnext-production-ui.log`, `/tmp/talaria-vnext-ui-verified.log`, `/tmp/talaria-vnext-ui-accessibility-final.log`, `/tmp/talaria-vnext-voice-dark-verified.log` and `/tmp/talaria-vnext-build-verified.log`; Xcode result bundles reside under `/tmp/talaria-vnext-build/Logs/Test/`. Temporary paths are local verification evidence, not permanent release artifacts.

The isolated integration harness uses the installed Hermes checkout at commit `4bb9e57bfde8a0affb5553eff13ed6e1f14147f1`, a temporary Hermes home, disposable profiles and a deterministic local model endpoint. The installed Hermes environment was missing its declared `snowballstemmer==3.1.1` dependency for tool search. Verification supplies the lockfile-hash-verified wheel from a private temporary directory via the harness’s `HERMES_TEST_DEPENDENCIES` option. Hermes source, its installed environment, the working mobile bridge, production bot definitions and production credentials are not changed.

## Deliberate deviations

- The native voice recognizers replace the proposed SwiftUI recognizer composition to fix observed tap/hold and scroll cancellation failures. This does not require a follow-up migration or upstream change.
- B2 is implemented, so an older host without B2 keeps captures in the private local queue. It does not silently convert them into actionable Kanban work. A compatibility Kanban fallback was not needed.
- Review note plus transition retains the upstream non-atomic contract. Removing that limit would require an upstream transactional operation; no extra recovery system was introduced in Phase 1.

## Remaining device checks and limits

- The reported earlier physical-phone typing problem was not reproduced in Simulator: native Agent and connection forms accept keyboard input and Paste. Confirm those fields with the physical phone keyboard as well.
- Actual microphone/Speech permissions, on-device recognition availability, audio quality, camera, Photos/Files permission flows, haptics and interruption/background behavior require a physical phone.
- Physical VoiceOver rotor operation, Smart Invert and real device Dynamic Type need a manual pass; simulator screenshots and automated accessibility assertions do not establish that these all work on hardware.
- The iOS 18 availability fallback compiles with the retained 18.0 deployment target. An iOS 18 runtime is unavailable on this Mac, so runtime validation remains pending.
- Physical Tailscale/LAN reconnect, installation, provisioning expiration and SideStore Refresh are outside this implementation run.
- Local notifications retain their existing app-alive limitation. There are no APNs, extension targets, Live Activities, widgets, App Intents, TTS, LLM routing, remote dangerous approvals, mid-thread model switching, Agent pause or Agent reasoning defaults.

No push, deployment, public release update or legacy-app removal is part of this work.
