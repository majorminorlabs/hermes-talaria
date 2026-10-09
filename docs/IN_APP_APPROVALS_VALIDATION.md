# In-app Hermes approvals validation

Date: 2026-10-09. Hardening is isolated in
`<repo>`, on
`codex/hermes-approvals-v1`, directly above `e993863`. The separate
`codex/native-coding-ios` checkout, simulator and builds remain untouched.
No Hermes source changes, deployment, notification actions, APNs changes,
Live Activity buttons or native coding session changes are included.

## Verified upstream contract and timeout read path

Installed Hermes: `4bb9e57bfde8a0affb5553eff13ed6e1f14147f1`.
The running Studio advertises `approval` server requests. Approval support now
follows that advertisement, including on unknown/newer commits; it is no longer
pinned to that hash. Attachment/image-upload commit gates are unchanged.

Source references in `<home>/.hermes/hermes-agent`:

- `tui_gateway/server_requests.py:70`: srq request frame and session/params.
- `tui_gateway/server_requests.py:253`: JSON-RPC response routes by srq ID.
- `tui_gateway/server.py:824`: response resolves the captured queue request_id.
- `tools/approval.py:153`: exact queue matching precedes legacy FIFO matching.
- `tui_gateway/server_requests.py:145`: request.cancel carries id/method/reason.
- `tui_gateway/methods_prompt.py:1130`: request.answer invokes the same response
  resolver and acknowledges ok/expired; an expired race produces mobile 409.
- `hermes_cli/web_routers/config_env.py:80-91`: existing read-only GET /api/config
  returns configuration within the requested profile scope.
- `tools/approval_context.py:218-223,240-258`: Hermes reads approvals.timeout
  from live configuration (default 300), applying its runtime safety cap.

The Studio's read-only GET /api/config?profile=default returned
approvals.timeout=60. New exact approval items use the configured timeout when
that advertised read-only route/value is available. Other configuration is
never persisted or exposed to the phone. If unreadable/missing, expires_at is
null; Hermes cancellation and the fresh open_requests response check own
withdrawal. Replays retain the original observation/deadline. Clarifications
retain their 290-second local window.

## Hardened behavior

Every connection attempts client.capabilities with server_requests=true.
Unsupported/failed negotiation resets clarify, approval and declines_not_shown
flags to false, preserving legacy observation without FIFO approval responses.
Clarification capability also follows the advertised flag.

Mobile exact approvals accept offered once/session/deny choices. Both all and
always are rejected; always returns 400 invalid_choice even when permanent
approval is offered. Pending state, connection generation, run/session identity,
both request IDs and live open_requests remain checked before answering.
Repeated or withdrawn requests return 409 stale_attention and never revive
through reconnect replay. Legacy approval.request remains FIFO-disabled.

Null expiry stays actionable without a local deadline and cancellation withdraws
it. Approval cards show the command and fixed copy:
“If you don't answer, Hermes blocks this command.”
Session approval stays on the card. Home swipe actions offer only Approve (once)
and Deny, with a per-item in-flight guard. Both approval and clarification stale
responses remove the card, refresh, and show “No longer pending. Refreshed.”

## Validation evidence

- Full bridge suite: 100 passed, 1 opt-in integration skip.
- Installed-Hermes integration: 1 passed using a temporary HERMES_HOME,
  disposable command fixture and deterministic local model. Configured timeout
  900 produced expires_at=observed_at+900. Once executed the command; deny
  retained the fixture and delivered BLOCKED; Mac settlement withdrew the
  request and a later mobile response returned 409 stale_attention.
- New bridge cases cover unknown/newer commit advertisement, unknown/failed
  capability RPC, clarify-only advertisement, both permanent policies rejecting
  always, null expiry past the old cutoff, cancellation, and configured/missing/
  unreadable timeout. Existing FIFO, double-tap and replay checks passed.
