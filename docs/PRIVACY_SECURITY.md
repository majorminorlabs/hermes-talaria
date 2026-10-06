# Privacy and security

Talaria uses private Tailscale HTTPS and an authenticated scoped/revocable bridge
credential. Serve remains private; Funnel is not used. Provider, Hermes and optional
Research Terminal credentials stay on the Mac. The iPhone bridge token uses
device-only Keychain storage. Saved hosts, drafts, cached transcripts and queued
Asks/Captures are local user data, not source files.

Capture is a durable store, not automatic agent execution. The iPhone queue is in
Application Support/TalariaOutbox, protected by iOS file protection. The bridge's
`captures_root` defaults to `<state_dir>/captures`; service installation places it
inside the private Application Support/HermesMobileBridge service root. Device
subdirectories are isolated, directories use 0700 and files 0600. Stable IDs,
exact-byte interrupted-write reconciliation and synchronized files/directories
precede confirmation. Media upload ownership, types, sizes and quotas are checked.

Voice Capture sends a reviewed transcript and M4A audio to your bridge. Ordinary
Ask/dictation sends text. Apple Speech may use network recognition where on-device
recognition is unavailable. Photos/files you select are sent to your configured
host; subsequent provider/tool use depends on Hermes configuration. Plain captured
links are stored without fetching them.

Keep captures, upload stores, databases, logs, host configuration and signing outside
the checkout. Ignore rules are defense in depth for common runtime directories;
a custom `captures_root` inside arbitrary source paths cannot be protected by a
filename rule. Choose an absolute directory outside Git and include it only in
private backups. Fixtures must be synthetic. Inspect screenshots before sharing.

Do not commit `.env` credentials, pairing transfer files, certificates, private keys,
provisioning profiles, signed artifacts or Xcode user state. Revoke an exposed token
and provision a replacement using [pairing](INSTALL.md#pair-and-verify). Review all
unpublished commit trees as well as HEAD before publication. Do not rewrite public
history without an explicit recovery decision if an actual credential was published.

No APNs delivery, background monitoring guarantee or remote dangerous tool approvals.
This is a scoped implementation review, not an independent penetration test.
