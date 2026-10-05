# Install Talaria

Talaria is the native iPhone client for Hermes. Hermes Agent and the mobile bridge run on the Mac Studio; the phone connects to the bridge over your tailnet. The bridge does not replace Hermes and does not connect through SSH.

## Requirements

- A Mac Studio with the audited Hermes installation and its desktop API available to a dedicated local backend.
- macOS, Python 3.11 or newer, and Tailscale signed in to the same tailnet as the iPhone.
- Tailscale MagicDNS and HTTPS enabled for the tailnet. Tailscale Serve also needs the phone-to-Studio connection allowed by the tailnet access policy.
- An iPhone running iOS 18 or newer, and an installation route: Xcode with a signed-in Apple ID for development, or SideStore for repeatable personal-device installs.

Talaria is published by MAJOR//MINOR. The canonical IPA bundle identifier is `xyz.majorminor.talaria` and the app version is `0.1.0`. Installation requires your own Apple signing identity; no signing certificate or provisioning profile is included. Source analysis predicts that official SideStore's default signing installs it as `xyz.majorminor.talaria.<your Team ID>`. Keep the default suffix; no second-account physical installation is claimed. For the complete install, pairing, chat and Refresh sequence, see the [SideStore user guide](SIDESTORE_USER_GUIDE.md).

## Mac Studio

Clone this repository on the Studio, then install the bridge for the macOS account that owns the Hermes installation:

```sh
git clone <repository-url> ~/src/talaria
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

Create a device credential. The default command provisions a scoped token without printing it:

```sh
./scripts/pairing-token.sh --name iPhone
```

Follow the command's private-provisioning instructions. The helper keeps the token in a mode-0600 `mobile-pairing.json` file until you remove the transfer copy or revoke it. When the app's Add Host flow asks for the token, display it in a private terminal:

```sh
./scripts/pairing-token.sh --show
```

Copy it directly into Talaria; do not put it in shell history, a file in the checkout, chat, screenshots, or logs. Talaria stores it in Keychain. After pairing, remove the separate protected plaintext transfer copy with `./scripts/pairing-token.sh --forget-transfer`; the token remains valid in Talaria. The bridge's credential database stores only the credential hash and registry metadata. If the token is exposed, revoke its device ID with `./scripts/pairing-token.sh --revoke DEVICE_ID`, then provision a replacement.

## iPhone

1. Install and sign in to Tailscale on the iPhone. Confirm the Studio and phone are members of the same tailnet.
2. Install Talaria with SideStore by following the [SideStore user guide](SIDESTORE_USER_GUIDE.md), steps 1–6. Leave **Append Team ID** on. Developers can use Xcode instead (below).
3. Open Talaria → More → Hosts → Add Host.
4. Enter a name such as `Mac Studio`, the HTTPS bridge URL, and the one-time displayed mobile token. Saving checks authentication and stores the token in the iPhone Keychain.
5. Open Home and confirm that both the bridge and Hermes report healthy.

Use the full HTTPS URL shown by `configure-tailscale.sh`. Do not enter the Studio's loopback bridge URL, a raw HTTP URL, an SSH address, or a Hermes provider key.


Keep signing machine-local: copy `Config/Signing.example.xcconfig` to the ignored root `Signing.local.xcconfig` and set `DEVELOPMENT_TEAM` to your Team ID from Xcode. The shared project loads it optionally. Selecting a Team in Xcode can write the project file; keep that personal change uncommitted. Release packaging overrides the Team and signing identity to blank.

### Direct Xcode installation

For development, connect and unlock the iPhone, accept its Trust This Computer prompt, and open the project in Xcode. Under the **Hermes** target's **Signing & Capabilities**, select your Apple Account's **Personal Team** and leave automatic signing enabled. The canonical public source ID is `xyz.majorminor.talaria`. Direct Xcode signing requires an identifier your Team can register; if necessary use a unique developer ID in ignored local build settings. That build is a separate app from a SideStore install. Select the connected iPhone as the run destination and press **Run**. Xcode requires an Apple Account sign-in, but a paid Developer Program membership is not required for personal-device testing. Apple's Personal Team provisioning is temporary: registered App IDs/devices and development profiles expire after seven days, so the app must be rebuilt/reinstalled periodically. [Apple account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account) · [Installing on personal devices with Xcode](https://developer.apple.com/help/account/membership/program-enrollment).

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