- Full Swift suite: 99 tests passed in 16 suites, including null-expiry mapping,
  cancellation availability, fixed timeout copy and stale clarification removal/
  refresh. The initial test host failed to attach XCTest; restarting only the
  dedicated approval simulator resolved it.
- Approval UI suite: 2 tests passed on the dedicated iPhone 17 Pro simulator.
  Approve once removed the card; stale tap showed “No longer pending. Refreshed.”
  and removed the card after refresh. Xcode reported TEST SUCCEEDED.
- git diff --check: passed.

Evidence: <local evidence log>,
<local evidence log>,
<local evidence log>
These isolated integration/UI checks do not certify a deployed physical-phone
path. No deployment or iPhone installation was attempted in this hardening task.

## Updater blocker: initial read-only investigation

Before the approved reconciliation below, the private production journal contained one unknown run:

| Field | Observed value |
| --- | --- |
| Run ID | <run-or-request-id> |
| Conversation ID | <conversation-id> |
| Conversation | <test conversation> |
| Stored session | <session-id> |
| Profile | default |
| State | unknown |
| Live ID | f50e769b |
| Last event | run.status, sequence 9469 |
| Last event time | 2026-10-09 07:01:04.444651 America/Chicago (UTC-05:00) |
| Last event payload | state=unknown, coverage_gap=true |
| Recorded reason | upstream_disconnected |

Authenticated session.active_list returned sessions=[]: Hermes does not report
that handle as live. No session.resume was performed for the absent handle,
since resuming saved history could create a replacement session. The missing
handle is evidence of lost execution coverage, not proof that the command
completed successfully.

The bridge disables controls for unknown runs (service.py:74); Stop also requires
an active exact live handle (service.py:465-479). There is no public bridge API
that safely marks this absent unknown run terminal. Reconnect reconciliation
preserves unknown when the handle is absent. Thus neither Stop nor a restart is
a supported resolution for this journal entry.

The initial proposed safe action, requiring separate authorization, was: back up the private
journal; perform an explicit operator reconciliation of this one run using the
existing bridge Store.update_run/Service.emit/invalidate_attention machinery,
recording a failed terminal outcome with the coverage gap and missing-handle
reason preserved rather than asserting successful completion. A reviewed
maintenance entry point would be needed; none was added or run during the initial hardening task. Then rerun
ensure_idle normally. Do not delete the row, replay the prompt, or bypass the
gate. The production journal and ensure_idle remained unchanged during that initial investigation.


## Approved local operator reconciliation

The user subsequently authorized reconciliation of this one run. A consistent
SQLite backup, including live WAL contents, was created before changes and
passed integrity_check. The backup preserves the original unknown run:

`<home>/Library/Application Support/HermesMobileBridge/backups/<backup>.sqlite3`

Added the local-only command (no HTTP endpoint):

```sh
hermes-mobile-bridge --config /absolute/private/config.json reconcile-run RUN_ID --reason "Operator explanation"
```

It refuses non-unknown/non-uncertain states, any live_id present in a fresh
Hermes active list (even idle), or an unreadable inventory. One SQLite write
transaction covers the final read/check, failed terminal status with a visible
coverage gap, pending/uncertain attention expiry, and audit/terminal events.
Failures roll the transaction back. It does not resume Hermes sessions, submit
prompts, restart services or alter other command receipts.

Executed from the isolated worktree CLI against the existing private journal:

- Run: <run-or-request-id>.
- Time: 2026-10-09 08:58:54.871910 America/Chicago (UTC-05:00).
- Operator: <operator>.
- Supplied reason: orphaned by physical steer/stop validation; Hermes active list empty.
- Prior state/reason: unknown / upstream_disconnected.
- Result: failed / operator_reconciled, coverage_gap=true; never completed.
- Events: run.reconciled sequence 9474, run.failed sequence 9475.
- Expired attention: none existed for this run; zero pending/uncertain remain.
- The running bridge read back that terminal result without a restart.
- The unchanged updater ensure_idle passed against the actual running bridge.

