# Talaria post-design regression validation

> Historical device evidence. Legacy development identifier: `com.dippo.hermes`.
> The public release now uses `xyz.majorminor.talaria`. These observations concern
> the existing legacy installation; they do not validate the new public identity.
> That physical installation is preserved untouched during public release preparation.

Scope: `c70d9ec` on `codex/bot-mode-milestone`, 2026-10-04. Preserve the
Talaria design, `com.dippo.hermes`, and existing bridge behavior. Research Terminal and credential configuration are unchanged. Physical checks
required bounded bot-request and cache/discovery fixes; the Hermes backend
architecture and native bot lifecycle remain unchanged.

## Accessibility table freeze

Reproduced with the original mock Researcher conversation (`c-researcher`),
its provider latency table, and
`UICTContentSizeCategoryAccessibilityL`. Opening the conversation stopped
responding to accessibility snapshots and navigation. The simulator app
used 99.1% CPU at 30 seconds and 100% at 40 seconds. A five-second process
sample repeatedly entered SwiftUI `GridLayout.Cache.setProposal` and
`GridLayout.Cache.sizeGenerally` through the main-thread layout chain.
The original horizontally scrolling Grid's column sizing was looping in
the transcript's lazy stack under accessibility text sizing.

`MarkdownTableView` now selects its layout using `dynamicTypeSize`:

- Standard sizes retain the original horizontally scrolling native Grid.
- Accessibility sizes render each row as vertically stacked heading/value
  pairs with unrestricted value wrapping and combined accessibility labels.
  This path does not use Grid or cross-column size measurement.
- Header-only tables retain their headings. Dynamic Type remains enabled.

The removed conversation/table step in `testLargeDynamicType` is restored.
It checks rendered provider fixture values, scrollability, and responsive back
navigation. A separate largest-size regression uses
`UICTContentSizeCategoryAccessibilityXXXL`; the normal-size test checks both
the native Grid and reachable live-run controls. None of these tests is
opt-in or skipped. The focused fixed accessibility regression passed in
27.228 seconds.

Local reproduction artifacts (outside Git):

- `<private-local-evidence>`
- `<private-local-evidence>`
- `<private-local-evidence>`
- `<private-local-evidence>`
- `<private-local-evidence>`
- `<private-local-evidence>`

## Other changes and checks

Screenshot review found the composer Stop icon could render in the accent
color. It now has the destructive role and explicit failure color.
Clarification Stop Run also has the destructive role. Stop/approval API
behavior is unchanged.

Regression coverage checks bridge-provided retry controls across completed,
running, failed, and cancelled states, and exercises Retry on a completed
mock run. Bot UI coverage creates, edits, duplicates, and hides the original
bot from its Management section without mistaking the surviving duplicate
for the hidden identity. Existing approval, denial, steering, attachment,
and simulated dictation interactions remain part of the complete suite.

The existing status pulse was also checked in a 12-second simulator Home
recording. Sampling the status-dot region at 10 fps showed short pulses
separated by approximately three seconds of identical static frames. App CPU
samples ranged from 0.3% to 8.3%; no sustained busy loop was observed.
The implementation sleeps between finite 1.1-second animations and disables
them under Reduce Motion. Artifacts: `<private-local-evidence>`,
`<private-local-evidence>`, and
`<private-local-evidence>`.

## Complete Swift suite

Final full-suite result: **69 passed, 21 opt-in skips, 0 failures**. The complete suite
ran on iPhone 17 Pro / iOS 26.5 with parallel testing disabled and bounded UI
execution time:

| Category | Passed | Opt-in skipped | Failed |
| --- | ---: | ---: | ---: |
| Swift unit/integration | 57 | 3 | 0 |
| XCTest UI | 12 | 18 | 0 |

The unit skips are `simulatorInstalledHermesStack`,
`removeIsolatedSimulatorPairing`, and `productionStudioHTTPS`, which need
explicit isolated-stack or private Studio fixtures. The UI skips are the
existing real-stack/Studio/Research Terminal/device opt-ins plus the new
physical Talaria table/skills/identity check. They require external fixtures
or an explicitly paired phone; none is an accessibility table regression.

The first
full light-mode run exposed two test-harness issues: the bot assertion also
matched its surviving duplicate, and the largest-size table assertion ran
before the lazy table was scrolled into view. Both assertions were fixed;
neither was removed or skipped.

Final complete-suite evidence: `<private-local-evidence>`,
`<private-local-evidence>`, and
`<private-local-evidence>`.
The restored accessibility test passed in 27.881 seconds, largest size in
41.303 seconds and normal Grid/live-run controls in 16.011 seconds.
After the bot-detail request/discovery adjustment, the affected bridge/store
integration tests and BotManagement UI were rerun: 31 unit/integration and
one UI pass, zero failures (`<private-local-evidence>`). These are
included in the distinct totals above, not counted again. The targeted bridge
Python suite passed 13 tests, including clone-budget/uncertain-outcome coverage.
No unrelated Research Terminal suite was rerun.

## Screenshot review

Light-mode artifacts: `<private-local-evidence>`. Final dark-mode artifacts:
`<private-local-evidence>`. Screenshots are also retained as XCTest attachments.
Reviewed stable Home light/dark, grouped tool history, active run with
reachable controls, failed run with Retry, normal Grid, accessibility stacked
table, bot detail/Management, Create/Edit, selected photo preview, and
simulated dictation. Dark-mode Stop and Deny remain red. No redesign was needed.
The attachment snapshot can catch the preparation spinner; the subsequent
dictation snapshot shows the selected flower thumbnail and removal control.

