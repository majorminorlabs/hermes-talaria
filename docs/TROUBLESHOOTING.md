# Troubleshooting Talaria

- **Cannot reach the Mac:** keep the host awake/logged in, connect Tailscale on
  both devices, check MagicDNS/access to TCP 443 and `scripts/status-bridge.sh`.
  Use the exact HTTPS hostname printed by setup, not loopback or HTTP.
- **Pairing required:** enter the mobile credential through Add Host/Pair Again.
  Hermes/provider tokens are not substitutes. Revoke a leaked device credential
  on the Studio; never paste it into issue reports.
- **Hermes unavailable:** bridge health and Hermes health are separate. Check
  `status-bridge.sh` and restart the owned service; avoid a second backend on the
  same port or another live-client owner for its chats.
- **Unknown command outcome:** inspect canonical state before trying again.
  Talaria never automatically replays a mutation after a lost acknowledgement.
- **Bot options loading:** let native detail finish; reconnect or use Retry on
  the sheet. Editing reads the confirmed SOUL/options rather than a roster summary.
- **File rejected:** select a supported file up to 10 MiB, at most four per
  message; see ATTACHMENTS_AND_VOICE.md. No Studio destination path is accepted.
- **Camera/dictation denied:** enable the relevant permission in iOS Settings
  if you choose. On-device recognition depends on device/language; otherwise
  Apple's network recognizer is used. No dictation audio enters the bridge.
- **Xcode signing / bundle-ID error:** use your own Team and a unique identifier
  it can register. Free Personal Team signing is supported; paid membership is
  not required. See [Xcode signing troubleshooting](XCODE_INSTALL.md#common-signing-problems).
- **App expired:** use the method you installed with: refresh with SideStore or
  rebuild/reinstall with Xcode and your own Team.
  Preserve the bundle ID and update in place; do not delete the app. A change
  of signing team/access group can require bridge re-pairing.
- **SideStore install/refresh cannot reach device services:** turn Tailscale off,
  connect LocalDevVPN on Wi-Fi and retry. Afterwards turn LocalDevVPN off and
  Tailscale on for normal Talaria connectivity.
- **Maximum installed free-profile apps:** SideStore counts toward the three-app
  limit. Remove only an approved unneeded installed app; stale App-ID registrations
  are a separate limit and can expire naturally. See
  [account limits](SIDESTORE_USER_GUIDE.md#free-account-capacity-and-app-ids).

## Advanced legacy or exact-ID troubleshooting

- **SideStore shows 7 days but Talaria still expires:** your Talaria is installed
  at an unsuffixed identifier (advanced/legacy case) and SideStore is an unpatched build. See the
  [SideStore user guide](SIDESTORE_USER_GUIDE.md#advanced-legacy-or-exact-id-installations).

Issue reports should contain app/bridge versions, a redacted error code and steps.
Exclude tokens, provider credentials, private hostnames, device IDs, personal
paths, conversations, attachments and unredacted screenshots/logs.