Validation: 13 focused reconciliation tests passed; the full bridge suite passed
113 tests with one opt-in skip; the separate installed-Hermes integration passed
one test. Coverage includes live/state refusal, unknown and uncertain repair,
audit operator/time/reason/prior state, attention expiry, repeat refusal, invalid
inventory refusal, atomic rollback, and the real ensure_idle function blocking
before and passing after reconciliation. Evidence logs:
<local evidence log>, <local evidence log> and
<local evidence log>

No Hermes source changes or deployment occurred. Approval Swift/UI source is
unchanged from the preceding validated hardening commit. The other branch and
its work remain untouched. The updater gate was not bypassed or changed.

## Physical acceptance attempt via iPhone Mirroring (2026-10-09)

The installed Talaria is version 0.2.0, build 2, from b71c569. The user reports
Approve once and timeout → BLOCKED already passed manually; those are not
claimed as newly verified in this attempt.

Prepared ~/talaria-approval-test/b.txt, c.txt, d.txt and e.txt. The current
profile-scoped Hermes approval timeout was read as 60 seconds. The user approved
a temporary increase to 180 seconds followed by restoration to 60 seconds.
That change has not yet been applied because the UI control prerequisite failed.

Opened iPhone Mirroring, but macOS System Events denied Accessibility control:
“osascript is not allowed assistive access” (-1728). No test prompts or approval
decisions were sent. Deny, Mac-wins/stale-tap, lock/reopen and swipe acceptance
remain pending; no screenshots or approval journal lines exist for these tests
yet. Accessibility access for the responsible Codex/control process is needed
before continuing. The timeout remains 60 seconds and the four fixtures exist.

No product code, signing settings or Hermes source were changed. No merge.

## Physical acceptance after Accessibility approval (2026-10-09)

**Result: 3 of 4 checks passed; swipe acceptance failed. No product code changes
or merge.** The earlier Accessibility blocker was cleared by the user. These
checks used the installed 0.2.0 build 2 from b71c569, controlled through the
Studio's iPhone Mirroring window with observed screenshots and macOS input
synthesis. Each accepted test used a new Talaria Ask thread and the exact
requested `rm -rf ~/talaria-approval-test/<file>` command.

The existing profile-scoped Hermes REST config path changed approvals.timeout
from 60 to 180 seconds with user authorization; GET verified 180 before tests.
The same path restored it to **60 seconds**, verified by GET after the tests.
No Hermes source, signing settings, notification actions, or deployment changed.

| Check | Result | Run | Filesystem outcome |
| --- | --- | --- | --- |
| Deny b.txt | PASS: Deny on the phone; agent received `BLOCKED: Command denied by user`; card disappeared | `<run-or-request-id>` | b.txt remains |
| Mac wins c.txt | PASS on retry: exact native Mac approval, then phone Approve once; `No longer pending. Refreshed.` toast, card removed, no persistent error | `<run-or-request-id>` | c.txt absent; exactly one terminal execution in this run |
| Close/reopen d.txt | PASS: Mirroring closed for at least 30 seconds; same approval returned with correct countdown; phone Approve once succeeded | `<run-or-request-id>` | d.txt absent |
| Swipe e.txt | FAIL: Now's working row exposes Stop; the Needs You card has no approval swipe actions. Denied via the card afterward; agent received BLOCKED | `<run-or-request-id>` | e.txt remains |

Evidence is retained under `evidence/in-app-approvals-20261009/`:

