# hermes-mobile-bridge

Studio-side Python service; HTTP/JSON actions and one authenticated SSE stream. Hermes continues executing agents, tools, cron and Kanban. No Swift code or Hermes source changes are required.

Contracts: [BRIDGE_API.md](../BRIDGE_API.md), [BRIDGE_HERMES_MAPPING.md](../BRIDGE_HERMES_MAPPING.md), [IOS_INTEGRATION_GUIDE.md](../IOS_INTEGRATION_GUIDE.md), [BRIDGE_TEST_REPORT.md](../BRIDGE_TEST_REPORT.md).

## Install

Python 3.11 or newer, on Studio:

```sh
cd hermes-mobile-bridge
python3.11 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -e '.[test]'
```

Use a separate environment; the package never imports Hermes internals or installs into Hermes's environment.

## Configure

Copy `config.example.json` to a private directory, replace paths and ports, and `chmod 600` the config. `state_dir` must be owned by the service user and mode 0700. The service stores a mode-0600 SQLite journal and bearer credential hashes there. Keep this directory on local Studio storage, outside synchronized/shared folders. Retain it across restarts; losing it loses run IDs, event cursors and device credentials.

Each configured profile needs its own loopback dashboard origin launched under that profile's Hermes home. `default` identifies the default home; other names must match Hermes profile names. Do not route two profiles through the same dashboard origin. Set `source_dir` to the audited Hermes checkout; the CLI verifies its HEAD and refuses a different commit. A dashboard restarting from another installed tree still needs operator verification; HTTP does not attest the serving binary.

Provision a high-entropy `HERMES_DASHBOARD_SESSION_TOKEN` deliberately in the dashboard's Studio launch environment. Store the same value in its bridge `token_file`, owned by the service user with mode 0600. The bridge accepts only loopback upstream origins and the audited session-token authentication path. It does not scrape dashboard HTML or use server-internal credentials. Gated remote dashboards are outside this release's supported upstream configuration.

Keep the structured dashboard socket exclusive to the bridge for these chats. Native desktop clients can rebind the sole session event sink; the upstream protocol cannot prove or prevent such ownership theft. Profiles/sessions from other Hermes processes remain incomplete live coverage. No PTY or SSH is used.

`workspaces` maps mobile display IDs to administrator-chosen directories. `artifact_roots` should contain only narrow Hermes upload/output directories (for example `.hermes/desktop-attachments`, images, screenshots). Never configure the home directory, whole project tree, or filesystem root as an artifact root. Files are registered only from known session attachments or structured tool-result paths; clients cannot submit paths for download. Root directories and file components may not be symlinks, and hard-linked files are rejected. On macOS use canonical `/private/...` paths for directories under `/var` or `/tmp`.

`boards` is an explicit allowlist. Board access is granted as a whole through its configured profile, including cards assigned to other workers; do not map a private board into a broadly readable profile. Assignment/reassignment to another worker requires that worker profile's management permission.

## Provision mobile access

```sh
.venv/bin/hermes-mobile-bridge --config /absolute/private/config.json token-create --name iPhone --profiles default
.venv/bin/hermes-mobile-bridge --config /absolute/private/config.json token-list
.venv/bin/hermes-mobile-bridge --config /absolute/private/config.json token-revoke DEVICE_ID
```

Creation prints the mobile token **once** for deliberate provisioning. Do not put that output in logs, source control or shell history. Transfer it privately to the iPhone Keychain. Read-only access: `token-create --name observer --profiles default --scopes read`. Existing tokens are revocable while the server is running. Server logs never print credentials, requests, prompts, tool results, exception URLs or access logs.

## Run

```sh
.venv/bin/hermes-mobile-bridge --config /absolute/private/config.json serve
```

Default listener: `127.0.0.1:8787`. Run as the normal Studio user, not root. A second bridge using the same state directory is rejected by an OS lock. Use one instance per configured set of backends; separate state directories are not a safe way to attach multiple bridge owners to the same chats.

For iPhone access, deliberately configure Tailscale HTTPS/reverse proxy to this loopback listener and restrict tailnet ACLs to the intended devices. Disable proxy buffering for `/mobile/v1/events/stream`; do not log Authorization headers or upstream token query URLs. Alternatively configure `tls_cert` and `tls_key` with a valid certificate and a specific tailnet listener address. The CLI refuses a nonloopback listener without TLS. No Tailscale exposure, daemon/launchd registration, certificate provisioning or production service changes are performed by this implementation.

