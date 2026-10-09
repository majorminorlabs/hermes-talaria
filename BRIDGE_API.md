# Hermes mobile bridge API v1

Implemented in hermes-mobile-bridge 0.1.0. Upstream baseline: Hermes 2a4c9afd7bd7b56d3e1f95524ca8956092f2904c, desktop contract 2. This describes implemented behavior; the earlier audit explains the upstream gaps.

All paths begin with **/mobile/v1**. Use HTTPS/JSON for state/actions and **one SSE channel** for all authorized profiles. SSE uses ordinary HTTP authentication and replay cursors; actions remain explicit HTTP requests. The phone never owns a Hermes socket. Polling and SSE share the same nondestructive journal.

## Authentication and commands

Every request requires **Authorization: Bearer <mobile-device-token>**. Mobile authentication accepts no query tokens, cookies, provider credentials or Hermes dashboard token. Studio provisioning generates a random 384-bit token; only its SHA-256 hash, device label, scopes, profile allowlist and revocation flag are stored. Config/upstream secret files require owned mode 0600; state requires owned mode 0700. Provision/revoke through the Studio CLI, never an unauthenticated pairing endpoint.

| Scope | Permission |
|---|---|
| read | Required for all requests; authorized profiles, runs, tasks, events and registered artifacts |
| chat.control | Conversations, run controls, attachment uploads and capability-gated bot management |
| tasks.manage | Cron/Kanban mutations; assigning another worker requires that worker profile's permission |
| approvals.respond | Exact clarifications and approval server requests; legacy FIFO approvals remain disabled |

Every mutation requires a UUID **Idempotency-Key** header and a JSON object, including {} for empty actions. Persisting its receipt precedes dispatch. The same device/key/method/path/query/body returns the recorded response; a changed payload/device conflicts. Pending or uncertain commands return 409 command_uncertain. An interrupted request does not prove nonexecution. Never automatically repeat an uncertain operation with a new UUID.

All IDs are opaque to Swift. Conversation/cron/task IDs internally include profile namespaces; do not construct/decode them. Run/attention IDs belong to the bridge. Kanban attempt IDs remain integers scoped by board/profile and differ from bridge chat run IDs.

Bridge timestamps are Unix seconds (numbers); upstream schedule times retain ISO strings. Optional values can be absent/null. Content/tool results can include Markdown, code and multimodal JSON.

## Endpoints

Collection/inventory profile query defaults to default. Detail IDs carry their own scope. Unknown/disallowed profiles or boards return 403.