## Physical iPhone

The current signed app was built and installed over the existing app on the
connected iPhone 15 Pro Max / iOS 26.6.2, preserving app data. Xcode's installed
app inventory lists Talaria, version 1, bundle `com.dippo.hermes`.

The earlier XCTest automation gate was resolved by the user directly on the
phone. Subsequent acceptance tests use the actual signed production app and
existing Keychain pairing, without simulator fixtures or injected credentials.

Native dictation passed on the current build: Cancel restored the composer,
a second capture showed partial words and **Listening · on device**, Stop kept
the text editable, and the edited sentence received `SPRINT_PHONE_VOICE_OK`.
The persisted Hermes user message equals the captured composer text after the
normal leading/trailing whitespace trimming. Bridge upload rows stayed at
seven before/after this run: no microphone audio was uploaded.
Evidence: `<private-result-bundle>` under
`<private-local-evidence>`, exported to
`<private-local-evidence>`.

Physical testing exposed these bot-loading defects:

- Concurrent avatar warmup used full native detail reads. Five simultaneous
  reads took 43.5–46.5 seconds; the existing 30-second request limit expired.
  Warmup now loads these reads sequentially and keeps actual Desktop faces.
- Native profile cloning could outlast the ordinary RPC/request budget.
  Only `profiles.create` now has a 60-second RPC budget; mobile Create and
  Duplicate have a bounded 120-second response budget. Idempotency and
  uncertain-outcome handling are unchanged; no mutation is automatically retried.
- Incomplete roster summaries were treated as editor-ready and could omit SOUL.
  Missing editable-field metadata now remains unknown, the editor loads native
  detail before showing editable fields, and confirmed creation detail survives an unavailable follow-up read.
- A startup/transient offline snapshot could select legacy profile identities,
  and an older roster request could overwrite a newer result. Discovery now
  precedes namespace selection, known Bot Mode identities persist through an
  offline snapshot, and stale roster completions are ignored. Bot detail loading
  restarts when Bot Mode discovery becomes available. Editor loading restarts
  after connection discovery and ignores cancelled reads, preserving user edits. Its read-only response
  budget is 90 seconds because it includes native metadata/avatar reads.

Files selection, native preview, attachment send, exact marker retrieval and
background/foreground reconciliation passed. A single assistant response returned
with `PHONE_FILE_MARKER_9017`; no duplicate attachment/message was observed.
Evidence: `<private-local-evidence>`.
Normal Grid and accessibility stacked tables rendered on the actual iPhone;
back navigation remained responsive. Show All/Show Fewer exposed the native
Research Orchestrator skills including `research-terminal`. The initial combined
case failed only while locating an icon on another Springboard page; the icon
navigation now scrolls before asserting an offscreen icon.
Evidence: `<private-local-evidence>`.

A disposable native bot was created from the phone using the inherited safe
`gpt-5.6-luna` / `openai-codex` model, a description and a short SOUL. Native
creation and the phone's confirmed dismissal were observed. The icon and display name were physically verified on Springboard after
scrolling to the App Library, and Tailscale showed Connected. Evidence:
`<private-local-evidence>`.
Edit, background/foreground, writable canonical chat and relaunch-history checks
passed together on the latest build in 105.808 seconds. The loaded editor
preserved the original SOUL and appended the requested change; save dismissed
after confirmed persistence. Native profile files independently contain both
phone edits. Evidence:
`<private-local-evidence>`.
The final editor-readiness change also passed BotManagement UI again
(`<private-local-evidence>`). Hide passed from the new Management section, including its history-preservation
confirmation and removal from the live roster (32.344 seconds). A native
message-content digest before/after Hide was identical: all ten messages remain.
The three disposable native bots from this pass are hidden; no chat was deleted.
Evidence: `<private-local-evidence>`.
The owned iCloud fixture was removed. Its one consumed upload follows the existing
seven-day staging cleanup policy; native attachment/history retention is unchanged.
Known mobile/backend credential values had no matches in changed deliverables or
scoped acceptance logs. No credentials, test media or signing material were staged. Earlier camera, Photo Library and PostgreSQL-search
passes remain documented in BOT_MODE_VALIDATION.md; they are not claimed as
new post-design tests.

The physical Wi-Fi path uses the private Tailscale HTTPS hostname on port 443.
The actual phone Tailscale connection and normal chat were exercised after a
managed bridge/backend restart. Cellular was not repeated. Funnel remains off.

Run individual physical methods, with Hide last; running the entire class in
alphabetical order hides its shared disposable bot before later checks.
Pairing stays in Keychain. Fixtures, screenshots, result bundles and recordings
remain outside Git.

## Signing and release gate

Only non-secret source, fixture, test, and documentation changes belong in
this milestone. Two pre-existing machine-local files remain intentionally
uncommitted: `Hermes.xcodeproj/project.pbxproj` (personal DEVELOPMENT_TEAM and
Xcode serialization changes) and
`Hermes.xcodeproj/xcshareddata/xcschemes/Hermes.xcscheme` (UI-test target
parallelizable setting). Do not discard them or commit signing material.

The complete non-opt-in suite and affected follow-up checks pass. All requested
post-design physical components have been exercised successfully, including the
icon check repeated separately after its Springboard-page harness correction.
Talaria is ready for `v0.1.0` release cleanup. This does not publish, tag or package
a release. A general Opus UI-polish pass is not needed for this acceptance gate.
