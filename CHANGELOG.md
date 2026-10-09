# Changelog

The entry below is the original release-preparation snapshot. Current installation
supports [Xcode](docs/XCODE_INSTALL.md) and [SideStore](docs/SIDESTORE_USER_GUIDE.md);
later public-ID phone validation is recorded in [release readiness](docs/RELEASE_READINESS.md).
The published v0.1.0 release artifacts remain unchanged.

## 0.2.1 — in-app Hermes command approvals (2026-10-09)

Approve once, approve for the session, or deny the exact Hermes request. Now
provides Approve/Deny swipe actions. Stale taps safely show “No longer pending.”
Requires Hermes server-request approvals (4bb9e57 or newer), with Mac fallback
for older versions. Bridge capability detection and the audited `reconcile-run`
operator command are included. Lock screen/notification approvals are excluded
by design. App and bridge version 0.2.1; app build 3.

## Unreleased

- Now shows its empty Needs You message once; the status line contains active counts.
- Held voice Ask feedback attaches to the microphone button that started recording.
- Pinned Needs You cards stack above the conversation composer or read-only footer.
- Xcode installation instructions use the current clone directory, `tools-talaria`.

## 0.2.0 — binary release (2026-10-06)

The v0.2.0 release includes an unsigned IPA, device archive and bridge package.
The existing v0.1.0 tag and artifacts remain unchanged. App/bridge version is 0.2.0;
app and Live Activity build number is 2, with the public bundle identity preserved.

### Work from the phone

Now / Threads / Agents replace the old primary tabs. Now groups Needs You, Working,
Done and upcoming routines; Threads adds search, unread/pin/archive and Agent/source
filters. Thread steps, artifacts, results and supported delegate handoff markers
replace the separate Run Detail shell. Global Ask previews deterministic routing:
Auto selects Hermes; explicit names/aliases select an Agent, with ambiguity resolved
by the user. Independent Agent threads preserve canonical Bot Chats.

### Durable input and control

Capture stores verbatim text, context and media in a local relaunch-safe queue and
syncs to a dedicated private Mac inbox. Voice Capture includes its confirmed
transcript and M4A audio. Offline Asks always require Send now; uncertain commands
use receipt checks without automatic replay. Held voice Ask sends on release,
slides down to lock and left to cancel; Capture/clarifications remain explicit.
Native input regressions cover typed/pasted Agent and host fields.

Agent detail shows real work/recent threads and supported model-default change/
Revert controls. New-thread model/provider, reasoning and project overrides retain
Hermes session scope. Needs You exposes supported clarification deadlines, task
review/send-back and routine interventions, with snooze/desk handoff.

### Bridge, recovery and Live Activity

B1 creates independent Agent sessions. B2 adds device-owned, stable-ID Capture and
media storage with durability/ownership/type/quota checks. Read-only command receipts
resolve uncertain Outbox state. Native Kanban assignments and review notes map to
real backend operations. SSE survives transient health failures and recovers expired
replay cursors through canonical snapshots.

One aggregate Live Activity prioritizes blocked/needs-input/running work, excludes
completed/uncertain runs and opens Threads. App/extension share a local Swift package.
Headers are unified and duplicate thread work-status panels removed.

### Compatibility and limits

Update the bridge from current source; older hosts retain unsupported captures
locally. iOS 18 deployment target and both installation paths remain. The Live
Activity extension derives its ID from TALARIA_APP_BUNDLE_ID; select your own Team
for both targets. No APNs/background guarantee, mid-thread model switching, Agent
pause/reasoning defaults, structured decisions, tracked delegation or TTS. Review
notes plus transitions are non-atomic. Current physical acceptance passed, including owner-confirmed voice and camera.
iOS 18 runtime remains unverified. See [acceptance](docs/PHYSICAL_ACCEPTANCE_v0.2.0.md).

## 0.1.0 — published prerelease (2026-10-05)

### Public identity

Publisher/project: MAJOR//MINOR. Canonical unsigned IPA bundle ID:
`xyz.majorminor.talaria`, version 0.1.0/build 1. Official SideStore's default
Team-ID suffix is the source-derived new-user path. A new public identity is a
separate application from the preserved legacy development install; no migration
or physical installation of this new identity was performed.

### Native Hermes chat

Persistent conversations, canonical history, streamed replies, grouped tool
activity, live status, stop/steer and explicit supported retry. Reconnect uses
retained events plus canonical snapshots, without automatically replaying commands.

### Bot Mode

Dynamic native bot discovery and shared canonical writable chats. Create, edit,
duplicate and hide use Hermes's profile lifecycle. Supported configuration includes
name/description, SOUL, host-provided model/provider, skills, toolsets and MCP
selection. Hide preserves conversation/history; hard delete is unavailable.

### Tasks and status

Current run/host status, routine and cron management, configured Kanban boards,
worker/task metadata, usage and capability-gated inventories.

### Attachments and voice

Files, selected Photos and new Camera captures, composer previews and safe upload
IDs scoped to a conversation. Up to four attachments, 10 MiB each. Native partial
speech recognition populates editable text; dictation uploads no audio to Hermes.

### Talaria design

Talaria display name and winged-sandal icon, light/dark appearance, Desktop bot
faces, readable error summaries and compact tool history. Markdown tables retain
a normal Grid and use stacked heading/value rows at accessibility sizes, avoiding
the confirmed SwiftUI layout freeze.

### Networking and security

Private Tailscale HTTPS, authenticated scoped/revocable mobile tokens, device-only
Keychain storage, owner-only Studio state and guarded per-user launchd services.
Secrets, private host configuration and personal signing are excluded from releases.
Research Terminal search works with PostgreSQL when configured on the host.

### Known limitations

No App Store distribution or APNs push delivery. Private tailnet connectivity and
an awake/logged-in host are required. Remote dangerous approvals, standalone skill
installation and some settings/integrations are unavailable. Host versions are
audited explicitly; independent Desktop clients can take over native live event
ownership. Apple network speech recognition is used when on-device recognition is
unavailable. Free signing expires after seven days. SideStore update-in-place,
data/Keychain preservation and three normal refresh cycles passed on the historical legacy
same-Team installation with the [one-line SideStore patch](docs/sidestore/0001-restore-preferred-bundle-id-team-rule.patch).
The patch is for existing unsuffixed installations; ordinary new users keep
official SideStore and the default suffix. New-ID physical signing/Refresh remains
unverified. See [installation](docs/SIDESTORE.md).

Source is MIT-licensed with third-party notices. The v0.1.0 prerelease was published on 2026-10-05; its artifacts remain unchanged.
