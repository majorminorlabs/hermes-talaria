> This guide installs the unsigned v0.2.0 download. Pair through Studio → Saved Hosts.
> The current physical acceptance used Xcode; SideStore expiry/refresh limitations below remain.

# Talaria with official SideStore

Talaria is MAJOR//MINOR's native iPhone companion for the Hermes backend on your
Mac. Its canonical public unsigned IPA bundle ID is `xyz.majorminor.talaria`;
version 0.2.0, build 2. This is the alternative to
[building/installing with Xcode](XCODE_INSTALL.md), not a requirement for Talaria.
Paid Apple Developer Program membership is not required for this free-account path.

**LocalDevVPN is for SideStore installation/refresh. Tailscale is for Talaria ↔
Hermes bridge connectivity.** LocalDevVPN is not part of Talaria's normal network
architecture. Turn it off and restore Tailscale when you finish a SideStore operation.

## Identity and evidence

| Term | Meaning |
| --- | --- |
| Canonical IPA bundle ID | `xyz.majorminor.talaria`, as distributed by MAJOR//MINOR. |
| SideStore resigned/installed ID | Official defaults are expected to produce `xyz.majorminor.talaria.<YOUR TEAM ID>`. This is your installed app's identity; preserve it for updates. |
| Apple Team ID | The development Team belonging to your Apple Account. No maintainer Team value is supplied or required. |
| Application identifier | The signed `<TEAM>.<installed bundle ID>` supplied by your provisioning profile, normally `<TEAM>.xyz.majorminor.talaria.<TEAM>`. |
| Keychain access group | The default group allowed by the installed signing entitlements. Talaria specifies no access-group entitlement or query override; signing supplies the group. |
| Keychain service | Talaria uses the running `Bundle.main.bundleIdentifier` and host ID as service/account. It follows the resigned identity. It never uses the maintainer's Team. |

**Physical evidence (2026-10-05):** the published public IPA was installed under
its normal Team-suffixed identity on one Apple Account. Pairing, Home, existing
bot inventory/history, fresh streamed normal and bot chat, Tasks, Settings,
Photos/Files pickers, force quit/relaunch and ordinary Refresh passed. The renewed
profile matched the actual installed ID, and the app reconnected after Refresh.
That session used the existing SideStore build with the legacy same-Team ID fix;
it was not a stock-official-build or second-account test. Public-ID Refresh All
was deliberately skipped to preserve a separate rollback installation.

**Source-derived official behavior:** normal suffix selection and reuse on Refresh,
based on [SideStore `6032424a` profile selection](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift),
[context defaults](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Core/Operations/OperationContexts.swift)
and [customization defaults](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/AltStore/Core/Extensions/UserDefaults+AltStore.swift).
Official SideStore remains the normal installation route; its suffixed path does
not require the advanced unsuffixed-ID fix. A stock-build public-ID physical run,
a different Apple Account, actual expiry/recovery, reboot, cellular-only and
background refresh remain untested.

