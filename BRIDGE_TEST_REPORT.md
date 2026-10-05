# Bridge validation report

Date: 2026-10-02. Workspace: <talaria-checkout>. Hermes baseline: 2a4c9afd7bd7b56d3e1f95524ca8956092f2904c. Bridge version: 0.1.0.

## Result and scope

The bridge is implemented and locally installable. The standalone package environment runs the automated suite, including real loopback HTTP/WebSocket/SSE and an installed-Hermes integration test. No SwiftUI work, Hermes source modifications, production configuration/data changes, tailnet exposure, launchd registration or deployment were performed.

Final suite result: **26 passed in 14.92 seconds, with no warnings**, in the separate bridge environment. The installed-source test reports five local model requests, successful chat completion, observed tool cancellation and a mounted Kanban plugin.

Two validation layers:

- Deterministic network fixture: real aiohttp listeners and sockets, simulated Hermes RPC/state faults, real SQLite journal and authentication. This tests bridge behavior, not actual upstream agent correctness.
- Installed-source integration: actual Hermes dashboard/desktop backend/core/tools/storage/plugin at the audited commit, launched with a temporary HERMES_HOME and workspace. A local OpenAI-compatible mock model supplies deterministic responses/tool calls; production provider credentials are not inherited or used. Canonical cron/Kanban mutations occur only in that temporary home. Only test-owned processes are terminated.

## Reliability/security matrix

| Requirement | Executed evidence | Result |
|---|---|---|
| Bridge restart | Network fixture reopens same journal/credential, reattaches identical live owned session, keeps run ID and prompt count; real bridge restart retains completed IDs/bearer against installed Hermes | Pass |
| Hermes restart | Fixture drops WS/removes handles; real test abruptly kills/restarts its isolated Hermes process during work | Pass: stable run remains unknown, controls disabled, no prompt re-submission |
| Transient upstream disconnect | Reconnects same fixture process/generation; active owned handle recovered with explicit coverage gap | Pass |
| Phone background/disconnect | Close mobile HTTP client while upstream emits text/tools/completion; reconnect/replay | Pass: upstream continues |
| Replay/fan-out | Two readers retrieve identical nondestructive pages; SSE carries normalized data; cursor resumes exclusively | Pass |
| Monotonic sequences/no duplicate display delivery | Sorted unique sequences, tool-event dedup, replacement final text, late duplicate completion/approval cannot revive a terminal run | Pass |
| Pagination/retention | Page cursor stays behind undelivered events; count/per-run/byte budget expires old cursors; foreign epoch rejected | Pass: resync_required |
| Duplicate connection/command | Same device command returns same run; different payload conflicts; concurrent starts produce one execution; duplicate state-directory bridge rejected by OS lock | Pass |
| Lost Hermes reply | Prompt executed once, socket closes before response, journal receipt stays uncertain, same UUID does not execute again | Pass |
| Stop during tool work | Fixture waits for explicit interrupted completion; installed backend exercises a terminal tool and late approval after interrupt | Pass: acknowledgement stays distinct from cancellation; late FIFO cleared through whole-run interrupt |
| Late/null interrupted output | Installed Hermes emits nullable final text; regression verifies normalization and retained connection | Pass |
| Steering | Fixture queued acknowledgement; installed Hermes delivers steering text into a subsequent local model request during an active safe terminal tool | Pass; public API still reports consumed=false |
| >300-second cleanup boundary | Fixture run creation set >1,000 seconds in past remains controllable; upstream handle loss separately preserves durable observation | Pass for selected desktop path; no wall-clock 300-second AS stream run performed |
| Stale/FIFO approval | Every remote dangerous choice (once/always/deny), including after reconnect, returns conflict with zero approval.respond calls | Pass |
| Exact clarification | Valid request ID dispatched once; repeated/expired/replayed IDs rejected; expiry not refreshed | Pass |
| Failed Hermes request | Offline/rejected/lost replies become explicit errors/uncertainty, not invented success | Pass |
| Malformed request | Bad JSON, wrong field/type/query, arbitrary cwd, invalid path-like filename rejected | Pass |
| Authentication | Missing bearer 401, read-only mutation 403, revoked token 401, profile filtering in event feed | Pass |
| Provision/run/revoke CLI | Installed entry point provisions a token, launches separate server process, authenticates capabilities, revokes while running | Pass |
| Credential/state permissions | Unsafe token file mode rejected; DB/WAL files remain private; no server credential/request/exception-URL logs | Pass |
| Artifacts | Known upload/download works; metadata omits paths; traversal/symlink escape and replaced file rejected | Pass |
| Sessions | Installed-source create/start/history/search/rename/usage/delete, plus fixture list/resume/ownership conflict | Pass |
| Profiles/inventory | Allowlisted model/skill/tool/MCP inventory strips injected secret/config fields; profile-scoped access enforced | Pass for normalization; named production profile fleet not exercised |
| Cron | Installed-source create/detail/edit/pause/resume/trigger/delete in isolated home | Pass for management; trigger truthfully requires scheduler |
| Kanban | Installed plugin create/detail/edit/assignment/dependency IDs/workspace mapping; seeded canonical claim/heartbeat through upstream helpers; bridge reclaim/reassign/delete | Pass; no dispatched agent worker fabricated |
| Home | Real installed status/host/cron/Kanban plus bridge observed completion/attention aggregation | Pass |
| Package/dependencies | Editable package installation in separate Python 3.11 venv; CLI help/serve/provision/revoke; compileall | Pass |

