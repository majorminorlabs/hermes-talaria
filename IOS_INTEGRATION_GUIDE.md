> Historical implementation/design reference. For current 0.2.0 navigation,
> Capture/voice semantics and capability boundaries, see [Use Talaria](docs/USING_TALARIA.md)
> and [current release notes](CHANGELOG.md). Agents are underlying Hermes bots/profiles.

# iOS integration with Hermes mobile bridge

The native Swift client is implemented in Hermes/Services/Bridge and composed by AppEnvironment.live(). Its completed service mapping is [INTEGRATION_POINTS.md](INTEGRATION_POINTS.md). The client uses [BRIDGE_API.md](BRIDGE_API.md), not the upstream desktop RPC protocol. Studio executes everything.

## Connection and authentication

Use the Studio's deliberately configured HTTPS tailnet hostname. The bridge defaults to loopback; configure a Tailscale HTTPS reverse proxy or direct TLS before real-phone testing. Native URLSession requests carry the mobile bearer in Authorization. Do not disable certificate validation or add an arbitrary cleartext-network exception. Tailscale reachability does not replace this bearer credential.

Store the mobile token in Keychain, preferably a device-only item with access after first unlock when background notifications/networking are needed. Keep the base URL/device label separately. Never store the token in UserDefaults, cached JSON, analytics, URL query strings or crash logs. Hermes/provider credentials never belong on iPhone. A 401 requires deliberate reprovisioning; do not loop retries or request an upstream token.

Initial connection:

1. GET capabilities. Check API version, authorized profiles/scopes, health, support flags, workspace display IDs and journal epoch.
2. GET Home for one aggregate snapshot. Cache its snapshot_cursor and each run's snapshot_cursor.
3. Open one authenticated GET events/stream?after=<cursor>. This is an SSE response, not a WebSocket upgrade.
4. Hydrate the selected conversation/tasks from their detail endpoints. Keep resource snapshots and stream application serialized in one state actor.
5. Show Studio unreachable, bridge authentication failure, and Hermes offline as separate states.

Use ordinary HTTP JSON requests for actions. Every new user action receives a UUID Idempotency-Key saved with method/path/query/body before sending. Reuse that exact UUID/payload on a transport retry. If command_uncertain is returned, inspect Home/run/history rather than generating another UUID and repeating it. A recorded response can be safely fetched by repeating the same request. Backend changes or stream reconnect must never cause prompt/steering/task-trigger resubmission.

The bridge keeps upstream connections alive when iOS suspends; iPhone reconnect changes only a subscription. Do not send stop on view disappearance, app backgrounding or stream cancellation.

## Expected service boundaries

These are interface responsibilities, not Swift implementations:

| Service | Responsibility |
|---|---|
| StudioConnectionService | URL/token access, capabilities/health, authenticated URLSession, connection state and retry policy |
| BridgeEventService | One SSE parser, durable cursor, polling replay, gap/epoch recovery, sequence deduplication |
| ConversationService | List/search/create/inspect/resume/rename/archive/delete; workspace/model/reasoning creation options |
| RunService | Start/status/list/stop/steer/explicit retry; run projection keyed by bridge run ID |
| AttentionService | Context-rich attention list, capability-gated exact clarification and approval responses |
| ScheduledWorkService | Cron list/detail/create/edit/enable/disable/trigger/delete and canonical recent results |
| KanbanService | Board/task/detail/assignment/dependencies/heartbeat/attempts/transitions/reclaim/reassign |
| InventoryService | Profiles/SOUL, skills/tools/MCP/models, host metrics, memory metadata and usage |
| ArtifactService | Bounded uploads, known artifact metadata/download, task-scoped attachments |

Conversation = persistent interaction; Run = one observed execution; Task = canonical Kanban card or cron routine. Ordinary chat run.task_id is null. A Kanban attempt integer is not a bridge run UUID. A profile is not proof of a first-class bot.

Use opaque string IDs throughout. Model event payload/content/tool result fields as JSON values rather than assuming one fixed tool schema. Bridge observation timestamps decode as Unix seconds; Hermes schedule ISO strings should be handled separately. Preserve unknown event types for forward compatibility without crashing.

## Streaming/replay algorithm

Use URLSession's incremental bytes/lines for SSE. Frames end at a blank line; collect data lines, event name and optional id. Normal events contain complete Event JSON. Treat stream.checkpoint as cursor advancement/heartbeat and stream.resync_required as a recovery instruction. Do not assume every frame has an id.

Persist an event cursor only **after** its changes have been applied durably. Cursor identifies journal epoch and global sequence. Deduplicate with epoch/seq, even if two mobile connections briefly overlap. Per-run sequence is monotonic but not contiguous; other runs/profiles use the same counter.

Reconnection:

