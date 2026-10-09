# Use Talaria

[Install and pair](INSTALL.md) first. Keep Tailscale connected and the Mac awake,
logged in and reachable. This guide describes current 0.2.1 source; the v0.1.0 IPA
still has the earlier interface.

## Now, Threads, Agents and Studio

**Now** shows Needs You, Working, Done and Next Up. Needs You includes supported
clarifications, task reviews, routine interventions and uncertain Outbox commands.
Answer or use supported task transitions; snooze a request or defer it to your desk.
Hermes command approvals offer Approve once, Approve for session and Deny, each tied
to the exact request. Swipe a pending approval on Now to Approve once or Deny.
Requires Hermes server-request approvals (4bb9e57 or newer); older Hermes shows
“Approve on your Mac.” If the Mac answers first or Hermes times out, a stale tap
shows “No longer pending” and refreshes the card. Deadlines appear only when
Hermes reports them. Lock screen and notification approvals are not included. Review send-back notes and transitions are separate upstream operations.

**Threads** contains conversation and observable work history. Search locally and,
while connected, on Hermes. Filter by Agent/source, Active, Needs You or Unread;
pin, mark read/unread and archive supported conversations. Open a thread to see
streaming messages, collapsed steps, artifacts and results. Use follow-up, steer
and confirmed Stop controls when supported. Unknown outcomes and disconnected
last-known state are distinct; reconnect before deciding whether to repeat work.

**Agents** represents native Hermes bots/profiles. Open an Agent for current work,
recent threads, configuration and model controls. **Ask** creates an independent
thread for that Agent; the underlying canonical Bot Chat remains intact. Create,
edit, duplicate and hide are capability-gated. Hide preserves history; unhide on
Hermes Desktop. Model defaults affect future threads. Revert checks the server's
current value first; it will not overwrite another device's change. Session settings
are fixed at creation; reasoning is displayed only when the runtime reports it.
Real routine pause/resume is available; pausing an Agent is not.

Tap the Talaria mark to open **Studio** for hosts, connection, settings, usage and
other supported tools. **Studio → Hosts → Add Host** pairs with a private HTTPS
URL and scoped bridge token, stored in Keychain. Provider keys stay on the Mac.
Configured **Board** is reachable through Threads filters; Scheduled and Outbox
are secondary destinations. The old Home/Chat/Bots/Tasks/More tabs are replaced.

## Ask and routing

Tap global **Ask** to start work from any main tab. **Auto** means Hermes, not an
LLM router. Explicit Agent names/aliases resolve deterministically; ambiguous
matches require your choice. Inspect the destination before sending. Supported
provider/model, reasoning and project overrides apply only when creating the thread.
Send returns to your prior screen with an **Open** toast.

When offline, Ask is durable in **Outbox** and requires **Send now** after reconnect.
An interrupted delivery becomes uncertain: use **Check** to inspect the bridge
receipt. A confirmed command is not repeated. Only a rejected/not-received outcome
makes explicit sending available again; unresolved outcomes need checking on the Mac.

## Capture and attachments

**Capture** stores a note, idea, task label, link, photo, file or voice record.
Its kind does not execute a task. Text is preserved exactly; context and attachments
are separate metadata. Plain links are not fetched. Files, Photo Library and Camera
use native pickers; camera and permissions need a physical device.

**Saved on iPhone** means local persistence. Captures survive relaunch and sync on
reconnect; **Saved to Hermes** requires the bridge's stable-ID acknowledgement.
Older bridges without Capture capability retain them locally. Use Outbox to review
pending captures and errors. Update the bridge from current source for B1/B2 support.

Capture stores dated UTF-8 Markdown, metadata sidecars and media in the bridge's
private inbox, separate from Kanban and Obsidian. Text is limited to 200 KB;
attachments to four at 10 MiB each; default media quota is 256 MiB per device.
Conversation attachments have the same four-file/10 MiB limits. Supported images,
PDF and text/code files get previews where the host supports them; PDF previews
need host Poppler. Review attachment previews before sending.

## Voice

Hold global **Ask** to speak. Release sends the recognized text to the displayed
destination; slide **down** to lock, **left** to cancel. A locked hold uses **Send**
when ready. Recording has a 60-second fuse. A short/empty recording is rejected.
Editable Ask dictation can show a 1.5-second review before automatic sending unless
**Review voice before sending** is enabled. Held Ask uses send-on-release behavior.

Voice Capture and clarification answers require explicit confirmation. Capture
sends the reviewed transcript and mono M4A recording; ordinary dictation and voice
Ask send text without microphone audio. Speech recognition prefers on-device
processing; Apple's network recognition may be used for unsupported devices/languages.
No voice call, spoken response or TTS is provided.

## Live Activity and reconnect

One aggregate Activity shows observed running, needs-input and blocked work on
Lock Screen/Dynamic Island. Completed and uncertain runs are excluded from the
active count. Rows can open Threads; there are no remote approve/Stop actions.
Production snapshots become stale after 60 seconds and do not imply completion
on disconnect. App suspension may stop updates; there is no APNs/background delivery.
On reopen Talaria reconciles canonical snapshots and replays retained events.

## Optional research, signing and updates

Ask the host's Research Orchestrator a read-only retrieval question when its
Research Terminal skill/credentials are configured. Credentials stay on the Mac;
see [Research Terminal setup](RESEARCH_TERMINAL_SETUP.md).

Update the bridge separately with [Studio setup](STUDIO_SETUP.md). Xcode builds
keep the installed ID and Team; free signing needs rebuild/reinstall before expiry.
SideStore: Tailscale off → LocalDevVPN on → Refresh → verify the renewed signing
period → LocalDevVPN off → Tailscale on. The existing published IPA remains 0.1.0;
current source features require a current Xcode build. Do not uninstall for routine
updates. A changed ID creates a separate container and Keychain identity.

See [privacy](PRIVACY_SECURITY.md) and [validation boundaries](RELEASE_READINESS.md).
