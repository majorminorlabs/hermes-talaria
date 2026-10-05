# Talaria physical-device acceptance

> Historical device evidence. Legacy development identifier: `com.dippo.hermes`.
> The public release now uses `xyz.majorminor.talaria`. These observations concern
> the existing legacy installation; they do not validate the new public identity.
> That physical installation is preserved untouched during public release preparation.

Updated 2026-10-04. Talaria `0.1.0` / build `1`, bundle `com.dippo.hermes`.
Tested on iPhone 15 Pro Max / iOS 26.6.2 with Hermes
`4bb9e57bfde8a0affb5553eff13ed6e1f14147f1`.

physical_device_validation: LEGACY_PASS
sidestore_update_validation: PENDING

## Verified on the actual phone

- Signed Xcode installation over the existing app, without uninstalling or
  removing pairing/preferences. Host authentication and canonical chats survived.
- Research Orchestrator skill invocation, authenticated PostgreSQL search,
  real existing corpus results, visible rendering and relaunch persistence.
- Native bot creation, description/SOUL editing, dynamic discovery, writable
  canonical chat and background/relaunch. Hide retained the canonical history.
- Files selection/preview/send and exact harmless marker retrieval, selected
  Photo Library image and a new Camera capture received by Hermes.
- Native microphone/speech permissions, on-device partial dictation, stop/cancel,
  editing and normal text send. No audio upload occurred.
- Background active run and foreground reconciliation, with one assistant reply
  and one attachment. Wi-Fi through private Tailscale HTTPS worked.
- Post-design Show All skills, ordinary chat, normal/accessibility Markdown tables,
  Management Hide, Files/dictation and Talaria icon/display name.

The latest post-design complete Swift suite passed 57 unit/integration and 12 UI
checks, with 21 explicit opt-in skips and no failures; affected follow-up checks
also passed. Details are in BOT_MODE_VALIDATION.md,
ATTACHMENTS_AND_VOICE.md and TALARIA_REGRESSION_VALIDATION.md. Historical gates
in those append-only evidence sections are superseded by their completed results.
Private result bundles/screenshots remain outside the repository and packages.

## Remaining separate gates

SideStore is not installed on the connected phone. Its update/re-sign workflow,
Keychain access after re-signing, LocalDevVPN/Tailscale switching and refresh have
not been exercised. Cellular was not repeated. No full machine reboot/login test
is claimed. Successful Xcode updates or an unsigned IPA do not prove SideStore
update preservation. Do not uninstall Talaria for that test.
