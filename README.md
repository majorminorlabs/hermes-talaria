# Talaria

Talaria is MAJOR//MINOR's native iPhone companion for Hermes running on your Mac. Hermes runs
the agents and keeps their records; Talaria provides chat, bots, tasks and status
through a private authenticated bridge.

**v0.1.0 is an early personal-install release.** It is not available on the App
Store. Its permanent public IPA bundle identifier is `xyz.majorminor.talaria`.
Hermes remains the backend; SideStore signs the IPA for your own Apple Account.

```text
Talaria on iPhone → private Tailscale HTTPS → hermes-mobile-bridge → Hermes on Mac
```

## What works

- Persistent conversations, streaming replies, tool/activity history, stop and steer.
- Hermes Bot Mode: dynamic discovery, canonical writable bot chats, create/edit,
  duplicate and hide. Native Hermes profiles remain the source of truth.
- Tasks, routines, configured Kanban boards, usage and current run status.
- Files, Photo Library and new Camera captures with attachment previews.
- Native speech-to-text into the editable composer; microphone audio stays out
  of the Hermes bridge.
- Reconnect/replay, foreground reconciliation and cached last-known state offline.
- Research Terminal retrieval/search when the host skill and credentials are configured.
- Talaria branding, light/dark appearances and accessible Markdown tables.

Features are capability-gated by the host. Dangerous tool approvals remain
Studio-only because the audited Hermes protocol cannot safely target them.

## Requirements

- macOS host with Python 3.11+ and an existing, prepared Hermes installation.
- Full Bot Mode/media support was tested against Hermes commit
  `4bb9e57bfde8a0affb5553eff13ed6e1f14147f1`. The bridge also supports the audited
  legacy `2a4c9afd7bd` contract with fewer capabilities; arbitrary newer versions
  are not automatically trusted.
- Tailscale on Mac and iPhone, MagicDNS/HTTPS and an access policy permitting
  the phone to reach the host on TCP 443. Serve stays private; Funnel is unused.
- iOS 18+, Xcode 26+ for development, and your own Apple signing identity for
  personal installation. SideStore can re-sign the unsigned IPA.

## Install

Start with [installation](docs/INSTALL.md). It covers the existing Hermes
requirement, bridge setup, HTTPS, private token creation and host pairing.
[Studio setup](docs/STUDIO_SETUP.md) covers service ownership, restart and backup;
the [SideStore user guide](docs/SIDESTORE_USER_GUIDE.md) covers device installation,
official SideStore installation and weekly refresh. Legacy exact-ID cases are
covered separately in that guide.

For the full tested host feature set, a fresh bridge installation uses:

```sh
git clone <repository-url> talaria
cd talaria
./scripts/install-bridge.sh --bot-management --bot-chat --bot-mode --board default
./scripts/configure-tailscale.sh
./scripts/status-bridge.sh
./scripts/pairing-token.sh --name iPhone
```

Enter the URL printed by the HTTPS setup helper and the privately displayed
mobile token in **Talaria → More → Hosts → Add Host**. Tokens are device-only
Keychain items. Hermes/provider/Research Terminal credentials stay on the Mac.
The installer does not install Hermes or replace existing gateways.

## Develop and test

Open `Hermes.xcodeproj`, select the **Hermes** scheme and an iPhone simulator.
The Xcode project/targets retain technical Hermes names. Normal launch uses the
Studio bridge; explicit Simulation mode and test fixtures are separate.

```sh
xcodebuild -project Hermes.xcodeproj -scheme Hermes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO test
cd hermes-mobile-bridge
python3 -m venv .venv
.venv/bin/python -m pip install -e '.[test]'
.venv/bin/python -m pytest -q
```

Personal signing belongs in ignored `Signing.local.xcconfig`; copy
`Config/Signing.example.xcconfig` and set your Team locally. The current shared build configuration and release artifacts contain no personal
Team, certificate or provisioning material. Public distribution uses a separate
fresh-root repository; see [public release handoff](docs/PUBLIC_RELEASE_HANDOFF.md).

## Documentation and limits

- [Release notes](CHANGELOG.md), [packaging](RELEASE.md) and
  [release readiness](docs/RELEASE_READINESS.md).
- [Troubleshooting](docs/TROUBLESHOOTING.md).
- [Bot management](BOT_MANAGEMENT.md), [attachments and voice](ATTACHMENTS_AND_VOICE.md).
- [Design](TALARIA_DESIGN.md), [UI architecture](UI_ARCHITECTURE.md),
  [integration points](INTEGRATION_POINTS.md) and [bridge contract](BRIDGE_API.md).
- [Physical acceptance](PHYSICAL_DEVICE_TEST_REPORT.md) and
  [post-design regression evidence](TALARIA_REGRESSION_VALIDATION.md).

No APNs delivery or guaranteed execution while iOS suspends the app. The Mac must
be awake, logged in and reachable on the tailnet. Some inventories/settings remain
unavailable, and independent native clients can conflict with live transport
ownership. Free Personal Team provisioning expires after seven days; refresh weekly
in SideStore. New SideStore installs use official SideStore with its default Team-ID suffix.
Only existing installs kept at an unsuffixed identifier need the advanced SideStore patch/workaround; see the [SideStore user guide](docs/SIDESTORE_USER_GUIDE.md).

## License

[MIT](LICENSE). Third-party components keep their own licenses; see
[notices](THIRD_PARTY_NOTICES.md). Nothing is pushed, tagged or published by the
release scripts.

## Screenshots

Simulator screenshots with fictional demonstration bots; no live account data.

<img src="docs/images/bots.png" alt="Talaria Bots" width="260"> <img src="docs/images/bot-detail.png" alt="Talaria bot detail" width="260">

## Start here

1. [Install and pair](docs/INSTALL.md): Mac service, Tailscale, iPhone installation and host enrollment.
2. [Use Talaria](docs/USING_TALARIA.md): chat, bots, media, dictation, tasks and research.
3. [Install, refresh and update with SideStore](docs/SIDESTORE_USER_GUIDE.md) or [diagnose a problem](docs/TROUBLESHOOTING.md).