Test files: hermes-mobile-bridge/tests/test_bridge.py, tests/conftest.py, tests/test_installed_hermes.py. The installed-source test is opt-in; ordinary pytest skips it. The packaged CLI test skips when run from an interpreter without the installed entry point.

## Commands

From the bridge directory, after installing the separate environment:

~~~sh
HERMES_BRIDGE_E2E=1 .venv/bin/python -m pytest -q -s -p no:cacheprovider
.venv/bin/python -m compileall -q src
.venv/bin/hermes-mobile-bridge --help
~~~

Hermes interpreter: ~/.hermes/hermes-agent/venv/bin/python, Python 3.11.15, aiohttp 3.13.4. Independent bridge validation environment: Python 3.11.15, aiohttp 3.14.3, pytest 9.1.1, pytest-asyncio 1.4.0. These are observed installed test versions, not a claim about latest releases. Package runtime requirement is Python >=3.11 and aiohttp >=3.12,<4.

The default system python3 selected Python 3.9 in the package directory during initial setup; the separate environment was recreated explicitly with Python 3.11. README specifies python3.11 and current pip for pyproject editable installation. Hermes's own environment was not modified.

## Findings resolved during integration

- The real Kanban kernel rejected triage→blocked. The test was corrected to use a supported transition; the bridge now surfaces upstream validation/conflict status and advertises conditional source targets, excluding direct running/review.
- Hermes can enqueue a dangerous approval after the initial stop clears the FIFO. A durable stop intent now reasserts the authorized session interrupt when this late wait is observed. No approval action is weakened/enabled.
- Interrupted assistant completion can have null text. It is normalized to an empty string; late duplicate frames cannot revive a finished execution.
- File attachments need Hermes reference syntax. The bridge stores/inserts it internally, so Swift sends only ordinary prompt text.
- Dependency IDs and workspace kinds needed canonical mapping. Dependencies now use mobile IDs externally and source IDs internally; configured paths map to Hermes dir workspace.
- Opening the auth CLI against a live journal must not mark pending commands uncertain. Recovery is restricted to bridge ownership/startup, not token registry operations.

## Unverified behavior and limits

- No physical iPhone, Swift URLSession SSE parser, real Tailscale route, tailnet ACL, DNS/certificate, TLS proxy buffering, mobile radio switch or APNs delivery was tested. Loopback transport success is not production reachability.
- No live paid provider/model was exercised. Model/reasoning metadata and cost counters vary by provider; no universal quota/cost was invented.
- No production gateway, cron dispatcher, scheduled model execution, script-only output, named-profile fleet or Kanban agent worker was run. Canonical seeded claim/heartbeat tests validate management and projection without proving dispatch health.
- Image/PDF conversion and every tool-specific generated artifact convention were not exhaustively exercised; text attachment/download was. PDF relies on Poppler. Known artifact discovery remains narrower than arbitrary filesystem access.
- Read-only memory metadata and some provider/profile details depend on existing Hermes installations; memory content/settings/log passthrough are intentionally absent.
- Exact dangerous approval targeting remains impossible with this upstream FIFO. Remote responses are disabled. Clarification ID age/generation checks are conservative and do not provide universal approval semantics.
- A native desktop client can steal the same Hermes session's transport without a reported ownership token. Independent Hermes processes cannot all be observed/controlled. Exclusive backend use remains a requirement.
- Abrupt Hermes loss can destroy unobserved events/outcome. Unknown stays explicit. Event journal age/count/byte expiry requires snapshot hydration; it cannot reconstruct source events never observed.
- Command deduplication is durable at the bridge boundary but cannot guarantee exactly-once effects across an upstream reply/crash gap. Retries of failed/cancelled work are new executions and may repeat earlier tool effects.
- Canonical task updates are not universally atomic/CAS. Assignment is separated and running tasks use reclaim; independent clients can still race source transitions. Refresh after conflicts/errors.
- Metadata/command receipts/run observations are retained beyond event expiry. Protect/back up/monitor the private state directory; it is not an encrypted transcript vault or automatic erasure system.
- Only the configured state-directory owner is process-locked. Do not start independent bridge journals against the same sessions.

## Preservation

Hermes Git status remained exactly the pre-existing changes: gateway/platforms/bluebubbles.py, tests/gateway/test_bluebubbles.py, and untracked .install_method. No Hermes patch was required. Existing iOS source/project/tests and the completed audit documents were not modified. Test services were torn down; no bridge production service was left running.