| Method/path | Request | Response |
|---|---|---|
| GET /capabilities | — | Version, epoch/cursor, scopes, per-profile health/features/workspaces, retention/coverage |
| GET /home | — | Aggregated health, activity, active runs, attention, failures/blocks, completions, scheduled results/upcoming jobs, Kanban, coverage errors/watermark |
| GET /profiles | — | {profiles:[Profile]} for configured authorized profiles |
| GET /profiles/{id} | — | Identity, description, skill count, model metadata, SOUL, health/session link |
| GET /conversations?profile=&q=&limit=&offset= | q uses Hermes search; limit 1–100 | {conversations:[Conversation],total?,offset}; optional search snippet |
| POST /conversations?profile= | {title?,model?,provider?,reasoning_effort?,workspace?} | 201 Conversation |
| GET /conversations/{id} | — | {conversation,messages:[Message],current_stored_id?,cursor,observed_runs?:[Run]} |
| PATCH /conversations/{id} | {title?,archived?}; title max 200 chars | Conversation |
| DELETE /conversations/{id} | {} | {deleted:true}; rejects active/uncertain work and another client's live handle |
| POST /conversations/{id}/resume | {} | Conversation; resume idle stored interaction under bridge ownership |
| POST /conversations/{id}/runs | {text}; nonempty, max 200,000 chars, no slash administration | 202 Run |
| GET /conversations/{id}/usage | — | Owned live conversation usage; otherwise 409, use analytics |
| GET /runs?state=&limit=&offset= | Optional state; limit 1–100 | {runs:[Run],cursor} |
| GET /runs/{id} | — | Run, retained after Hermes forgets its handle |
| POST /runs/{id}/stop | {} | {acknowledged:true,termination_confirmed:false,run} |
| POST /runs/{id}/steer | {text} | {status:queued/rejected,consumed:false} |
| POST /runs/{id}/retry | {} | 202 new Run with parent_run_id; failed/cancelled submitted prompts only |
| GET /runs/{id}/events?after=&limit= | Cursor; limit 1–500 | ReplayPage |
| GET /events?after=&limit= | Cursor; limit 1–500 | ReplayPage across authorized profiles |
| GET /events/stream?after= | Or Last-Event-ID; omission starts at current watermark | Authenticated SSE across authorized profiles |
| GET /attention | — | {items:[Attention]}, up to 200 recent observations |
| POST /attention/{id}/respond | {answer} for clarification; {choice} for exact approval | Acknowledgement or 409 |
| GET /inventory/{resource}?profile= | skills/tools/mcp/models/usage/host/memory; usage days 1–365 | Allowlisted inventory |
| GET /cron?profile= | — | {jobs:[ScheduledJob]} |
| POST /cron?profile= | {prompt,schedule,name?,deliver?,skills?} | 201 ScheduledJob |
| GET /cron/{id} | — | {job,recent_conversations,execution_evidence} |
| PATCH /cron/{id} | {prompt?,schedule?,name?,skills?,model?,provider?} | ScheduledJob |
| DELETE /cron/{id} | {} | {deleted:true} |
| POST /cron/{id}/enable or /disable | {} | {job,acknowledged:true,...} |
| POST /cron/{id}/run-now | {} | {job,acknowledged:true,execution_started:false,scheduler_required:true} |
| GET /kanban/tasks?profile=&board= | Configured board only | {board,tasks:[Task],workers,workers_checked_at} |
| POST /kanban/tasks?profile=&board= | {title,body?,assignee?,priority?,parents?:[mobileTaskID],triage?,skills?,max_runtime_seconds?,workspace?} | 201 Task |
| GET /kanban/tasks/{id} | — | {task,links,diagnostics,comments,attempts,attachments,recent_activity,supported_targets,...} |
| PATCH /kanban/tasks/{id} | {status?,assignee?,priority?,title?,body?,result?,block_reason?,summary?} | {acknowledged:true,task_id,refresh_required:true} |
| DELETE /kanban/tasks/{id} | {} | {deleted:true}; upstream validates |
| POST /kanban/tasks/{id}/reclaim | {reason?} | Acknowledgement; Hermes releases claim/terminates worker/records outcome |
| POST /kanban/tasks/{id}/reassign | {profile,reclaim_first?,reason?}; empty profile unassigns | Acknowledgement; refresh canonical state |
| GET /kanban/tasks/{id}/attachment?id=<integer> | Must belong to that task | Binary download through restricted Hermes route |
| POST /attachments | {conversation_id,name,content_type,content_base64} | 201 {staged:true,attached:false,upload_id,artifact} |
| GET /conversations/{id}/artifacts | — | {artifacts:[Artifact]} |
| GET /artifacts/{id} | — | Artifact metadata |
| GET /artifacts/{id}/download | — | Binary download; no path parameter |

Use conversation IDs returned by list/search/create. Collections lazily establish canonical mappings. Empty conversations can be bridge-tracked drafts until Hermes persists them; detail returns draft:true and messages:[] during that window. Agent handles remain ephemeral.

Workspace is an administrator-configured display ID, never a client path. Reasoning at creation: none/minimal/low/medium/high/xhigh, conditional on provider/model support. This release sets model/provider/reasoning at creation; it does not expose later reasoning changes because the upstream handler writes global defaults. No provider base URL or credential editing is accepted.

Imported conversations can be explicitly resumed, but conflicts are checked only in the configured desktop backend. Another Hermes process may own work this backend cannot enumerate. Concurrent control with independent desktop/messaging clients is not guaranteed. Use exclusive backend ownership for bridge-controlled chats.

Kanban source states: triage/todo/scheduled/ready/running/blocked/review/done/archived. Display done maps to complete; raw_state preserves done. PATCH target vocabulary is triage/todo/scheduled/ready/blocked/done/archived. Detail returns conditional supported_targets derived from the current source guards; dependency checks can further reject a ready promotion after concurrent changes. Running requires the dispatcher; review has no dashboard PATCH transition. For an already running task use reclaim. Assignment changes must be separate: upstream compound updates are not atomic. Board scope covers the whole configured board, including other assignees. Dependencies use mobile task IDs and must remain within one board/profile.

Cron run-now sets the due time via trigger. It neither executes work in the bridge nor proves scheduler health. Script-only jobs may have no conversation. Last execution status and delivery errors remain distinct.

## Core schemas

~~~json
{
  "id": "opaque-conversation-id",
  "profile": "default",
  "owned": true,
  "title": "Work",
  "model": "chosen-model",
  "provider": "chosen-provider",
  "reasoning_effort": "medium",
  "cwd": "/configured/Studio/project",
  "archived": false
}
~~~

