# iOS ↔ Studio bridge integration validation

Validated on 2026-10-02, Xcode 26, iPhone 17 Pro Simulator / iOS 26.5. The installed Hermes checkout is `2a4c9afd7bd7b56d3e1f95524ca8956092f2904c`. UI milestone `df387cf04d23340ce708af9b9f290fc1138b45d5` remains in history. The previously untracked bridge/audit/contracts were inspected and committed separately as `8923efb`; virtualenvs, Python caches, build output and private fixture state are excluded.

## Automated results

Functional total: **69 passed** (36 Swift unit tests, 5 existing UI tests, 1 hosted local-stack workflow, 1 production UI smoke, 26 Python bridge tests). Simulator pairing cleanup also passed: **70 checks including housekeeping**. UI totals combine the full-suite run and the successful targeted screenshot-timeout rerun; the flaky aggregate run itself was not green. All simulator builds/tests use ad-hoc signing (`CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`) so real Keychain access is exercised.

| Suite | Result |
|---|---|
| Original Swift unit tests | Passed, 15 tests |
| Bridge-focused Swift unit tests | Passed, 21 tests |
| Original Swift UI tests | Passed, 5 tests across final full/targeted runs |
| Production local-stack hosted test | Passed, 1 test |
| Production local-stack UI smoke | Passed, 1 test |
| Simulator pairing cleanup | Passed, 1 housekeeping test (Keychain item, saved host and cache removed) |
| Python bridge tests including installed-Hermes test | Passed, 26 tests |

The Swift integration suite uses the production aggregate client and transport with an injected URLProtocol fixture for controlled failures. It covers bearer auth/401, unreachable bridge, reachable bridge with unavailable Hermes, SSE framing/UTF-8, committed-cursor replay, duplicate sequence suppression, stable assistant identity/final-history replacement, checkpoint-before-ACK, active-run cache restoration on relaunch, Home aggregation/stale cache, run-scoped stop/steer, clarification response targeting, dangerous approvals disabled, uncertain mutations without retries, idempotency headers, capability gates, source Kanban transitions, real simulator Keychain save/read/remove, sanitized error text and token totals without double counting reasoning.

The bridge suite covers multiple consumers, restart recovery, missing upstream handles, 300-second cleanup/long-run reconciliation under controlled upstream fixtures, stale FIFO approval rejection, exact fresh/expired clarification IDs, malformed requests, failed upstream requests, authentication/scopes/revocation, concurrency/idempotency, retention/paginated replay and artifact confinement. Its installed-Hermes test uses the actual packaged CLI and source with a local model provider. Integration-added assertions verify configured board discovery and state-dependent Kanban targets.

Simulator Debug builds/tests and unsigned device-target Release build both succeed. Ad-hoc simulator signing validates Keychain; the device-target build is a compile check, not a signed install. Final functional test result bundle: `Test-Hermes-2026.10.02_08-51-29--0500.xcresult` under Xcode DerivedData. Bridge final result: 26 passed in 19.11 seconds.

## Real local stack

`RealStackTests.simulatorInstalledHermesStack` runs inside the signed simulator test host using `BridgeHermesClient`, actual URLSession networking, SSE and Keychain:

**Simulator → production hermes-mobile-bridge → actual installed Hermes desktop backend → deterministic local OpenAI-compatible model fixture.**

The fixture creates a private disposable Hermes home/workspace, cron job and Kanban task. Production provider credentials/configuration/session data are not inherited. The model emits real streaming protocol chunks and asks Hermes to execute the safe terminal command `sleep 6`. Restart controls kill/restart only test-owned services. They are fixture endpoints, not bridge API additions.

| Check | Local evidence |
|---|---|
| Authenticate/connect | Real scoped bearer stored/read through simulator Keychain; bridge and Hermes healthy |
| Sessions | Canonical list, create, history and send through real Hermes |
| Streaming | Incremental response and complete text observed through real SSE |
| Tool activity | Actual Hermes terminal tool start/result observed |
| Phone disconnect/reconnect | Consumer cancelled during response, resumed from last applied cursor |
| Replay/duplicates | Same bridge run ID; one assistant bubble; canonical history retains its stable ID |
| Relaunch during active work | New production client reconnects while terminal tool executes; existing run remains active |
| Steering | Run-scoped POST accepted; fixture confirms instruction reached a later model request |
| Stop | Actual active tool run resolves to canonical cancelled state |
| Scheduled work | Actual isolated cron fixture listed; Run Now remains a scheduler due-time update |
| Kanban | Actual isolated task/board listed with source state and conditional transitions |
| Profiles | Actual default profile listed |
| Usage/status/Home | Actual usage analytics/status and Home aggregation read |
| Hermes restart | Bridge stays alive, interrupted work becomes unknown/disconnected, health recovers; no command resubmission |
| Bridge restart | Same state directory; Swift reconnects, completed run/history remain addressable; no duplicate assistant |

