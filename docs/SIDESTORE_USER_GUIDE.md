# Talaria with official SideStore

Talaria is MAJOR//MINOR's native iPhone companion for the Hermes backend on your
Mac. Its canonical public unsigned IPA bundle ID is `xyz.majorminor.talaria`;
version 0.1.0, build 1. This guide separates the normal new-user path from the
advanced same-team unsuffixed-ID bug.

## Identity and evidence

| Term | Meaning |
| --- | --- |
| Canonical IPA bundle ID | `xyz.majorminor.talaria`, as distributed by MAJOR//MINOR. |
| SideStore resigned/installed ID | Official defaults are expected to produce `xyz.majorminor.talaria.<YOUR TEAM ID>`. This is your installed app's identity; preserve it for updates. |
| Apple Team ID | The development Team belonging to your Apple Account. No maintainer Team value is supplied or required. |
| Application identifier | The signed `<TEAM>.<installed bundle ID>` supplied by your provisioning profile, normally `<TEAM>.xyz.majorminor.talaria.<TEAM>`. |
| Keychain access group | The default group allowed by the installed signing entitlements. Talaria specifies no access-group entitlement or query override; signing supplies the group. |
| Keychain service | Talaria uses the running `Bundle.main.bundleIdentifier` and host ID as service/account. It follows the resigned identity. It never uses the maintainer's Team. |

**Source-derived:** normal new-user install and Refresh behavior below, based on
[SideStore `6032424a` profile selection](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift),
[context defaults](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Core/Operations/OperationContexts.swift),
[customization default](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/AltStore/Core/Extensions/UserDefaults+AltStore.swift)
and the install/resign pipeline inspected on 2026-10-05. A different Apple Account,
new public-ID installation and its physical Refresh have **not** been tested.
Current Simulator/build results validate Talaria packaging and local behavior,
not Apple portal registration or on-phone signing.

**Physically tested historical evidence:** same-Team legacy update, two single-app
Refreshes and Refresh All with patched SideStore, preserving data/Keychain. The
[legacy investigation](SIDESTORE_INDEPENDENT_INVESTIGATION.md#6-physical-validation)
records that separate experiment. The existing phone was left untouched during
public-ID release preparation.

## New user: install, pair, chat and Refresh

First prepare the awake, logged-in Mac's Hermes bridge and private Tailscale HTTPS
as described in [installation](INSTALL.md). You need an iPhone on iOS 18+, a
passcode, your own Apple Account and Tailscale access to your Mac.

1. **Install official SideStore.** Follow its current
   [prerequisites](https://docs.sidestore.io/docs/installation/prerequisites) and
   [installation guide](https://docs.sidestore.io/docs/installation/install).
   The documented Mac route uses iloader and LocalDevVPN. Complete device trust,
   Developer App trust and Developer Mode where required.
2. **Configure SideStore normally.** Connect LocalDevVPN and sign in using the
   same Apple Account used for SideStore's installation. Complete 2FA and refresh
   SideStore itself once. Leave **Settings → User Customizations → Customize AppID**
   off. A free account has a seven-day signing window and app/App-ID limits; check
   the [FAQ](https://docs.sidestore.io/docs/faq) before adding other apps.
3. **Get and verify the Talaria IPA.** Download `Talaria-v0.1.0.ipa` and the
   release's `SHA256SUMS.txt`; check the IPA hash on your Mac. The unsigned archive
   has the public base ID and no provisioning profile or personal certificate.
   Transfer it through a trusted method that makes it available to SideStore.
4. **Import with defaults.** In SideStore, import the Talaria IPA. If **AppID
   Customization** appears because you enabled it, retain base ID
   `xyz.majorminor.talaria`, leave **Append Team ID checked**, then Confirm.
   Do not force an exact maintainer application identifier or turn the suffix off.
5. **Install Talaria.** Keep LocalDevVPN connected until signing/install completes.
   Confirm one Talaria entry in My Apps. Official source is expected to register
   the Team-specific ID and install it with your own profile. If signing fails,
   use SideStore's reported error; Talaria has not proven a second-account portal
   path. Do not change identity repeatedly as a troubleshooting shortcut.
6. **Switch to Tailscale.** LocalDevVPN may replace the active Tailscale VPN.
   Restore Tailscale before opening Talaria for Hermes connectivity.
7. **Pair with your own bridge.** In **Talaria → More → Hosts → Add Host**, enter
   the HTTPS URL printed by your Mac's setup helper and your own mobile bridge
   token. The token is stored in the phone's device-only Keychain. Hermes/provider
   credentials stay on your Mac; SideStore does not provide the bridge connection.
8. **Verify chat.** Confirm Home reports the host connected, open Chat, send a
   short request and wait for a fresh reply. A health badge alone is insufficient.
9. **Verify Refresh.** Switch to LocalDevVPN, open SideStore and tap Talaria's days
   badge to Refresh. Restore Tailscale, reopen Talaria and confirm saved host,
   preferences and a fresh chat reply without token re-entry. A "7 days" badge
   alone is not proof that the correct profile was renewed. Advanced verification
   can inspect the renewed profile with approved local tooling: its application
   identifier must match your existing Team-specific installed ID. No maintainer
   Team, profile or device identifier should be copied into this check.
10. **Refresh weekly, before expiry.** Connect LocalDevVPN → My Apps → Refresh All
    → reconnect Tailscale → open Talaria. Confirm chat still works. Keep your
    installed ID and Apple Account/Team stable when importing future Talaria IPAs.

Never delete an existing installation as part of a routine update. Changing its
installed bundle ID or Team changes data/Keychain access; migration requires a
separate plan. Free-account expiry, reboot/cellular/background refresh and
post-expiry recovery are not validated by this release.

## Why ordinary new users need no patch

In pinned official SideStore source, `appendTeamID` defaults to true, so a first
import constructs the public base plus the active Team ID. The installed record
stores the resigned ID and Team. On Refresh, that ID contains the same Team ID,
so `getPreferredBundleID` reuses it. The regression's suffix condition is therefore
satisfied on the default path. This is an inference from official source and
Talaria's no-extension packaging, not a physical new-user result. Check newer
SideStore guidance/source if its behavior changes.

Talaria has no app extensions, app groups, push or iCloud entitlement requirements.
Its Keychain queries specify service/account only and accept the installed signing
identity's default group. The runtime bundle-ID service follows SideStore's rewrite.
Simulator tests confirm the runtime default and separation of base/resigned service
names; they do not prove Apple signing or cross-Team migration.

## Advanced legacy or exact-ID installations

Legacy development identifier: `com.dippo.hermes`. The maintainer's validated
installation at this ID remains on the phone. It is a different app from the new
public release; no install, migration, re-sign, deletion or phone test was performed.
Personal migration is deferred until separately authorized.

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
  migrate that installation during this release preparation.
- The patch was physically tested only on the legacy same-Team/no-extension case.
  Unsuffixed extensions, expiry recovery and account changes remain untested.

The [upstream issue/PR draft](sidestore/UPSTREAM_PR.md) is ready for later review
and submission. It has not been submitted. Talaria distributes the source patch
and its provenance, not a SideStore fork or patched SideStore IPA. Ordinary new
users follow the official suffixed path above.