Message fields: id, role, content, tool_calls, tool_call_id, tool_name, timestamp, optional reasoning. Full system prompts/configuration/credentials are excluded.

~~~json
{
  "id": "bridge-run-uuid",
  "conversation_id": "opaque-conversation-id",
  "profile": "default",
  "task_id": null,
  "origin": "desktop_rpc",
  "state": "running",
  "created_at": 1790916000.0,
  "updated_at": 1790916001.0,
  "assistant_text": "partial reply",
  "snapshot_cursor": "journal-epoch:42",
  "controls": {"stop": true, "steer": true, "retry": false},
  "coverage_gap": false,
  "projection_truncated": false,
  "parent_run_id": null
}
~~~

Run states: starting/running/waiting_for_input/stop_requested/complete/failed/cancelled/unknown. Completion/interruption/error events determine outcomes; missing handles and idle activity do not prove completion/cancellation. Unknown disables control/retry and blocks another submission in that conversation. Inspect canonical history/Studio; do not silently duplicate work. A new conversation remains possible. Goal continuations receive a separate run ID linked by parent_run_id.

Usage: scope=conversation_cumulative, tokens={input,output,cache_read,cache_write,reasoning,prompt,completion,total,calls,context_used?,context_max?,context_percent?,compressions?}, model, optional cost={status,usd,source:hermes_estimate}. Only Hermes-reported amounts are returned. A run's snapshot can be cumulative conversation usage, not that run's delta.

Task: opaque ID/profile/board/kind=kanban/state/raw_state/upstream_id and available title/body/assignee/priority/result/block reason/times/heartbeat/workspace/current attempt/summary. Attempts are canonical integer board run records with independent statuses/outcomes. Dependency links use mobile IDs. Worker rows expose task/attempt/profile/status/heartbeat metadata, without generic process-kill APIs.

ScheduledJob: opaque ID/profile/kind=cron/upstream_id plus available name/prompt/skills/schedule/display/repeat/enabled/state/next run/last run/last status/errors/model/provider/workdir. A routine is durable work, not one execution.

Artifact: id/conversation_id/run_id?/profile/name/size/content_type. Paths/inodes stay internal. Registerable sources are known session uploads and structured tool result paths (file_path/image_path/artifact_path) inside narrow configured roots. Relative paths, traversal, symlink components, hard links, oversized files and changed identity/size/mtime are rejected. Discovery is intentionally incomplete. No arbitrary filesystem browser is exposed.

Uploads default to 10 MiB; downloads to 50 MiB. Filename only, no path separators. Accepted content types: PNG/JPEG/WebP/GIF, PDF, plain text, Markdown, JSON and octet-stream. Images/PDF use Hermes attachment queues. The bridge appends Hermes file references internally to the next submitted prompt; Swift does not assemble host-path syntax. Download registration may be unavailable if the upstream output directory is not explicitly allowed. PDF conversion requires upstream Poppler.

## Events and replay

~~~json
{
  "seq": 43,
  "cursor": "journal-epoch:43",
  "type": "assistant.delta",
  "profile": "default",
  "run_id": "bridge-run-uuid",
  "conversation_id": "opaque-conversation-id",
  "observed_at": 1790916001.0,
  "payload": {"text": "more text"}
}
~~~

Sequence strictly increases globally; per-run sequences can have gaps. The epoch persists with the database across restarts. Bounded raw Hermes frames stay internal.

| Event | Payload |
|---|---|
| studio.connection | connected flag for profile transport |
| run.started | Initial Run observation; actual execution start is separate |
| run.status | State, optional gap/hydration/stop acknowledgement/reason |
| assistant.delta | Text to append to run projection |
| assistant.completed | Text/status/warning; replace partial text |
| tool.started | Tool ID/name/context/optional args text |
| tool.completed / tool.failed | Tool ID/name/args/result/duration/summary/todos where available |
| approval.requested | Attention observation |
| approval.resolved | Observation state; uncertain is not an approve/deny acknowledgement |
| steering.accepted / steering.rejected | Queued/rejected, consumed=false |
| run.completed / run.failed / run.cancelled | State and available usage/reason |
| task.activity | Board/mobile task ID/attempt ID/source kind/time/allowlisted details |

Oversized event payloads (>128 KiB) become {truncated:true,preview,hydrate:true}; raw debug frames have a separate cap. Run text projections retain at most one million characters and indicate truncation. Canonical transcripts/task details provide full text.

ReplayPage = {events,cursor,has_more}. After is exclusive. Default retention: 10,000 global events, 2,000 per run, seven days, 32 MiB serialized event/debug budget; all limits apply together. Durable run/command metadata outlives event retention. Expired, foreign or future cursors return 409 resync_required with a current cursor, never silently skip. Readers/disconnects do not consume events.