- Deny: [pending](evidence/in-app-approvals-20261009/deny-pending.png), [result](evidence/in-app-approvals-20261009/deny-result.png), [journal](evidence/in-app-approvals-20261009/deny-journal.jsonl), seq 9555 requested, 9556 resolved, 9557 BLOCKED.
- Mac wins: [pending](evidence/in-app-approvals-20261009/mac-pending.png), [stale toast](evidence/in-app-approvals-20261009/mac-stale-toast.png), [journal](evidence/in-app-approvals-20261009/mac-journal.jsonl), seq 9640 requested, 9641 expired/withdrawn, 9642 terminal completed with exit code 0.
- Close/reopen: [before](evidence/in-app-approvals-20261009/lock-pending.png), [reopened](evidence/in-app-approvals-20261009/lock-reopened.png), [result](evidence/in-app-approvals-20261009/lock-result.png), [journal](evidence/in-app-approvals-20261009/lock-journal.jsonl), seq 9606 requested, 9607 responded, 9608 completed with exit code 0.
- Swipe: [pending](evidence/in-app-approvals-20261009/swipe-pending.png), [Stop confirmation reached by working-row swipe](evidence/in-app-approvals-20261009/swipe-stop-confirmation.png), [card without swipe actions](evidence/in-app-approvals-20261009/swipe-card-no-actions.png), [journal](evidence/in-app-approvals-20261009/swipe-journal.jsonl), seq 9623 requested, 9624 responded, 9625 BLOCKED. Stop was cancelled; it was not executed.

The Mac action used Hermes' native `approval.respond` RPC directly on the Studio,
with live session `<live-session-id>`, exact queue request
`<run-or-request-id>`, and choice `once`. Hermes returned
`{"resolved": 1}` before the phone tap. The observed stale toast is produced
by the installed client's HTTP 409 `stale_attention` mapping
(`Hermes/Services/Bridge/BridgeTransport.swift:400-417` and
`Hermes/Services/Protocols/HermesClient.swift:48`). No separate HTTP traffic
capture was taken. The journal records one terminal start and one successful
terminal completion in this final run.

For close/reopen, the pending screenshot shows 171s left. Mirroring closed at
19:08:34 UTC and reopened at 19:09:13 UTC, after a 30-second wait plus operation
overhead. The next screenshot shows 109s left, consistent with the approval's
180-second deadline and total elapsed time since the first screenshot. This
certifies the permitted close/reopen variant, not a physical lock-button test.

The swipe failure is also grounded in the installed branch source:
`Hermes/App/RootView.swift:62` mounts `NowView`;
`Hermes/Features/Work/WorkViews.swift:77` mounts `NeedsYouGroupCard`, while
`:130-134` gives working rows only Stop. `NeedsYouCard.swift:3-19,32-72` has no
approval swipe modifier. The Approve/Deny swipe implementation in
`Hermes/Features/Home/HomeComponents.swift:200-216` is not used by this active
Now route. Fixing and rebuilding that route requires a subsequent authorized
code change; this acceptance run leaves it untouched.

The per-approval log evidence above comes from the production bridge's durable
SQLite event journal, opened read-only. launchd supervisor logs contain lifecycle
entries, not individual approval payloads. Test events were exported without
reading or changing unrelated run data.

Operator retries: the first b.txt attempt (`<run-or-request-id>`)
accidentally approved when the card appeared between a screenshot and a tap; the
fixture was recreated and Deny retried in a new thread. One c.txt typing attempt
(`<run-or-request-id>`) received a backtick instead of a tilde from
Mirroring keyboard synthesis; it was denied. An initial exact Mac-wins attempt
(`<run-or-request-id>`) verified withdrawal/deletion but did not
capture the stale toast; c.txt was recreated for the successful new-thread retry.
These attempts are not counted as acceptance passes. Final checks confirm b.txt
and e.txt exist, c.txt and d.txt do not. All test runs finished; no test approval
remains pending.

## Now swipe fix and physical test 6 repeat (2026-10-09)

**PASS: the remaining swipe acceptance failure is resolved.** Scope is the iOS
Now route, approval presentation, and its tests; no bridge-service changes or
bridge deployment. No merge to main.