## Reconcile an orphaned run (local operator only)

First make a timestamped, private journal backup using SQLite's backup API
(including live WAL contents). Then, as the Studio service owner:

```sh
hermes-mobile-bridge --config /absolute/private/config.json reconcile-run RUN_ID --reason "Why this execution is orphaned"
```

This is a local CLI command; there is no HTTP endpoint. It refuses states other
than `unknown`/`uncertain`, and checks Hermes `session.active_list` at execution
with an authenticated read on a separate socket. Any matching `live_id` refuses
reconciliation, including idle handles. Failed/unreadable inventory also refuses
without changing the run. It never resumes, interrupts or submits to Hermes.

A successful reconciliation atomically marks the run `failed` with
`reason=operator_reconciled` and `coverage_gap=true`, expires pending/uncertain
attention, and appends `approval.resolved`, `run.reconciled` and `run.failed`
events. The audit contains the local OS operator, timestamp, supplied reason,
prior state/reason and live handle. An already reconciled run cannot be reconciled
again. Other runs and pending command receipts are preserved. The running bridge
reads these durable changes without a restart; SSE polling observes the journal
within its normal wait interval. Rerun the updater's normal `ensure_idle` check;
this command does not bypass the gate or deploy anything.

## Validate

```sh
.venv/bin/python -m pytest -q
HERMES_BRIDGE_E2E=1 HERMES_SOURCE=/absolute/hermes-agent .venv/bin/python -m pytest -q -s
```

The opt-in integration test runs the installed Hermes interpreter/source under a temporary `HERMES_HOME`, uses a local mock model, and tears down only its own processes. It does not use production profiles or provider keys. The audited legacy commit uses Hermes's venv; the current commit resolves Hermes's managed dependency environment. Dependencies must already be prepared; lazy installs are disabled. Ordinary tests use actual loopback HTTP/WebSocket sockets with a deterministic fake Hermes service.

SQLite observations and command receipts persist indefinitely; events expire by age/count/byte budget. Run text projections are capped at one million characters; final Hermes transcripts remain canonical. Plan intentional local backup/disk monitoring for the journal. Avoid copying it while live without SQLite's backup mechanism.


Desktop Bot Mode is available through an explicit `bot_mode_roster: true` backend grant. See [source audit and mobile contract](../BOT_MODE_AUDIT.md). This grants read access to all local bots, including newly created bots, to credentials authorized for that source backend; it does not grant control of their Desktop chats.

## vNext Phase 1 additions

`botThreads` enables `POST /mobile/v1/bots/{id}/conversations`. It creates an
independent native profile session rather than reusing `Bot Chat`. The sessions
appear in the ordinary conversation list/search with `bot_id`; the existing
canonical-chat endpoints remain supported. Model/provider/reasoning/workspace
overrides apply at creation, and an omitted override follows the profile config.

`captures_root` is a dedicated bridge inbox, defaulting to `state_dir/captures`.
Use an absolute canonical path on private local storage. Its directories are
0700 and files 0600, owned by the service user; symlinks and hard links are
rejected. Capture requires `read` and `chat.control`. Dated Markdown files contain
only the exact captured UTF-8 text; JSON sidecars contain context and attachment
references. Uploads support validated media and mono M4A (`audio/mp4`), up to
10 MiB each, four per capture, with a 256 MiB per-device media limit. Text is
limited to 200 KB. Back up this inbox with the journal; losing the journal loses
receipt/ownership metadata. Capture creates no task and executes no Hermes turn.

Capture and upload IDs are stable and replay-safe, including recovery after an
interrupted receipt. Other uncertain mutations remain non-replayable. The new
read-only `/commands/{id}` endpoint exposes only the authenticated device's
receipt so Talaria can check an uncertain Ask without sending it again.

Kanban lists now include `supported_targets`. Review supports completion with a
summary. Send back writes a nonempty note through Hermes's existing comment
endpoint before the status PATCH: these two upstream writes are not atomic. An
interrupted command must be checked on the Mac and must not be replayed.
Exact approval server requests support mobile choices; legacy FIFO approvals remain Mac-only; optional clarification default/timeout
metadata passes through only when Hermes actually supplies it.