The opt-in UI smoke launches the **production application composition**, authenticates with its pre-provisioned Keychain item, sends a safe prompt, displays the real streamed response, and opens Profiles and Scheduled work. No token is typed through XCTest or supplied as a launch argument/environment value.

## Failures found and fixed

- Foundation `AsyncBytes.lines` omitted blank SSE separators on this runtime. Replaced it with a bounded UTF-8 byte parser preserving LF/CRLF boundaries; added regression coverage. This was discovered through the real stack, beyond stub HTTP tests.
- An early Simulation event could write an empty applied-state bundle and mask later populated fixture caches after relaunch. Simulation retains its original cache path; production keeps atomic state-plus-cursor checkpoints. The degraded-state UI test passes after this fix.
- Unsigned simulator builds cannot use Keychain reliably. Validation uses ad-hoc signing; no Keychain fallback to ordinary storage was added.
- Corrected test-only HTTPS addresses, JSON interpolation, URLProtocol body-stream capture, schema placement and keyboard/tab navigation assertions. Production URL/auth restrictions were retained.
- The simulator encountered an Xcode screenshot timeout during one UI run. The approval interaction passed on targeted rerun (15.999 seconds); the other four existing UI tests and production smoke passed in the full run. The complete UI tour passed (165.465 seconds).
- Review hardened host/subscription generation checks around asynchronous event delivery and exact ACK targeting, denied authenticated redirects, disabled cookies/persistent network caches, and preserved uncertain mutation outcomes during cancellation.
- The unsigned generic-iOS Release build exposed a Swift 6.3.3 `EarlyPerfInliner` crash in the pre-existing generic `Resource` and mock `EventBroadcaster` destructors. A narrowly scoped `@_optimize(none)` explicit destructor workaround in those two types preserves normal application optimization. The generic-iOS Release build then succeeded, with zero compiler errors. This compiler-specific workaround can be removed once a fixed toolchain is verified.
- Source usage totals remain input/output totals; reasoning is retained as a breakdown and is not added a second time. Explicit Hermes total values are preserved.

## Limits and unverified behavior

- **No physical iPhone or Tailscale test was performed.** Loopback Simulator tests do not establish tailnet reachability, HTTPS proxy/certificate setup, network roaming or iOS background suspension behavior.
- No paid/production model provider was called in this validation. The Hermes runtime, desktop backend, bridge, Swift transport and tool execution are real; the model provider is a deterministic local fixture.
- Production launchd/HTTPS/Tailscale service deployment and Mac Studio pairing credentials were not configured. Pair the real host through More → Hosts using its HTTPS URL and scoped token.
- No hardware signing/provisioning was performed. Physical installation requires an Apple signing team/profile, iOS 18 or later and reachable trusted HTTPS over Tailscale.
- APNs, uploads/camera/voice, profile/skill mutation, memory entries, integrations and logs remain unavailable. Safe registered artifact download/open is implemented and confinement is bridge-tested; Quick Look of a downloaded real Hermes artifact was not exercised in the simulator smoke.
- Dangerous tool approval responses remain unavailable remotely. Clarification targeting is covered by bridge and Swift fixtures; a real installed-Hermes clarification tool round-trip was not generated by the local model fixture.
- Cron dispatch and Kanban worker dispatch were not started in this isolated validation. Lists/transitions are exercised; queueing is not presented as an execution.
- Independent desktop/messaging process ownership and coverage limitations remain documented in the bridge contract. Lost work is unknown, never silently declared complete or retried.
- Fixture services and simulator pairing are removed at the end of validation. Existing installed-Hermes modifications are preserved; no upstream source changes were made by this integration.

## Reproduce

See README for isolated-stack setup and paired simulator workflow. Standard unit/UI suites need no Studio service. The opt-in stack uses only a private fixture **path** in `TEST_RUNNER_HERMES_STACK_FIXTURE`, never a bearer token. Stop the fixture script after testing. Run `TEST_RUNNER_HERMES_STACK_CLEANUP=1` with `-only-testing:HermesTests/RealStackTests/removeIsolatedSimulatorPairing` to remove the test host credential/metadata/cache.