Extensive earlier physical update/data-retention and refresh evidence, including
Refresh All, is recorded separately in the
[historical investigation](SIDESTORE_INDEPENDENT_INVESTIGATION.md#6-physical-validation).
Release-preparation reports describe their original snapshot, before the later
public-ID phone validation above; the published v0.1.0 artifacts are unchanged.

Current 0.2.0 Xcode upgrade and device acceptance are recorded in
[physical acceptance](PHYSICAL_ACCEPTANCE_v0.2.0.md). They do not certify new
SideStore account signing, expiry or refresh behavior.

## New user: install, pair, chat and Refresh

First prepare the awake, logged-in Mac's Hermes bridge and private Tailscale HTTPS
as described in [installation](INSTALL.md). You need an iPhone on iOS 18+, a
passcode, your own Apple Account and Tailscale access to your Mac.

1. **Install official SideStore.** Follow its current
   [prerequisites](https://docs.sidestore.io/docs/installation/prerequisites) and
   [installation guide](https://docs.sidestore.io/docs/installation/install).
   The documented Mac route uses iloader and LocalDevVPN. Complete device trust,
   Developer App trust and Developer Mode where required.
2. **Configure SideStore normally.** Turn Tailscale off, connect LocalDevVPN
   on Wi-Fi, and sign in using the
   same Apple Account used for SideStore's installation. Complete 2FA and refresh
   SideStore itself once. Leave **Settings → User Customizations → Customize AppID**
   off. A free account has a seven-day signing window and app/App-ID limits; check
   the [FAQ](https://docs.sidestore.io/docs/faq) before adding other apps.
3. **Get and verify the Talaria IPA.** Download `Talaria-v0.2.0.ipa` and the
   [release](https://github.com/majorminorlabs/hermes-talaria/releases/tag/v0.2.0)'s
   `SHA256SUMS.txt`; compare the IPA's `shasum -a 256 Talaria-v0.2.0.ipa` output
   with its entry in that file on your Mac. The unsigned archive
   has the public base ID and no provisioning profile or personal certificate.
   Transfer it through a trusted method that makes it available to SideStore.
4. **Import with defaults.** Save the IPA to Files, then use **SideStore →
   My Apps → +** to select it. The previously tested URL-import route is
   `sidestore://install?url=<HTTPS IPA URL>`; use only a trusted release URL. If **AppID
   Customization** appears because you enabled it, retain base ID
   `xyz.majorminor.talaria`, leave **Append Team ID checked**, then Confirm.
   Do not force an exact maintainer application identifier or turn the suffix off.
5. **Install Talaria.** Keep LocalDevVPN connected until signing/install completes.
   Confirm Talaria appears in My Apps with a valid signing period. Normal signing
   registers a Team-specific ID and installs it with your own profile. If signing
   fails, use SideStore's reported error and the account limits below. Do not change
   identity repeatedly as a troubleshooting shortcut.
6. **Switch to Tailscale.** Turn LocalDevVPN off, then turn Tailscale on.
   Confirm it reaches the same tailnet as your Mac before opening Talaria.
7. **Pair with your own bridge.** In **Talaria → Studio → Saved Hosts → Add Host**, enter
   the HTTPS URL printed by your Mac's setup helper and your own mobile bridge
   token. The token is stored in the phone's device-only Keychain. Hermes/provider
   credentials stay on your Mac; SideStore does not provide the bridge connection.
8. **Verify chat.** Confirm Studio reports the host connected, open global Ask, send a
   short request and wait for a fresh streamed reply. Check Agents and Threads,
   create two independent threads for one Agent, and verify each history. Force
   quit/relaunch and verify reconnect.
   A health badge alone is insufficient.
9. **Verify Refresh.** Turn Tailscale off and LocalDevVPN on while on Wi-Fi.
   Open SideStore and tap Talaria's days badge to Refresh. Check its renewed signing
   period; turn LocalDevVPN off and Tailscale back on. Reopen Talaria and confirm saved host,
   preferences and a fresh chat reply without token re-entry. A "7 days" badge
   alone is not proof that the correct profile was renewed. Advanced verification
   can inspect the renewed profile with approved local tooling: its application
   identifier must match your existing Team-specific installed ID. No maintainer
   Team, profile or device identifier should be copied into this check.
10. **Refresh weekly, before expiry.** Follow the explicit VPN/Refresh All sequence
    below. Keep your installed ID and Apple Account/Team stable for future IPAs.

Never delete an existing installation as part of a routine update. Changing its
installed bundle ID or Team changes data/Keychain access; migration requires a
separate plan. Free-account expiry, reboot/cellular/background refresh and
post-expiry recovery are not validated by this release.

## Weekly refresh with free-account signing

Refresh before the seven-day period expires; do not wait until the final minute.
Use Wi-Fi as required by [SideStore's prerequisites](https://docs.sidestore.io/docs/installation/prerequisites).

1. Turn **Tailscale off** on the iPhone.
2. Turn **LocalDevVPN on** and confirm it is connected.
3. Open **SideStore → My Apps → Refresh All**.
4. Wait for completion, check for errors and verify the refreshed signing period
   for both Talaria and SideStore. Refresh All affects all apps managed there;
   use Talaria's individual days badge if another installation must stay untouched.
5. Turn **LocalDevVPN off**.
6. Turn **Tailscale back on** and confirm its connection.
7. Open Talaria, confirm the saved bridge connects, and send a fresh chat request.

A refreshed SideStore badge alone is insufficient: Talaria must also have a valid
matching profile and still work. This sequence renews signing; it does not install
new Talaria code. For an app update, import the new published IPA using the same
Apple Account/Team and installed identity, then repeat connection/chat checks.

## Free-account capacity and App IDs

[Apple](https://developer.apple.com/help/account/basics/about-your-developer-account)
and the [SideStore FAQ](https://docs.sidestore.io/docs/faq) describe separate limits:

- **Installed apps:** at most three free-profile apps per device. SideStore counts
  as one; Talaria counts as another. Xcode test runners and a second Talaria identity
  can consume a slot too. An App Store installation of LocalDevVPN does not consume
  a free-development app slot. A maximum-installed-apps error requires freeing an
  unneeded installed app, with its owner's approval; preserve any needed rollback.
- **App-ID registrations:** up to 10 active free-account App IDs, expiring after
  seven days. Extensions can need additional IDs. Uninstalling an app frees device
  capacity but does not immediately free its App-ID registration. Let stale IDs
  expire; do not repeatedly change bundle IDs or delete unrelated registrations.

A paid Team uses different provisioning limits. This guide's seven-day weekly
sequence targets free-account signing; follow the actual profile expiration if
using paid membership.

## Why ordinary new users need no patch

In pinned official SideStore source, `appendTeamID` defaults to true, so a first
import constructs the public base plus the active Team ID. The installed record
stores the resigned ID and Team. On Refresh, that ID contains the same Team ID,
so `getPreferredBundleID` reuses it. The regression's suffix condition is therefore
satisfied on the default path. This is an inference from official source and
Talaria's no-extension packaging. The physical public-ID test above used a
pre-existing patched build, so it does not establish stock-build behavior. Check newer
SideStore guidance/source if its behavior changes.

Talaria has no app extensions, app groups, push or iCloud entitlement requirements.
Its Keychain queries specify service/account only and accept the installed signing
identity's default group. The runtime bundle-ID service follows SideStore's rewrite.
Simulator tests confirm the runtime default and separation of base/resigned service
names; they do not prove Apple signing or cross-Team migration.

## Advanced legacy or exact-ID installations

Legacy development identifier: `com.dippo.hermes`. This is a distinct application
from the public release. Keep any needed legacy installation as rollback until
the new identity is verified; local data and Keychain do not migrate automatically.

The same-team **unsuffixed** case also applies to an exact public ID if you choose
that advanced installation route. On the inspected stock SideStore versions,
Refresh rejects the saved ID unless it contains the Team ID, then renews a
suffixed ID's profile while reporting success. Turning Append off affects import
only. It does not repair normal Refresh.

For the existing legacy installation:

- Preserve its installed ID and Apple Team. Do not delete or reset the app.
- Retain the already-tested patched SideStore. Do not accept an unpatched
  replacement until it includes the fix. Replacing SideStore can require signing
  in again; it is a separate operation from installing Talaria.
- The minimal [source patch](sidestore/0001-restore-preferred-bundle-id-team-rule.patch)
  restores AltStore's same-Team reuse rule. Its behavior and source build steps
  remain in the [independent investigation](SIDESTORE_INDEPENDENT_INVESTIGATION.md).
- If unpatched SideStore replaces it, the historical manual fallback is re-import
  of the **legacy IPA** with the same exact legacy ID and Append Team ID off before
  expiry. The new public IPA is not a drop-in legacy update; do not use it to
  overwrite a legacy installation as a routine update.
- Fix-specific regression testing covered the legacy same-Team/no-extension case;
  the later public suffixed installation also used that build. Unsuffixed
  extensions, expiry recovery and account changes remain untested.

The [upstream issue/PR draft](sidestore/UPSTREAM_PR.md) is ready for later review
and submission. It has not been submitted. Talaria distributes the source patch
and its provenance, not a SideStore fork or patched SideStore IPA. Ordinary new
users follow the official suffixed path above.
