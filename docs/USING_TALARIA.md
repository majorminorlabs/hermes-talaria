# Use Talaria

Complete [installation and pairing](INSTALL.md) first. The Mac must be awake,
logged in and connected to your tailnet. On iPhone, keep Tailscale connected.

## Confirm your connection

Open **Home**. The selected host should report both the bridge and Hermes as
available. If you have multiple hosts, select the intended one before starting
work. **More → Saved Hosts** manages saved connections. A pairing error requires a
valid mobile bridge token; provider keys and Research Terminal tokens never
belong in the phone's host form. See [troubleshooting](TROUBLESHOOTING.md).

## Chat

1. Open **Chat** and select an existing conversation, or use **+** for a new chat.
2. Choose the host/profile and any model options the host offers.
3. Type in the composer and tap Send. Read the streaming response and tool activity.
4. During a run, use Stop to interrupt it or the steering control to provide
   additional instructions. Dangerous tool approvals must be handled in Studio; Talaria cannot safely target them.

Returning to an existing conversation preserves its identity. After a connection
interruption, reopen it and let Talaria reconcile the run before submitting
another request. An uncertain delivery is shown for review rather than silently
resent. Offline views show last-known data; they cannot run Hermes offline.

## Bots

Open **Bots** to see the real bots discovered from Hermes. Tap a bot for its
configuration, then **Chat** to open its canonical shared conversation.

To create one, tap **+**, enter Name and description, optionally choose a host-
provided Provider/Model, add SOUL instructions and select Skills. Toolsets and
MCP server selections appear only when the host supports them. Tap **Create**.
Leaving the provider on **Hermes default** uses the default profile's model.
The new bot appears after Hermes confirms and Talaria reloads the inventory.

To edit, open the bot → **Edit**, change supported fields and tap **Save**.
Some model changes require confirmation. Verify the reloaded detail; changes
apply to the next run. **Duplicate** creates a separate identity. **Hide** asks
for confirmation and removes the bot from the visible list while preserving its
canonical chat/history in Hermes. Unhide from Hermes Desktop. Talaria does not
provide hard deletion. Missing controls mean the host does not offer that capability.

## Files, photos and camera

In a writable conversation, tap the attachment button beside the composer:

- **Files:** choose a document from the native Files picker.
- **Photo Library:** choose one or more images.
- **Camera:** grant access, take a photo, review it and select **Use Photo**.

Review the attachment chips/previews; remove an unwanted item before sending.
Add a short question describing what Hermes should do with the attachment,
then Send. Uploads are tied to that conversation. Supported types include
images, PDF, plain text/Markdown, JSON, CSV and common code files, with a
**10 MiB limit per file and up to four attachments per message**. Permission
denials show guidance; enable access in iOS Settings if you choose. Camera
capture requires a physical camera. See [troubleshooting](TROUBLESHOOTING.md).

## Dictation

Tap the microphone in the composer. Grant microphone and speech recognition
access when prompted, then speak. Partial transcription appears in the normal
text composer. Tap Stop when finished; edit the final words and tap Send.
Cancel discards the current recognition session. This is speech-to-text, not a
voice call: Talaria does not upload microphone audio to the bridge. It prefers
on-device recognition when supported; Apple's recognizer may use its network
service for other device/language combinations.

## Tasks and routines

Open **Tasks** for the host's jobs, routines and Kanban board. Use the controls
Hermes exposes for that item. Destructive or unavailable operations show
confirmation or an explanation. Refresh after a change to verify the result.
Boards must be explicitly authorized by the Studio installer.

## Research Terminal

Research Terminal is optional and configured on the Mac separately. Select
**Bots → Research Orchestrator → Chat** and ask a read-only question such as
“Search existing Research Terminal records for retrieval; do not start a new
research run.” The host needs the installed `research-terminal` skill and its
owner-only credential file. No Research Terminal credential is entered on iPhone.
See [Research Terminal setup](RESEARCH_TERMINAL_SETUP.md).

## Updates and background behavior

Use the update/signing method you installed with:

- **Xcode:** retain your installed bundle ID and Team, update the source checkout,
  then build/run again on the same iPhone. Free Personal Team signing needs a
  rebuild/reinstall before seven-day expiry; paid signing follows the actual
  development profile's expiration. See [Xcode installation](XCODE_INSTALL.md).
- **SideStore:** with free-account signing, refresh before expiry: Tailscale off →
  LocalDevVPN on (Wi-Fi) → **My Apps → Refresh All** → verify the renewed signing
  period → LocalDevVPN off → Tailscale on → confirm a fresh Talaria reply. To update
  app code, import the new IPA with the same identity and Team. See the
  [SideStore user guide](SIDESTORE_USER_GUIDE.md) for evidence and limits.

LocalDevVPN serves SideStore installation/refresh only; normal Talaria use needs
Tailscale. Do not delete an app for a routine update. Changing its bundle ID creates
a separate app whose local preferences/container and Keychain state do not
transfer automatically; a changed signing Team may also require re-pairing.

There is no APNs push delivery. While suspended, iOS may pause the connection;
opening Talaria replays retained events and reconciles the conversation. Avoid
expecting continuous background monitoring. Personal/free-account signing
expires after seven days unless refreshed.
