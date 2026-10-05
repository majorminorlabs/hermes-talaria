# Talaria

**Hermes on your Mac, in your pocket.**

A native iPhone companion for Hermes. Talaria connects securely to your
self-hosted Hermes instance on a Mac through **hermes-mobile-bridge** and
**Tailscale**. Hermes runs the agents and keeps their records; Talaria brings
conversations, bots and tasks to your phone.

[**v0.1.0 prerelease**](https://github.com/majorminorlabs/hermes-talaria/releases/tag/v0.1.0)
· [Install](docs/INSTALL.md) · [User guide](docs/USING_TALARIA.md)
· [MAJOR//MINOR](https://majorminor.xyz)

<p>
  <img src="docs/images/bots.png" alt="Talaria Bots: shared Hermes bots and their current activity" width="240">
  <img src="docs/images/bot-detail.png" alt="Talaria bot detail: chat, configuration and bot management" width="240">
</p>

*Current-interface simulator screenshots with fictional demonstration bots.*

## Features

- **Conversations:** persistent Hermes chats, streamed replies, tool/activity
  history, stop and steer.
- **Bots:** Bot Mode discovery and shared bot chats; create, edit, duplicate and
  hide bots where the host supports those capabilities.
- **Tasks:** routines, configured Kanban boards and current run status.
- **Attachments:** Files, Photos and Camera captures, with previews.
- **Dictation:** native speech-to-text into an editable message composer.
- **Connection recovery:** reconnect/replay, foreground reconciliation and cached
  last-known state while offline.
- **Private remote access:** authenticated bridge traffic over your Tailscale network.

Capabilities depend on the configured Hermes host. Optional Research Terminal
retrieval is also available; see the [user guide](docs/USING_TALARIA.md).

## Architecture

```text
Talaria / iPhone → private Tailscale HTTPS → hermes-mobile-bridge → Hermes / Mac
```

AI and agent workloads run on the Mac. The phone provides a native remote
interface; your Mac must be awake, logged in and reachable. Provider credentials
stay on the Mac, and Talaria stores its scoped bridge token in iPhone Keychain.

## Requirements

- An **iPhone running iOS 18 or newer**.
- A **Mac running Hermes**, with **Python 3.11+** and hermes-mobile-bridge installed.
- **Tailscale on both devices**, with private HTTPS and an access policy permitting
  the phone to reach the bridge.
- **Your own Apple signing**, using either Xcode or SideStore below.

The bridge targets audited Hermes versions; check the
[bridge requirements](docs/INSTALL.md#requirements) before setting up your host.

## Installation

### Xcode / Apple signing

Build from source with **Xcode 26+** and your own Apple Developer Team. A free
Personal Team works for personal-device testing; paid membership is optional.
Free signing needs rebuilding/reinstalling before seven-day expiry.

Follow [Xcode installation](docs/XCODE_INSTALL.md). The project, app target and
scheme are named **Hermes**; the installed app is **Talaria**. Self-builders may
use a unique bundle identifier such as `com.example.talaria`. Changing identity
creates a separate app with its own local state; see the guide for signing details.

### SideStore

Install **Talaria-v0.1.0.ipa** from the
[v0.1.0 release](https://github.com/majorminorlabs/hermes-talaria/releases/tag/v0.1.0)
with official SideStore. Keep its normal Team-ID suffix behavior and refresh
free-account signing before seven-day expiry.

Follow the [SideStore guide](docs/SIDESTORE_USER_GUIDE.md) for import, signing,
verification and weekly refresh.

**LocalDevVPN is for SideStore installation/refresh. Tailscale is for normal
Talaria ↔ Hermes connectivity.** Restore Tailscale after every SideStore operation.

## Bridge setup and pairing

Both installation paths use the same backend. Follow the canonical
[Mac bridge setup](docs/INSTALL.md#mac-bridge-setup), then
[pair and verify](docs/INSTALL.md#pair-and-verify) with your own scoped mobile token.
The installer does not install Hermes or replace your existing gateways.

## Current status

**v0.1.0 prerelease** is early, open-source software for personal installation,
not an App Store release. The published IPA's canonical identity is
`xyz.majorminor.talaria`; self-builders can choose their own ID.

Physical testing covers pairing, normal and bot chat, history, reconnect and
ordinary SideStore Refresh. Stock SideStore and a second Apple Account remain
physically untested; see [validation boundaries](docs/RELEASE_READINESS.md#current-installation-documentation-after-publication).
There is no APNs delivery or guaranteed execution while iOS suspends the app.
Dangerous tool approvals remain on the Mac.

[GitHub Releases](https://github.com/majorminorlabs/hermes-talaria/releases)
· [Troubleshooting](docs/TROUBLESHOOTING.md) · [Release notes](CHANGELOG.md)

## Documentation and contributing

- [Use Talaria](docs/USING_TALARIA.md): conversations, bots, tasks and media.
- [Mac service setup](docs/STUDIO_SETUP.md): service ownership, updates and backup.
- [Develop and test](docs/DEVELOPING.md): build commands and local signing.
- [Bot management](BOT_MANAGEMENT.md) · [Attachments and voice](ATTACHMENTS_AND_VOICE.md).
- [Bridge contract](BRIDGE_API.md) · [UI architecture](UI_ARCHITECTURE.md).

Use [GitHub Issues](https://github.com/majorminorlabs/hermes-talaria/issues) for
bug reports and focused proposals. Include your app/bridge versions and reproduction
steps; remove tokens, private hostnames and personal conversation data.

## License

[MIT](LICENSE), by MAJOR//MINOR. Third-party components retain their own licenses;
see [notices](THIRD_PARTY_NOTICES.md).