~~~text
id: journal-epoch:43
event: assistant.delta
data: {"seq":43,"cursor":"journal-epoch:43","type":"assistant.delta",...}

event: stream.checkpoint
data: {"cursor":"journal-epoch:43"}
~~~

Checkpoint advances through filtered events and provides an approximately ten-second idle heartbeat; it has no sequence of its own. If retention overtakes a connected client, stream.resync_required supplies the error envelope and closes. Revocation closes the stream; reconnect returns 401. One stream per phone is recommended. Concurrent streams are nondestructive; consumers deduplicate by epoch/sequence.

Home captures its watermark before upstream reads. Hydration is not one atomic transaction across Hermes stores. Each run snapshot has a snapshot_cursor: skip run events at/below that run snapshot's sequence. Apply state/task events as upserts. Final text replaces partial text; canonical history hydration replaces the transcript rather than appending duplicate bubbles. Coverage gaps require hydration; unobserved tool/approval events cannot be reconstructed.

## Approval and stop safety

Attention fields: id/run_id/conversation_id/profile/kind/state/observed_at/expires_at/can_respond/limitation/details. Details include command/description/patterns/permanent-policy flag or question/choices.

On audited Hermes `4bb9e57`, approval server requests carry an exact `srq-…` ID and a separate queue `request_id`. These attention items have `kind=approval` and `can_respond=true`. POST `/attention/{id}/respond` with `{"choice":"once"}`, `{"choice":"session"}`, or `{"choice":"deny"}` as offered by `details.choices`. The bridge checks the pending item, expiry, continuous connection generation, waiting run, and both IDs in a fresh `session.resume.open_requests` snapshot. It answers via Hermes's acknowledged `request.answer` proxy to the JSON-RPC response resolver. A repeat, cancellation, or losing race returns `409 stale_attention`. Approval expiry uses the profile’s `approvals.timeout` read through Hermes `GET /api/config` when available; otherwise `expires_at` is null and there is no local expiry. `request.cancel` expires the item and emits `approval.resolved`; replay never revives an answered or withdrawn item.

`all` is rejected. `always` returns `400 invalid_choice` from mobile regardless of `allow_permanent`; Talaria v1 omits it entirely. Details include the command, description, choices, permanent policy, and `on_timeout` when supplied. Legacy `approval.request` events retain `can_respond=false` and `limitation=upstream_fifo_without_exact_target`; every choice returns `409 exact_target_unavailable`. Phone responses never use the FIFO `approval.respond` operation.

Clarifications use actual upstream request IDs internally. Responses require a pending observation, the same continuous upstream connection generation, a waiting run, and age below 290 seconds. Resume/replay does not refresh IDs or expiry. Stale/expired/reconnected prompts fail closed. Secret/password and terminal-buffer prompts remain local-only. Completion/disconnect invalidates attention as uncertain; expiration reflects a bridge deadline, not proof of an upstream decision.

A stop records durable intent. If Hermes enqueues a prompt after interrupt cleared its FIFO, the bridge reasserts the already-authorized whole-run interrupt. It never approves/targets an individual FIFO entry. A stop acknowledgement does not prove every external effect has stopped.

## Capabilities, inventory and errors

Capabilities include current socket health, discovered route availability, configured boards/roots/workspaces (each profile includes its boards allowlist), audited/installed commit metadata, scopes and retention. Sessions/runs/stop/steering require a usable structured socket; replay remains available offline. Inventory route discovery uses OpenAPI rather than API-server capability flags. Permission scopes are an additional check. Bot Mode and writable Bot Chat require explicit source grants and an audited Bot Mode handshake; rooms are false; dangerous approval response requires a connected backend advertising `approval` server requests; its reason is present only when unavailable. CLI source verification when source_dir is configured does not attest a running HTTP binary launched elsewhere.

Inventory includes skills metadata, CLI-default toolsets, credential-free provider/model metadata/capabilities, MCP name/transport/enabled/tool selection, Hermes usage analytics, host metrics and memory provider/file-size metadata. It excludes raw config, MCP commands/env/auth/URLs, memory contents, logs, billing changes and global settings. Configured MCP/tool availability does not prove external service health.

~~~json
{"error":{"code":"stale_attention","message":"Prompt is expired or its connection changed","details":{}}}
~~~

