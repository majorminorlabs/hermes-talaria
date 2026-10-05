# Swift ↔ bridge integration

Implemented against `/mobile/v1`, bridge 0.1.0 / API version 1, audited Hermes `4bb9e57bfde8a0affb5553eff13ed6e1f14147f1` (legacy `2a4c9afd7bd` remains supported). Production composition is `AppEnvironment.live()` with one `BridgeHermesClient`; previews, unit/UI fixtures and explicit Simulation retain `MockHermesBackend`. No Swift view talks to Hermes desktop RPC.

## Service mapping

| Swift protocol | Implemented contract | Limits / local ownership |
|---|---|---|
| HermesEventStream | GET `/events/stream?after=`, global ordered SSE; GET `/runs/{id}/events` for timeline hydration | Whole source frame becomes an atomic batch; commit applied snapshots and cursor before ACK. Bounded transport buffering, reconnect/replay, epoch/retention resync. No command replay. |
| HostService | GET `/capabilities`, `/inventory/models`; health in `/home` | Saved URL/name/network are local metadata. Bearer lives exclusively in device-only Keychain. HTTP permitted only for debug simulator loopback. |
| HomeService | GET `/home` | One canonical aggregation request; no independent service fan-out to construct Home. Coverage errors remain attention items. |
| ConversationService | GET/POST `/conversations`, GET/PATCH/DELETE `/conversations/{id}`, POST `/conversations/{id}/runs`; explicit resume uses `/resume` | Existing session send is resumed inside bridge start. Local pin preferences are host-scoped. Delete refuses unresolved work rather than implicitly stopping it. Creation model/reasoning/workspace settings are not edits to a resumed session. |
| RunService | GET `/runs`, `/runs/{id}`, `/runs/{id}/events`; POST `/stop`, `/steer`, `/retry`; GET `/attention`; POST `/attention/{id}/respond` with answer | Durable bridge IDs only. Unknown maps to disconnected, never completed. Per-run `controls` gate buttons. Stop acknowledgement is not terminal cancellation; steering is queued, not proven consumed. |
| ProfileService | GET `/profiles`, `/profiles/{id}`, display-only `/inventory/memory` | Bots are profiles. Bot Mode adds `POST /bots`, `PATCH /bots/{id}`, hide/duplicate actions, and profile-scoped `/bots/inventory`. Safe configuration/SOUL/installed-capability selections are re-read from native Hermes; management requires its separate grant. Desktop Bot Mode uses `/bots` and per-bot details; no rooms or mentions. |
| TaskService | GET/POST `/kanban/tasks?profile=&board=`, GET/PATCH `/kanban/tasks/{id}` | Boards come from discovery. Detail exposes dependencies/activity and conditional `supported_targets`; known dependency guards further restrict ready. Start means queue for Hermes dispatcher, not spawn a run. Canonical task attempts are separate from chat bridge runs. |
| ScheduleService | GET `/cron`; POST `/enable`, `/disable`, `/run-now`; PATCH/DELETE `/cron/{id}` | `runNow` now returns Void: acknowledged due-time update requires an existing scheduler. No invented running execution. Delivery/profile edits are not exposed by the contract. |
| MemoryService | `/inventory/memory` metadata through profile detail; entry list/delete return unsupported | Contents and entry mutations do not exist. Memory-entry UI stays capability-hidden. |
| SkillService | GET `/inventory/skills` | Inventory is read-only here; bot management can select installed skills through the native profile editor. |
| ToolService | GET `/inventory/tools`, `/inventory/mcp` | Configured inventory does not prove external health. MCP endpoints/credentials are never requested/exposed. |
| IntegrationService | Unsupported | No bridge integrations endpoint; capability-hidden. |
| UsageService | GET `/inventory/usage?profile=&days=` | Hermes token totals, daily/model breakdown. Source counts sessions, so labels say sessions. No fabricated run counts, costs or quotas. |
| LogService | Unsupported | No logs endpoint; capability-hidden. Safe local connection/error copy never contains request/credential/URL exception payloads. |
| ArtifactService | GET `/conversations/{id}/artifacts`, `/artifacts/{id}`, `/artifacts/{id}/download` | Authenticated bounded downloads to an opaque temporary directory and Quick Look. No Studio paths or arbitrary filesystem browsing. |
| NotificationService | Existing local notifications | No APNs/device-token endpoint exists. Remote notifications remain future work. |

