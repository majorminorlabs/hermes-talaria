# Talaria v0.1.0 SideStore validation

> Historical device evidence. Legacy development identifier: `com.dippo.hermes`.
> The public release now uses `xyz.majorminor.talaria`. These observations concern
> the existing legacy installation; they do not validate the new public identity.
> That physical installation is preserved untouched during public release preparation.

> **Update (2026-10-05, later):** an [independent investigation](SIDESTORE_INDEPENDENT_INVESTIGATION.md)
> traced the refresh failure to SideStore commit `2873e2ec`. A one-line SideStore
> patch fixes it. With the patched SideStore, normal Refresh (twice) and Refresh All
> renewed `com.dippo.hermes` on the physical phone, with data and Keychain intact.
> The stock-SideStore observations below remain accurate for unpatched builds.

Date: 2026-10-05. Release source: `de7517f`. Physical iPhone 15 Pro Max,
iOS 26.6.2 (23G90). Talaria 0.1.0/build 1, bundle `com.dippo.hermes`.
SideStore installed through the Stable selector reports
`0.7.0-20260911.328+6032424a` (build 0700); its upstream release tag is
[`0.7.0-alpha`](https://github.com/SideStore/SideStore/releases/tag/0.7.0-alpha).
LocalDevVPN 1.3.0 and Tailscale 1.102.4 were used.

## Results

| Acceptance check | Result |
| --- | --- |
| Existing IPA imported into SideStore | PASS |
| Update over existing Xcode installation, exact bundle ID | PASS |
| Useful app-container state preserved | PASS |
| Existing Keychain bridge authentication usable | PASS |
| Normal SideStore Refresh renews exact app identity | **FAIL** |
| Repeat IPA re-sign/install with exact identity | PASS, manual workaround |
| Physical launch, host, bots, history, preferences and new messages | PASS |

The following sections are historical stock-SideStore observations. The later
patched-SideStore validation cleared normal refresh; see the update above and
[independent investigation](SIDESTORE_INDEPENDENT_INVESTIGATION.md#6-physical-validation).
No push, tag or GitHub release was performed. No IPA rebuild, uninstall, data reset,
Keychain clearing, saved-host removal or credential re-entry occurred.

## Baseline and evidence provenance

Before import, the owner explicitly reported: Mac Studio connected/authenticated,
no re-pair prompt, existing bots and conversation/history present, and no missing
or reset preferences/state. Device inventory independently confirmed the existing
Talaria installation. A prior private app-data backup remained available; it was
not restored during this validation and no Keychain extraction was performed.

Subsequent observations were made on the physical phone through iPhone Mirroring,
with `devicectl` app inventory/launch and SideStore device console logs corroborating
installation and provisioning operations. Times below are America/Chicago (CDT).
Raw logs contain private account/device/signing metadata and are retained privately,
not committed. This document records sanitized observations, not an attached raw
forensic archive.

## Import and signing transition

Used the existing `build/release/v0.1.0/Talaria-v0.1.0.ipa` unchanged:

- SHA-256: `724a429fb91925f59f9185009f07ac7f6a6cb17bbebb9838f227d2f57fa8e8c8`
- Size: 2,202,513 bytes; unsigned standard `Payload/Hermes.app`.
- Import: temporary LAN HTTP server serving the IPA, through supported
  [`sidestore://install?url=`](https://docs.sidestore.io/docs/advanced/url-schema).
  Phone HTTP GETs returned 200. Initial AirDrop delivery did not yield a verified
  selectable/imported file, so it is not counted as the successful method.

Setup initially failed with `DeviceEndpointNotInitialized`; SideStore's discovered
IP/reachability fields were N/A. Installing/connecting LocalDevVPN resolved endpoint
reachability. The owner completed protected VPN/account prompts. SideStore signed
in using the same Apple Account/Team as the Xcode app, with its normal certificate
rotation. Retained Xcode provisioning metadata matched that Team; the original
installed binary's exact certificate was not independently extracted. Certificate
rotation alone must not be confused with changing the application/access-group
identity. No private signing values are included here.

A default import attempted `com.dippo.hermes.<Team>`, a different identity. iOS
rejected it with ApplicationVerificationFailed/free-account three-app limit; the
existing Talaria and XCTest runner remained installed. No slot was freed by deletion
and no duplicate Talaria appeared.

Enabled/confirmed **Settings → User Customizations → Customize AppID**. During
import, chose **Install**, kept `com.dippo.hermes` in **AppID Customization**, unchecked
**Append Team ID**, and chose **Confirm**. At approximately 09:43–09:44, SideStore
installed Talaria successfully and listed it under My Apps with seven days.
Inventory and explicit launch confirmed the original `com.dippo.hermes`, without a
suffixed duplicate. This is the successful update-in-place result.

## Preservation and physical functionality

After reconnecting Tailscale, Mac Studio showed Connected with one saved host and
no re-pair prompt. Three existing bots loaded: Hermes (default), Research
Orchestrator and Research Worker. Existing canonical chat entries and older Hermes
conversation messages remained visible. A new message in that existing conversation
received `TALARIA_SIDESTORE_UPDATE_OK` at approximately 09:47.

Preferences remained: Mac Studio host, Hermes default profile, Medium reasoning,
simulation off, System appearance, haptics on and notifications off. No duplicate
host/bot/chat entries or corrupt state were observed in inspected screens.

**App container:** saved host configuration, defaults/preferences and visible cached
state survived. This is functional preservation, not a byte-for-byte comparison of
all sandbox files. Canonical bots/conversation history reside on the bridge/Hermes
host; successful loading proves continued access to that existing history, not that
all canonical records were stored inside the phone container.

**Keychain:** production `KeychainBridgeCredentialStore` uses the bundle identifier
as its service and host ID as account, independently of UserDefaults/snapshot data.
The existing credential authenticated fresh bridge requests and message sends after
replacement, without token entry, re-pairing or backup restoration. This is a
functional Keychain-preservation PASS for the tested same-Team transition. It does
not prove migration across different Teams/access groups.

## Normal refresh failure and diagnosis

At approximately 09:50, with LocalDevVPN connected, tapped Talaria's seven-day badge
in My Apps. SideStore reported successful completion and seven days. Its logs show
target `com.dippo.hermes`, preferred bundle ID nil, `appendTeamID: true`, and a fetched
profile for `com.dippo.hermes.<Team>` expiring 2026-10-12 14:50:23 UTC. Profile install
reported success. This does **not** renew the original app's correct profile.

The matching upstream [profile-selection source](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift)
requires a saved resigned ID to contain the Team identifier before reusing it.
The unsuffixed ID fails that condition. Refresh omits the import customization step;
its context defaults to appending the Team. These observations explain the mismatch.
The successful UI label is insufficient evidence of valid renewal.

After restoring Tailscale, the original app still launched, authenticated and
received `TALARIA_SIDESTORE_REFRESH_OK` at approximately 09:54. Bots, history and
preferences remained. This verifies current functionality, not correct renewal or
continued validity after the original profile expires.

## Verified maintenance workaround and final state

Re-imported the same IPA, again with **Append Team ID off**. Device logs at 09:59:04
show `com.dippo.hermes`, `appendTeamID: false`; its correct main profile expires
2026-10-12 14:59:05 UTC. At 09:59:07, `installation_proxy_install` and SideStore's
operation completed successfully for `com.dippo.hermes`. This repeated signing and
update renewed the correct identity.

Restored Tailscale. Talaria launched and showed Mac Studio Connected. Existing
history, all three bots, one saved host and the preferences above remained. A fresh
request received `TALARIA_SIDESTORE_RESIGN_OK` at 10:00. Final inventory contained
Talaria only under `com.dippo.hermes`; the pre-existing XCTest runner was preserved.
The temporary transfer server was stopped. Phone was left with Talaria usable over
Tailscale.

The manual re-import workaround passes re-sign/update preservation; it is not a
PASS for the requested normal Refresh workflow. A supported SideStore fix followed
by correct-profile and physical functionality validation is still required. No
seven-day wait, expired-profile recovery, full reboot, cellular-only route or
cross-account migration was tested. No Talaria code defect or need to rebuild its
IPA was demonstrated.


## Follow-up: ordinary Refresh investigation from `987ed8a`

Performed 2026-10-05, approximately 10:06–10:18 CDT. Talaria and its IPA were not
changed. Device inventory again showed only `com.dippo.hermes` for Talaria, plus the
pre-existing XCTest runner; SideStore My Apps showed one Talaria entry.

### Directly observed tracked state

Enabled temporary SideStore/operation verbosity and the per-step **Fetch
Provisioning Profiles** diagnostic switch. An ordinary Talaria Refresh at 10:14
produced this sanitized trace from SideStore's database lookup:

```text
app=com.dippo.hermes
installedResignedID=com.dippo.hermes
installedTeam=<same Team as targetTeam>
teamsMatch=false
preferredBundleID result: nil
Constructed mangled bundleID: com.dippo.hermes.<Team>
effectiveParent: com.dippo.hermes
appendTeamID: true
```

This reads the actual stored InstalledApp record at refresh time: the tracked
resigned ID is already correct and agrees with iOS. The refresh target begins as
`com.dippo.hermes`; the provisioning/application-identifier suffix becomes wrong
inside profile selection. It is not evidence of a stale suffixed installed-app
record. The original failed import's record before the successful replacement was
not captured, so its historical contents are not claimed.

The Apple portal list contains both `com.dippo.hermes` and
`com.dippo.hermes.<Team>`. The old suffixed App ID is still registered and is reused
by the failed refresh. An Apple portal registration is not an installed duplicate.
Removing that registration would not fix the code path: the selected suffixed ID
would be registered again if absent. No portal registrations/profiles were deleted.

There is one visible Talaria app record and no duplicate physical app. An exhaustive
SQL duplicate-row check was unavailable: `devicectl` could not enumerate SideStore's
shared database, and its supported **Export Database** action failed with
`CoreDataExport: AltStoreCore bundle not found`. The export did not reset or replace
the database. The observed record used by Refresh is nevertheless directly verified
by the database-lookup trace above.

### Root cause and supported-fix assessment

This is a SideStore refresh limitation in the installed build. Its
[profile-selection implementation](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift)
requires the saved resigned ID to contain the Team identifier, even when the
stored and target Teams are equal. Thus its `teamsMatch=false` does not establish
an actual account/Team mismatch for this unsuffixed app.

**Append Team ID off** affects the current import operation's context. It is not a
persistent per-app refresh preference. The successful import stores the resulting
unsuffixed resigned ID correctly. The normal refresh pipeline omits user
customization and starts with `appendTeamID=true`. Its profile-only completion
updates dates without correcting the saved resigned identifier. These behaviors
are visible in the matching [customization operation](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Core/Operations/PipelineOperations/UserCustomizationOperation.swift),
[operation context](https://github.com/SideStore/SideStore/blob/6032424a0e56c1c319762e786099bdd9186a238b/SideStore/Core/Operations/OperationContexts.swift),
and refresh pipeline/InstalledApp sources inspected at that same commit.

There is no incorrect tracked identifier to repair. No supported configuration or
registration correction was found that changes this normal-refresh behavior while
keeping `com.dippo.hermes`. Resetting SideStore metadata would not remove the suffix
condition. Talaria's unchanged unsigned IPA already imports and re-signs correctly;
no packaging defect or rebuild reason was established.

The GitHub latest non-prerelease release endpoint still identifies `0.7.0-alpha`
(published 2026-09-15), matching the installed stable-channel build. The current
[development profile-selection source](https://github.com/SideStore/SideStore/blob/develop/SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift)
also retains the suffix condition at inspection time. No SideStore replacement,
custom build, database patch or identity change was attempted. A supported upstream
fix followed by physical normal-refresh validation is required to clear this gate.

### Refresh outcomes and preservation

Ordinary Refresh was reproduced at 10:10 and again at 10:14 with detailed logging.
Both reported UI success while renewing the suffixed identity. At 10:14:48,
`misagent_install` succeeded and SideStore completed its operation, but the selected
profile was for `com.dippo.hermes.<Team>` with expiry 2026-10-12 15:14:48 UTC.
**Normal Refresh: FAIL. Diagnostic repeat: FAIL.** No correct first cycle occurred,
so the requested second cycle after a successful repair was not performed. The
requirement that no wrong-bundle profile be generated was not met.

No manual IPA import was used in this follow-up. The last verified correct profile
remains the 09:59 re-import profile from the preceding milestone, with recorded
expiry 2026-10-12 14:59:05 UTC. The newer seven-day UI date is not accepted as its
renewal. Raw provisioning-profile bytes were not extracted in this follow-up.

Temporary verbose/per-step logging settings were returned to their prior off state;
Tailscale was restored. Talaria launched as `com.dippo.hermes` with Mac Studio
Connected, no re-pair prompt and existing canonical history. Final physical
preservation/message observations are recorded below. The prior manual re-import
workaround remains the only verified maintenance path for this exact identity.
At that earlier milestone, normal-refresh acceptance and public-Git privacy
remained unresolved. Both are addressed by the later patched-SideStore validation
and [public release handoff](PUBLIC_RELEASE_HANDOFF.md).


Final follow-up checks at 10:16–10:18: device inventory and launch confirmed
`com.dippo.hermes` with no suffixed Talaria. One saved Mac Studio host remained
Connected; all three original bots and canonical chat entries were visible. Older
messages and the preceding update/re-sign replies remained in the same conversation.
A new message received `TALARIA_REFRESH_DIAG_OK` at 10:17 without credential entry
or re-pairing. Host/profile/reasoning/appearance/haptics/notification/simulation
preferences matched the earlier milestone. No duplicate/corrupt state appeared in
inspected screens. **Useful app-container preservation: PASS. Keychain auth
preservation: PASS.** These runtime passes do not convert incorrect provisioning
into a successful normal refresh.
