# Install Talaria

Talaria is the native iPhone client for Hermes. Hermes Agent and the mobile bridge run on your Mac; the phone connects to the bridge over your tailnet. The bridge does not replace Hermes and does not connect through SSH.

## Choose an installation method

| Method | Best for | Computer needed to install | Refresh/signing |
| --- | --- | --- | --- |
| Xcode + your Apple Developer Team | Developers using a free Personal Team or paid membership | Mac + Xcode for builds and device installation | Free Personal Team: rebuild/reinstall before seven-day expiry. Paid Team: normal development provisioning; check profile expiration. |
| SideStore | Personal sideloading without maintaining an Xcode workflow | Computer for initial SideStore setup; subsequent imports/refreshes on iPhone | Free-account signing: refresh before seven-day expiry. |

**SideStore is optional.** Either route installs the same Talaria client and needs
this backend:

```text
Hermes on Mac → hermes-mobile-bridge → private Tailscale HTTPS → Talaria on iPhone
```

## Requirements

- A Mac with the audited Hermes installation and its desktop API available to a dedicated local backend.
- macOS, Python 3.11 or newer, and Tailscale signed in to the same tailnet as the iPhone.
- Tailscale MagicDNS and HTTPS enabled for the tailnet. Tailscale Serve also needs the phone-to-Studio connection allowed by the tailnet access policy.
- An iPhone running iOS 18 or newer, and an installation route: Xcode with a signed-in Apple ID for development, or SideStore for repeatable personal-device installs.

Talaria is open source and self-hosted. The canonical project/release bundle ID
is `xyz.majorminor.talaria`, version `0.1.0`. Sign with your own Apple Account/Team;
no publisher certificate or provisioning material is provided.

### Option A: Xcode / Apple Developer

Clone the repository, open **Hermes.xcodeproj**, select the **Hermes** app target
(Talaria) and choose your Team in **Signing & Capabilities**. Use a unique bundle ID
if your Team cannot register the canonical one, connect your iPhone and build/run.
Paid membership is optional for personal-device testing. Follow
[Xcode installation](XCODE_INSTALL.md), then the shared bridge setup below.

### Option B: SideStore

