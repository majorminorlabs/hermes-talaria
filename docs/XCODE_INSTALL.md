# Install Talaria with Xcode

Build Talaria from its open-source project and install it with your own Apple
Developer Team. SideStore and LocalDevVPN are not required for this route.

## Prerequisites

- A Mac with Xcode 26 or newer and an Apple Account signed in under Xcode's
  **Settings → Accounts**. A free **Personal Team** or paid Apple Developer
  Program Team can install on your own device.
- An iPhone running iOS 18 or newer, unlocked and connected to the Mac.
- Hermes on your Mac, plus hermes-mobile-bridge and private Tailscale HTTPS.
  Follow the shared [bridge setup](INSTALL.md#mac-bridge-setup) after installing
  the app; Talaria does not install Hermes for you.

### Free versus paid signing

Free Apple Account signing appears as **Personal Team** in Xcode. Apple limits
it to 10 App IDs, three registered devices and three installed apps per device;
the App IDs/devices and provisioning profiles expire after seven days. Rebuild
and reinstall on your iPhone before profile expiry to continue using Talaria.
These limits also affect development/test-runner apps installed on that device.
See [Apple's account overview](https://developer.apple.com/help/account/basics/about-your-developer-account).

Paid Apple Developer Program membership provides normal Team development
provisioning instead of the free Personal Team's seven-day restrictions. Signing
still depends on valid certificates, device registration and a provisioning
profile; inspect that profile's expiration and rebuild/reprovision when needed.
Paid membership does not make an installed build permanent. Xcode automatic
signing can manage development profiles; see
[Apple's development provisioning guide](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile).

## Clone and open the project

```sh
git clone https://github.com/majorminorlabs/hermes-talaria.git
cd hermes-talaria
open Hermes.xcodeproj
```

Talaria's display name is **Talaria**. Its technical Xcode project, app target
and scheme retain the name **Hermes**. Select the **Hermes** app target, not
HermesTests or HermesUITests.

## Choose your Team and bundle identifier

1. Select the project in Xcode's navigator, then **TARGETS → Hermes**.
2. Open **Signing & Capabilities** and enable **Automatically manage signing**.
3. Choose your own Apple Developer Team (or **Personal Team**).
4. Check the **Bundle Identifier**. The canonical project/release ID is
   `xyz.majorminor.talaria`, identifying the MAJOR//MINOR release. If it is not
   available to your Team, replace it with a unique ID such as
   `com.example.talaria`, preferably based on a domain you control. Apply your
   choice to the build configurations you will use.
5. Allow Xcode to create the development certificate and profile for your Team
   and connected device. Resolve signing errors before building.

Changing the bundle ID for a self-build is normal. Talaria's bridge Keychain
service uses `Bundle.main.bundleIdentifier` at runtime and the saved host ID;
the literal `xyz.majorminor.talaria` is not required for normal app operation.
Signing supplies the default Keychain access group.

A changed bundle ID creates a distinct iOS application identity. It does not
automatically share another installation's local container, preferences, drafts
or Keychain credentials. Hermes keeps sent conversations, bots and history on
the Mac, so a new app can access them after pairing with that bridge. For a fresh
install, simply add the host and pair. Preserve an existing app as rollback if
you are deliberately changing identities.

Keep personal signing changes out of commits. The shared project optionally
loads the ignored root `Signing.local.xcconfig`: copy
`Config/Signing.example.xcconfig` there to store your `DEVELOPMENT_TEAM` locally.
Changing the bundle identifier in Xcode writes the project file; keep that edit
local and review your diff before committing. Do not copy MAJOR//MINOR Team IDs,
certificates, credentials or provisioning material.

## Install on the physical iPhone

1. Connect and unlock the iPhone. Accept **Trust This Computer** if prompted.
2. Enable **Settings → Privacy & Security → Developer Mode** if required,
   restart the phone and complete its confirmation.
3. Select the **Hermes** scheme and your physical iPhone as the run destination.
4. Choose **Product → Run**. Xcode builds, signs and installs Talaria.
5. If iOS asks you to trust the developer, follow its prompt under
   **Settings → General → VPN & Device Management**, then launch Talaria again.

See [Apple's device-running guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).
Simulator success alone does not verify physical signing or bridge connectivity.

## Configure Hermes and pair

Use the one shared [Mac bridge setup](INSTALL.md#mac-bridge-setup) and
[pairing/verification procedure](INSTALL.md#pair-and-verify). Both Xcode and
SideStore installs use Hermes → hermes-mobile-bridge → private Tailscale HTTPS
→ Talaria. Keep Tailscale connected on the phone for normal use; LocalDevVPN is
only needed by the alternative SideStore route.

Verify Home, existing Bots/history, a fresh streamed normal chat and bot chat,
Tasks, and reconnect after force quit/relaunch. Never put Hermes/provider
credentials into Talaria; use the bridge's scoped mobile pairing token.

## Update or rebuild later

Update your checkout to the intended source revision, retain your installed
bundle ID and Team, then **Product → Run** on the same iPhone. Rebuild/reinstall
before seven-day expiry for a free Personal Team; for paid signing, renew the
profile/certificate as needed. Do not delete the installed app for routine
updates. Changing Team or bundle ID can require a separate install and pairing.
Bridge updates are separate: follow [Mac service setup](STUDIO_SETUP.md).

## Common signing problems

- **Identifier unavailable / failed to register bundle identifier:** choose a
  unique ID your Team can register, then retry automatic signing.
- **Signing requires a development team:** sign in to Xcode and select your
  Team on the app target; do not use the publisher's Team.
- **No profiles / device not registered:** unlock/trust the phone, select the
  correct Team and physical destination, and let automatic signing register it.
  Paid organization Teams may restrict certificate or device registration;
  ask that Team's administrator if Xcode reports insufficient permission.
- **Maximum installed apps / App-ID limit:** a free Personal Team is subject
  to Apple's limits above. Remove only an unneeded app with your approval to
  free device capacity. Deleting an app does not immediately free its App-ID
  registration; let unused registrations expire rather than repeatedly renaming.
- **Developer Mode disabled / untrusted developer:** complete the corresponding
  iPhone Settings/trust steps, then retry Run.
- **App expired:** rebuild/reinstall with the same ID and Team. SideStore is
  not required to renew an Xcode installation.
- **Launches but cannot reach Hermes:** signing succeeded; check the shared
  [connection troubleshooting](TROUBLESHOOTING.md), Tailscale and bridge health.
