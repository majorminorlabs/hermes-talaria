# Talaria v0.2.0

> Current release update: v0.2.1 supports in-app Hermes command approvals when
> Hermes advertises server-request approvals (4bb9e57 or newer). Older Hermes
> retains “Approve on your Mac.” Mac-only approval references below describe
> the earlier design or release.

Talaria 0.2.0 / build 2 brings Now, Threads and Agents to the iPhone, with
independent threads for the same Agent and a global Ask composer that previews
Hermes or explicit Agent routing.

- Hold-to-talk Voice Ask, with release-to-send, lock and cancel gestures.
- Durable text/media Capture and automatic sync; offline Asks require explicit Send now.
- Needs You clarifications, review and Later; unsafe tool approvals remain on the Mac.
- Real streaming/progress, run steering and Stop with truthful incomplete outcomes.
- Supported Agent model-default changes and Revert, plus scoped new-thread options.
- One aggregate Live Activity and connection/replay recovery.

Physical 0.2.0 acceptance passed, including the data-preserving Xcode upgrade,
two independent Agent threads, real Ask/Capture/steering/Stop and owner-confirmed
keyboard/paste, voice and camera. See the [acceptance record](https://github.com/majorminorlabs/tools-talaria/blob/v0.2.0/docs/PHYSICAL_ACCEPTANCE_v0.2.0.md).

Download `Talaria-v0.2.0.ipa` and verify `SHA256SUMS.txt`. The IPA and archive are
unsigned; use your own signing through [SideStore](https://github.com/majorminorlabs/tools-talaria/blob/v0.2.0/docs/SIDESTORE_USER_GUIDE.md)
or [Xcode](https://github.com/majorminorlabs/tools-talaria/blob/v0.2.0/docs/XCODE_INSTALL.md).
Keep your installed app identity and Team stable to preserve local data. The
bridge source package is `hermes-mobile-bridge-v0.2.0.tar.gz`.

This remains a prerelease under the existing project convention. iOS 18 runtime,
stock SideStore/new-account signing and expiry/refresh cases remain unverified.
Live Activity updates have no APNs/background guarantee. Phase 2 features are
not included. v0.1.0 and its artifacts remain available.