Install official SideStore, configure LocalDevVPN and import the
[published IPA](https://github.com/majorminorlabs/hermes-talaria/releases/tag/v0.1.0).
Leave normal App-ID customization/suffix behavior enabled. A resigned identity
such as `xyz.majorminor.talaria.<YOUR TEAM ID>` is expected. Follow the
[SideStore user guide](SIDESTORE_USER_GUIDE.md), then pair with the same bridge.

**LocalDevVPN is only for SideStore installation/refresh. Tailscale is for normal
Talaria ↔ Hermes bridge connectivity.** Turn LocalDevVPN off and Tailscale back
on before using Talaria. Xcode installs do not require LocalDevVPN.

## Mac bridge setup

Clone this repository on the Studio, then install the bridge for the macOS account that owns the Hermes installation:

```sh
git clone https://github.com/majorminorlabs/hermes-talaria.git ~/src/talaria
cd ~/src/talaria
./scripts/install-bridge.sh --bot-management --bot-chat --bot-mode --board default
```

The installer creates a versioned bridge runtime and virtual environment under `~/Library/Application Support/HermesMobileBridge`, separate from both the source checkout and Hermes's Python environment. It keeps service configuration, bridge state, upstream token files, and generated mobile credentials in that private service root. Logs go to `~/Library/Logs/HermesMobileBridge`. It installs per-user LaunchAgents for the bridge and a dedicated Hermes desktop backend process.

The defaults use Hermes source `~/.hermes/hermes-agent`, the existing Hermes home `~/.hermes`, a private workspace beneath the service root, bridge loopback port 8787, and desktop backend loopback port 9119. The installer checks that the Hermes source is an audited Hermes commit (`4bb9e57bfde8a0affb5553eff13ed6e1f14147f1` for full Bot Mode/media, or legacy `2a4c9afd7bd`). The separate backend process serves that selected Hermes home; it does not replace existing Hermes gateways. Override the source/home/workspace or ports during installation if your Studio uses different locations:

```sh
./scripts/install-bridge.sh \
  --hermes-source "$HOME/.hermes/hermes-agent" \
  --workspace "$HOME/Projects/my-workspace" \
  --bot-management --bot-chat --bot-mode --board default
```

Use `--board NAME` for each Kanban board to expose. Review the installer summary before accepting it. The dedicated backend must use the audited Hermes checkout and have exclusive ownership of its configured chat transport. Existing Hermes gateways are left in place and unchanged.

Configure HTTPS through Tailscale Serve and check the service:

```sh
./scripts/configure-tailscale.sh
./scripts/status-bridge.sh
```

The placeholder URL is `https://your-mac.your-tailnet.ts.net`. Use the actual URL printed by the helper and confirm it matches the Studio's current MagicDNS name before pairing. Tailscale Serve proxies HTTPS on port 443 to the bridge at `127.0.0.1:8787`; the bridge remains bound to loopback and requires its own mobile bearer token.

## Pair and verify

Both installation methods use this procedure.

Create a device credential. The default command provisions a scoped token without printing it:

```sh
./scripts/pairing-token.sh --name iPhone
```

Follow the command's private-provisioning instructions. The helper keeps the token in a mode-0600 `mobile-pairing.json` file until you remove the transfer copy or revoke it. When the app's Add Host flow asks for the token, display it in a private terminal:

```sh
./scripts/pairing-token.sh --show
```

Copy it directly into Talaria; do not put it in shell history, a file in the checkout, chat, screenshots, or logs. Talaria stores it in Keychain. After pairing, remove the separate protected plaintext transfer copy with `./scripts/pairing-token.sh --forget-transfer`; the token remains valid in Talaria. The bridge's credential database stores only the credential hash and registry metadata. If the token is exposed, revoke its device ID with `./scripts/pairing-token.sh --revoke DEVICE_ID`, then provision a replacement.

### On the iPhone

1. Install and sign in to Tailscale on the iPhone. Confirm the Mac and phone are members of the same tailnet. Disable LocalDevVPN if you used SideStore.
2. Install Talaria using either [Xcode](XCODE_INSTALL.md) or [SideStore](SIDESTORE_USER_GUIDE.md).
3. Open Talaria → More → Saved Hosts → Add Host.
4. Enter a name such as `Mac Studio`, the HTTPS bridge URL, and the one-time displayed mobile token. Saving checks authentication and stores the token in the iPhone Keychain.
5. Open Home and confirm that both the bridge and Hermes report healthy.

6. Open Bots and an existing bot chat, then send a short request and verify a
   streamed response. Existing Hermes conversations/history should be accessible;
   local preferences and credentials from a different app identity are not imported.
7. Open Tasks, then force quit/relaunch Talaria and confirm reconnect. For SideStore,
   also complete the guide's ordinary Refresh verification before relying on it.

Use the full HTTPS URL shown by `configure-tailscale.sh`. Do not enter the Studio's loopback bridge URL, a raw HTTP URL, an SSH address, or a Hermes provider key.

## Bundle identity

Self-builders may use `com.example.talaria` or another unique ID under their own
Team. Talaria uses the actual runtime bundle ID for its Keychain service, so the
literal canonical string is not required. Changing the ID creates a distinct iOS
application: its local container/preferences and Keychain state do not automatically
carry over. For a fresh install, configure the host and pair normally. Keep the
installed ID and Team stable for updates; do not copy MAJOR//MINOR signing material.

## Service controls and updates

Run these commands from the repository checkout:

```sh
./scripts/status-bridge.sh
./scripts/stop-bridge.sh
./scripts/start-bridge.sh
./scripts/update-bridge.sh
./scripts/uninstall-bridge.sh
```

The update command installs the checked-out bridge source into a new versioned runtime while retaining the service's private configuration, credentials, run journal and logs. It refuses to update while an active or uncertain run may be controlled. Stop or reconcile that work in the app/Studio first, then retry. Uninstall removes the LaunchAgents and installed runtime but retains configuration and state by default. Use `./scripts/uninstall-bridge.sh --purge` only when you deliberately want to erase the retained service data and device credentials too.

For full Studio service, backup, and network details, read [Studio setup](STUDIO_SETUP.md). For development builds and simulator tests, see the root [README](../README.md).

## Current installation limits

The bridge and Hermes LaunchAgents start when the owning user logs in and are kept alive after crashes. They stop at logout; they do not run before login as root services. The Mac must be powered, awake, logged into the configured account, and connected to Tailscale for iPhone access. This is an intentional per-user service design so the processes use the normal Hermes configuration without system-wide privileges.

Pairing is manual host URL plus token. There is no QR enrollment endpoint in bridge v0.1.0. Physical iPhone behavior depends on the actual tailnet policy, Apple signing, and device network; the repository's local Simulator results do not establish those outcomes.