1. Back off with jitter, for example 0.5/1/2/4/8 seconds capped around 15 seconds. Cancel retries on revoked credentials. Distinguish tailnet/network loss from an upstream-offline event.
2. Retry the stream with the last applied cursor or Last-Event-ID. Polling GET events?after=&limit=100 is equivalent for catch-up; continue pages while has_more.
3. Apply assistant.delta by appending to that run's partial projection. Assistant.completed replaces its partial text. Terminal run events update lifecycle; they do not add a second message.
4. On 409 resync_required, changed epoch or stream.resync_required, hydrate Home, relevant conversations and tasks; use the returned snapshot watermarks. Resume the event stream from that snapshot boundary.
5. A hydrated Run includes snapshot_cursor. Skip run events at/below its own snapshot sequence even when replaying from Home's earlier global watermark. State/task events are upserts and can safely reconcile an overlapping snapshot.
6. On coverage_gap, hydrate canonical history; do not infer that lost tool events or approvals were replayed. Unknown outcome stays unknown until supported evidence/operator handling.

Canonical transcript refresh **replaces** the cached transcript. Overlay active run projections separately. When final history contains the completed turn, replace that run's transient bubble rather than appending its final text again. Rendering chat text from events and history as two independent append-only lists would duplicate messages.

Opening a stream without after starts at the current watermark; use a saved/snapshot cursor to recover earlier events. Journal retention is intentionally bounded. A backgrounded phone cannot rely on an indefinitely running socket; replay and snapshots are the recovery path.

## Local cache and ownership

Cache authorized profile/workspace metadata, conversation summaries/messages, run projections, task/job snapshots, artifact metadata and the applied cursor in a private app store. Keep tokens out. A small SQLite/Core Data/SwiftData cache can update projection and cursor together. Treat cached state as a display projection; Hermes owns conversation/task/job data and the bridge owns observation/auth/command metadata.

Keep outbound command receipts pending until an acknowledgement/definitive error. On restart, show uncertain commands requiring inspection. Do not optimistically display run completion from an HTTP response to stop. Do not infer provider cost when absent; retain the scope/source on cumulative usage.

Artifacts are downloaded by ID into app-private storage; validate byte/type limits and render filenames safely. Do not request Studio paths or implement a remote filesystem picker. Workspace selection uses capability-provided display IDs. Files uploaded through the bridge are attached internally to the next prompt; images/PDF handling also remains Studio-side.

## Example flows

**New chat:** POST conversations?profile=default with model/provider/reasoning/workspace choices → retain conversation ID → optional POST attachments → POST conversations/{id}/runs with text and a new command UUID → keep returned run ID → stream events keyed to it. Empty conversations may initially be drafts; the bridge normalizes that window.

**Resume:** list/search conversations → GET detail → explicit resume if desired → submit a new run when no unresolved execution exists. Bridge restart can reattach its previously owned running handle. Another desktop/messaging client may have ownership the backend cannot fully observe; surface conflicts/coverage limitations. Never use Hermes short live IDs directly.

**Stop:** POST runs/{id}/stop → show stop requested → wait for run.cancelled/failed/completed evidence. The bridge handles late pending prompts after the stop. Tool effects may already have happened.

**Steer:** POST runs/{id}/steer → queued is acknowledged, consumed=false remains truthful. Continue watching the same run. This is not a new conversation message/run submission.

**Attention:** show run/session context, command/description/patterns, age and limitation. Disable dangerous approve/deny controls whenever can_respond=false; legacy FIFO approvals remain disabled. Exact clarification requests accept `answer`; exact approval server requests accept `choice` from the offered choices. Omit permanent approval on the phone. A `409 stale_attention` shows "No longer pending" and refreshes attention. Do not convert a disabled denial into a FIFO call. Offer whole-run stop separately where controls.stop is available.

**Retry:** failed/cancelled run → explicit user retry creates a new run with parent_run_id. Unknown cannot be retried automatically. Retry does not reverse earlier tool effects.

**Scheduled work:** fetch cron list/detail → edits go to canonical Hermes job → enable/disable dedicated actions → run-now means queued due time, not execution_started. Refresh job.last_status/last_error and recent_conversations after the Hermes scheduler executes. No iPhone scheduler is needed.

**Kanban:** fetch configured board → select task ID → detail contains dependency links, attempt outcomes, diagnostics and worker heartbeat → PATCH a supported target or assignment separately → refresh canonical detail. Move a running worker through reclaim; use reassign with explicit reclaim_first where appropriate. Do not send a synthetic task state failed or complete; source done maps to display complete.

## Future notifications

Notifications are not implemented. A later Studio-side consumer can read the same durable event journal and generate deduplicated notification intents for approval attention, blocked/failed work, completion and due-job outcomes. Use event cursor/resource ID as the dedup key. Push payloads should contain opaque IDs/minimal state, not tool output, prompts or credentials.

APNs requires separate deliberate app/device registration and a Studio credential or trusted delivery relay. Tailscale alone does not wake a suspended iPhone with application events. On notification open, reconnect and fetch canonical state; a push is a hint, not authoritative run state. Disabled dangerous approvals remain disabled in notification actions.