## Safety and state

- Dangerous approval requests always map to unavailable remotely, with Studio-only explanation and conditional whole-run Stop. No Approve/Deny request is sent. Fresh exact clarifications are a separate composer mode, with optional choice buttons and POST answer; stale prompts fail closed.
- One assistant message ID per observed bridge run (`assistant-{bridgeRunID}`); deltas update its projection, final text replaces it, canonical history replaces the transcript. Imported history retains stable source row IDs. Per-run snapshot cursors prevent replaying older deltas into already hydrated text.
- Every successful source event application writes a single atomic `AppliedBridgeState` containing snapshots, transcript and cursor. Restoring the checkpoint takes precedence over older separate caches. Host scopes have distinct checkpoints and pins; switching cancels the old subscription and rejects stale ACKs/resyncs.
- Commands receive one UUID and a credential-free local receipt before dispatch. No HTTP mutation retry occurs automatically. Unknown outcomes surface `commandUncertain`; pending receipts survive relaunch and never cause resubmission.
- Capabilities are discovered at connection and stream heartbeat, not inferred from a hardcoded Hermes version. Healthy empty capabilities clear previously enabled features. Degraded status retains cached presentation.

## Remaining placeholders

Files/photos/camera upload and native composer dictation are implemented; bot editing uses the native profile lifecycle. Safe artifact download/open is implemented. Memory entries/settings, standalone skill installation, integration status and log access still need additional contracts. APNs is not implemented. Cron and Kanban dispatch must already run on Studio. Physical iPhone installation needs a signing team and a reachable authenticated HTTPS tailnet bridge.

## Writable canonical Bot Chat

`ProfileService.canonicalConversation` POSTs `/bots/{id}/conversation` when
`features.botChat` is available, otherwise reads the legacy existing chat.
One action initializes/opens the actual native-profile `Bot Chat`. The returned
Conversation retains `bot_id`, `bot_profile`, canonical metadata and `read_only`;
no prefix is used to decide send/control permissions. The existing
ConversationView, run APIs, event stream, replay and clarification composer are
reused. Run projections keep the opaque bot profile even when the event envelope
uses the backend source ID for authorization. Foreground refresh reloads all
resources. Main Chat lists canonical resources and opens the same ID as Bots;
legacy read-only aliases remain readable. Hidden/deleted membership disappears
without deleting stored histories. Source, initialization and shared-client
limits are in [BOT_MODE_AUDIT.md](BOT_MODE_AUDIT.md).

## Composer media and bot management

`attachments`/`imageUpload` and `botCreate`/`botEdit`/`botHide`/`botDuplicate`/`botInventory`
are discovered per source. Missing features hide the controls. `/bots/inventory?bot_id=`
reads the selected native profile, including profile-local skills. No provider keys,
base URLs, MCP commands/environments, or arbitrary profile configuration are returned.

Upload IDs are generated by the bridge, scoped to an authorized conversation, and
consumed once while holding its send lock. Upload and prompt requests use separate
idempotency receipts; neither is automatically resent after an uncertain response.
Composer draft bytes never enter persisted transcripts/checkpoints. Confirmed staging
is reused for an explicit retry within the current client; consumed uploads fail closed.

Camera, microphone and Speech Recognition privacy strings are in app build settings.
Photo library selection uses PhotosPicker, not broad library access. Dictation starts
and stops on the phone, supplies partial editable text, and sends no audio to Hermes.