Statuses: 400 malformed/unsupported fields; 401 invalid/revoked credential; 403 scope/profile/board denial; 404 missing resource; 409 conflict/stale/ambiguous/uncertain/resync; 410 deleted conversation; 413 size limit; 422 upstream validation; 502 upstream/protocol rejection; 503 unavailable/uncertain upstream; 500 internal failure. Numeric upstream code/status can appear in details; upstream exception text/URLs/config do not. Compound upstream mutations can partially apply: refresh canonical state after errors. There is no raw CLI, shell, PTY, unrestricted process/filesystem, Bot configuration or global configuration API.


## Desktop Bot Mode resources

See [Bot Mode source audit](BOT_MODE_AUDIT.md) for `/bots`, `/bots/{id}`, GET `/bots/{id}/conversation` and writable POST `/bots/{id}/conversation` contracts, explicit whole-roster authorization, profile fallback and canonical-title resolution. `features.botMode` is independent from `features.profiles`. POST initializes/opens the source canonical Bot Chat with `chat.control` plus `bot_chat_control:true`. Existing conversation/run/control/history APIs are reused with attached bot identity. Native create/edit/hide/duplicate is supported when `bot_mode_management:true` and `chat.control` are granted at the audited 4bb9e57 source. See [Bot management](BOT_MANAGEMENT.md). Canonical rename/delete is protected.


### Native bot management and staged media

- `GET /bots/inventory?bot_id=` returns the host/profile model, installed-skill,
  toolset and configured-MCP selections plus field availability. Credentials,
  endpoints, commands and environment values are excluded.
- `POST /bots {name,description,soul?,model?,provider?,skills?,toolsets?,mcp_servers?}`
  creates a native profile and returns `{bot}`. Model/provider must be selected
  together from the host inventory. Selection lists are bounded to 512 entries.
- `PATCH /bots/{id}` changes the same allowlisted fields. Hermes guarded model
  updates can return `409 bot_model_confirmation_required`; explicit approval
  resubmits with `confirm_expensive_model:true`.
- `POST /bots/{id}/hide {hidden:true|false}` changes native visibility and retains
  history. The default bot is protected. `POST /bots/{id}/duplicate {}` clones
  configuration through Hermes, with a fresh identity and no copied chat/history.
- `POST /attachments` stages validated bytes under an opaque generated ID.
  `POST /conversations/{id}/runs {text,attachment_ids?}` consumes at most four
  distinct ready IDs owned by that conversation, attaching before prompt submit
  under the send lock. No upload action executes a file or chooses a Studio path.

Files are bounded to 10 MiB each (or a lower configured limit). Staging, quotas,
MIME checks, expiration and native photo/camera/dictation behavior are detailed in
[Attachments and voice](ATTACHMENTS_AND_VOICE.md). A staged artifact has no run ID
until submit. Canonical upload/run paths retain the native bot profile boundary.

## vNext Phase 1 contract additions

These additions are development behavior on the Phase 1 branch, not a modified
public v0.1.0 release. Existing endpoints remain compatible.

| Method/path | Request | Response |
|---|---|---|
| POST /bots/{id}/conversations | `{title?,model?,provider?,reasoning_effort?,workspace?}` | 201 independent native-profile Conversation with `bot_id` |
| POST /captures/uploads | `{name,content_type,content_base64}` | 201 `{upload_id,name,content_type,size}`; accepts `audio/mp4` |
| POST /captures | `{client_capture_id,created_at,kind,text,attachment_ids?,context?}` | 201 `{capture_id,stored_at}` only after durable persistence |
| GET /commands/{id} | UUID from this device's command | `{state,result?}`; missing receipt is `not_received`, never dispatches |

Features advertise `botThreads` and `captures`. B1 permits creation-time
workspace IDs from the configured allowlist. Native Agent sessions appear in
`GET /conversations` and its Hermes-backed search; canonical `Bot Chat` stays
separate. Capture context permits `thread_id`, `agent_id`, `tag` (strings) and
`transcribed_on_device` (Boolean). Capture bytes never undergo summarization or
normalization. A device-scoped capture ID rejects changed content.

Only `/captures` and `/captures/uploads` may safely recover an interrupted
receipt with the exact original key/body; no Ask/control command gains that
exception. `GET /commands/{id}` requires read access and rejects another device's
receipt. Talaria uses it to distinguish a recorded result from pending or
uncertain execution, and requires an explicit tap for any permitted Ask retry.

Kanban list rows include `supported_targets`; review includes `done`, `ready` and
`todo` where the audited upstream permits them. Running work still requires
reclaim. A completion summary is part of the original PATCH. A note on another
transition is preserved as a comment before the PATCH (two non-atomic writes).
Optional clarification `recommended`, `default` and `on_timeout` are observational
metadata; the bridge does not fabricate a choice or postpone a deadline.
