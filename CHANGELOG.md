# Changelog

The entry below is the original release-preparation snapshot. Current installation
supports [Xcode](docs/XCODE_INSTALL.md) and [SideStore](docs/SIDESTORE_USER_GUIDE.md);
later public-ID phone validation is recorded in [release readiness](docs/RELEASE_READINESS.md).
The published v0.1.0 release artifacts remain unchanged.

## 0.1.0 — prepared prerelease (2026-10-05)

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

Source is MIT-licensed with third-party notices. This is release preparation,
not a published GitHub release or tag.