Diagnosis: `Hermes/App/RootView.swift:62` mounts NowView.
`Hermes/Features/Work/WorkViews.swift:87` renders Working with WorkItemRow;
`Hermes/Stores/WorkItemStore.swift:127-137` builds those items from conversation
runs. A waiting approval is not rendered with AttentionRow. That older row's
lookup (`HomeComponents.swift:251`) uses AttentionItem.approvalID, which WorkItem
does not have. Before this fix the active Now row only added Stop and never
called `ActivityStore.pendingApproval(for:)`. BridgeMapping.swift:103 maps the
real bridge's `waiting_for_input` to `.waitingForInput`, and :120 leaves
pendingApprovalID nil. The existing ActivityStore.swift:57-58 lookup already
falls back to approval.runID; it was not failing, it was unused by this route.
The UI fixture tests `.waitingForApproval` with pendingApprovalID nil; the real
phone test covers the bridge's `.waitingForInput` path.

Now's trailing swipe resolves the run's actionable approval and offers only
Approve (once) and Deny, using ActivityStore.resolve and a per-approval in-flight
guard (`WorkViews.swift:132-154`). Stop remains on the leading swipe (:156-160).
Full swipe does not execute either decision automatically. The card still offers
session approval. Unreported Hermes risk is nil and its label is hidden in both
card and detail; Later is hidden on approval cards while Hermes's countdown
continues unchanged.

Validation of the final source:

- Full Swift suite: 100 tests in 16 suites passed.
- Approval UI suite: 5 passed, including new waiting-run swipe Approve, Deny,
  and leading Stop checks, plus existing card Approve and stale-tap checks.
- Unchanged bridge regression suite: 113 passed, 1 opt-in integration skipped.
- git diff --check passed. No changes under hermes-mobile-bridge or scripts.
- Signed device Release build and deep signature verification passed, using the
  existing external Signing.local.xcconfig unchanged. Bundle ID remains
  `xyz.majorminor.talaria.<TEAM>`, version 0.2.0, build 2.
- Installed Release in place. Saved-host configuration and active-host selection
  matched the pre-install preferences exactly (one saved Studio). Mirroring
  launched the installed app and an authenticated real approval request followed,
  verifying retained pairing. The developer CLI launch was rejected while the
  phone was locked; launching through Mirroring succeeded.
- After an idle check, approvals.timeout was set to 180 and the Hermes backend
  restarted through its existing launchd service at 14:19 America/Chicago.
  After restart and after the physical test, config GET verified **180** and
  default approvals.respond remained true, without a reason field. The timeout
  remains 180 as requested for this task.

Physical test 6: fresh e.txt and new Talaria thread, exact requested command.
Run `<run-or-request-id>`, attention
`<run-or-request-id>`, server request `<server-request-id>`.
The Now Working row's trailing swipe visibly showed **Deny and Approve only**.
Tapped Deny through that swipe. The card disappeared, the agent reported the
command was denied and did not run, and e.txt remains. No persistent error state.
The pending card also visibly omitted Moderate risk and Later.

Evidence: [pending card](evidence/in-app-approvals-20261009/swipe-fixed-pending.png),
[swipe actions](evidence/in-app-approvals-20261009/swipe-fixed-actions.png),
[result](evidence/in-app-approvals-20261009/swipe-fixed-result.png), and
[read-only journal export](evidence/in-app-approvals-20261009/swipe-fixed-journal.jsonl).
Journal sequences: 9659 approval.requested, 9660 approval.resolved/responded,
9661 tool.failed with `BLOCKED: Command denied by user`, 9672 run.completed.
The approval's expires_at minus observed_at is exactly 180 seconds. ensure_idle
passed afterward, with no pending test attention.

Build/test/install logs and the executable SHA-256 receipt are retained locally
under build/now-approval-swipe. Final verified tests are in verified-tests.log;
bridge-tests.log records the regression count, and signed-release.log records
BUILD SUCCEEDED. Early simulator attachment attempts and UI locator/fixture
failures were resolved before this final passing run. The scoped code was built
and installed from the same source later committed; the version/build identifier
was not changed. The earlier test-6 failure above remains as historical evidence.
