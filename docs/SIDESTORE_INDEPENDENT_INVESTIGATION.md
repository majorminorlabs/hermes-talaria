# SideStore Refresh: independent investigation

> Historical device evidence. Legacy development identifier: `com.dippo.hermes`.
> The public release now uses `xyz.majorminor.talaria`. These observations concern
> the existing legacy installation; they do not validate the new public identity.
> That physical installation is preserved untouched during public release preparation.

Date: 2026-10-05. Scope: why SideStore's normal **Refresh** does not renew
Talaria (`com.dippo.hermes`), and what can make it do so. This investigation
rechecked the earlier diagnosis in [SideStore validation](SIDESTORE_VALIDATION.md)
from SideStore/SideSign source, device logs and the phone's installed profiles.
It did not rely on that diagnosis.

User-facing install, refresh and migration steps derived from this investigation
are in the [SideStore user guide](SIDESTORE_USER_GUIDE.md). A recheck at 12:30 CDT
the same day found the upstream branch heads unchanged. It also found that release
0.6.4 contains the same regression. The patch still applies to `0.7.0-alpha` and
`develop`.

Private signing values are redacted: `<TEAM>` is the free Personal Team ID.
It is the same team for Xcode, SideStore and all profiles below. Times are UTC
unless stated.

## Summary

| Question | Answer |
| --- | --- |
| Root cause | A SideStore regression in `getPreferredBundleID` (`FetchProvisioningProfilesOperation.swift`). It requires an installed app's saved bundle ID to *contain* the Team ID before Refresh will reuse it. Refresh then falls back to "append Team ID", which is always on during Refresh. |
| Classification | SideStore bug. It is not a Talaria defect, a packaging issue, or an identity-design flaw. |
| Introduced | SideStore commit `2873e2ec` (2026-07-29), *"diag: added more logging for fetch provisioning profiles operation"*. This commit changed AltStore's rule from `team matches OR (no team AND suffix)` to `(team matches OR no team) AND suffix`. |
| Fixed upstream? | No. The rule is unchanged in 0.7.0-alpha (Stable), `develop`/`nightly` (`0dd743f7`, 2026-09-20), `main` and `staging`. No issue or PR reports it. AltStore (`marketplace` branch) still has the correct rule. |
| Does the legacy development identifier `com.dippo.hermes` need to change to fix Refresh? | No. The public identity decision is separate. |
| Smallest fix | A one-line SideStore change that restores AltStore's rule: [`docs/sidestore/0001-restore-preferred-bundle-id-team-rule.patch`](sidestore/0001-restore-preferred-bundle-id-team-rule.patch). |
| Can normal Refresh work? | **Yes.** On the physical iPhone with patched SideStore: two single-app Refreshes and one Refresh All renewed `com.dippo.hermes`, with data and Keychain intact. See [Physical validation](#6-physical-validation). |

## 1. Talaria's identity and signing model

Verified from the project, the release IPA, an Xcode device build, the phone's
installed profiles and SideSign source.

| Concept | What it is | Talaria |
| --- | --- | --- |
| **Bundle ID** (`CFBundleIdentifier`) | What iOS keys an installed app on. It decides which data container an install or update reuses. | `com.dippo.hermes` (`PRODUCT_BUNDLE_IDENTIFIER`; release IPA `Info.plist`). Version 0.1.0, build 1. |
| **Team ID** | The Apple developer team that owns App IDs, certificates and profiles. | The free Personal Team `<TEAM>`. SideStore's own bundle ID (`com.SideStore.SideStore.<TEAM>`) and every Talaria profile carry the same team. |
| **App ID** | A developer-portal registration of a bundle ID under a team. Free teams can only register explicit (non-wildcard) App IDs. | `com.dippo.hermes`, registered by Xcode. Profiles named *iOS Team Provisioning Profile: com.dippo.hermes* exist from both Xcode (Oct 3) and SideStore (Oct 5). SideStore's first default import also registered a second, unwanted App ID: `com.dippo.hermes.<TEAM>`. |
| **Application identifier** | The `application-identifier` entitlement in the code signature: `<TEAM>.<bundle ID>`. It must match the installed profile. | `<TEAM>.com.dippo.hermes` |
| **Provisioning profile** | A 7-day free-team profile. It binds the App ID, certificates and device, and allows `get-task-allow` and the keychain group `<TEAM>.*`. iOS refuses to launch the app without a valid matching profile. | It must be for App ID `<TEAM>.com.dippo.hermes`. A profile for `…hermes.<TEAM>` does not apply to Talaria. |
| **Keychain access group** | The group a Keychain item belongs to. Without an explicit group, items go into the first `keychain-access-groups` entry, or the application identifier if there is none. | Talaria sets no group. `KeychainBridgeCredentialStore` uses service = bundle ID and account = host ID. Items live in `<TEAM>.com.dippo.hermes`. |

**Release IPA.** `Talaria-v0.1.0.ipa` (SHA-256 `724a429f…e8c8`) is completely
unsigned. It has no code signature, no entitlements blob and no
`embedded.mobileprovision`. `Payload/Hermes.app` contains the binary,
`Info.plist`, `PkgInfo` and assets, with no extensions, frameworks or app groups.
The archive's `SigningIdentity` and `Team` are empty. Every entitlement therefore
comes from whoever signs it.

**Xcode and SideStore produce the same identity.** An Xcode Debug-iphoneos
build of Talaria is signed with exactly `application-identifier =
<TEAM>.com.dippo.hermes`, `com.apple.developer.team-identifier = <TEAM>` and
`get-task-allow = true`. SideSign (SideStore's signer, `CodeSignerAPI.swift`
at the pinned commit `a731c0d5`) starts from the profile's entitlements. It
removes every key the app doesn't declare, except `application-identifier`,
`team-identifier` and `get-task-allow`. Talaria declares none, so SideStore signs
it with the same three entitlements. The bundle ID, application identifier,
team and default Keychain group are therefore identical, and iOS treats the
SideStore install as an update of the Xcode app. Only the signing certificate
differs. Both certificates belong to the same team, and iOS does not key data or
Keychain on the certificate. This matches the earlier physical result: data and
Keychain authentication survived the switch.

Talaria has no entitlements that affect SideStore's feature/App ID updates (no
app groups, iCloud, push and so on). There is nothing to fix in the Xcode
project or the IPA.

## 2. SideStore source paths

Source: [SideStore `6032424a`](https://github.com/SideStore/SideStore/tree/6032424a0e56c1c319762e786099bdd9186a238b).
This is the exact build on the phone, `0.7.0-20260911.328+6032424a`, which the
Stable selector installs; release tag `0.7.0-alpha`.

### Pipelines (`OperationStepDefinition.swift`)

- **Install / update (IPA import):** `userCustomization` → download →
  verify → stage → `updateAppCertificate` → `verifyCertificate` → … →
  **`fetchProvisioningProfiles`** → … → `resignApp` → … → `installApp`.
- **Refresh:** `updateAppCertificate` → `verifyCertificate` →
  **`fetchProvisioningProfiles`** → `refreshApp`. **There is no
  `userCustomization` step.**

### Where each decision is made

| Decision | Location | Behavior |
| --- | --- | --- |
| Context defaults | `OperationContexts.swift:245–266` | `customBundleIdentifier = nil`, **`appendTeamID = true`**, `targetBundleIdentifier = customBundleIdentifier ?? bundleIdentifier`. |
| Per-operation setup | `PipelineRunner.performPipeline` (`:274–296`) | For an installed app (Refresh), it copies `app.customBundleIdentifier`. **`appendTeamID` is never read from storage.** |
| Append Team ID and custom ID | `UserCustomizationOperation` | Runs only in install/update, and only when **Settings → Customize AppID** is on. It sets `context.appendTeamID` from the checkbox. A custom ID equal to the IPA's own ID is stored as `nil`. |
| Choice of App ID | `FetchProvisioningProfilesOperation.provisionAndFetchProfile` (`:130–154`) | Uses `getPreferredBundleID` if it returns a value. Otherwise it uses `target + "." + team` when `appendTeamID` is true, or `target` when false. |
| Reuse of the saved ID | `getPreferredBundleID` (`:91–128`) | Finds the `InstalledApp` whose `customBundleIdentifier` or `resignedBundleIdentifier` equals the target. Reuses its `resignedBundleIdentifier` only if **`(team matches OR team == nil) AND resignedBundleIdentifier.contains(team)`**. |
| App ID registration | `registerAppID` (`:185–222`) | Reuses the portal App ID with that exact identifier, or registers a new one. |
| Profile | `DeveloperPortalProxy.downloadProvisioningProfile` | Each call returns a fresh 7-day profile for the chosen App ID. |
| Signed identity | `ResignAppOperation.prepareAppBundle` | Rewrites `CFBundleIdentifier` to the selected profile's App ID, then signs with SideSign. |
| Installed-app record | `InstallAppOperation.fetchOrCreateApp` (`:200–240`) | Saves `resignedBundleIdentifier` (from the resigned bundle), `customBundleIdentifier` and **`team = active team`**. |
| Refresh install | `RefreshAppOperation` | Installs every fetched profile through misagent. It then calls `installedApp.update(provisioningProfile: profiles.values.first!)`, which updates only the dates. **It never checks that the profile's App ID matches the installed app**, so the UI shows "7 days" after a wrong refresh. |

### Why import works and Refresh does not

**Import with Append Team ID off.** The customization step sets
`appendTeamID = false`. `getPreferredBundleID` finds the record, but
`teamsMatch` is false because the saved ID lacks the suffix. The fallback
therefore uses `target` without a suffix: `com.dippo.hermes`. That is correct,
but only because the customization step just ran.

**Refresh.** There is no customization step, so `appendTeamID` stays at its
default `true`. `getPreferredBundleID` finds the correct record
(`resigned = com.dippo.hermes`, `team = <TEAM>`). The team comparison is true,
but the `.contains(team)` condition is false, so it returns `nil`. The fallback
then builds `com.dippo.hermes.<TEAM>`, reuses that unwanted App ID, and installs
its profile. The installed app's real profile is not renewed.

**Default import (Append on).** The app becomes `com.dippo.hermes.<TEAM>`, a
different app to iOS. Here, Refresh works on stock SideStore: the saved ID
contains the team. This is the path SideStore was tested around. It cannot keep
an existing `com.dippo.hermes` installation.

### The regression

AltStore's rule, still current on AltStore's `marketplace` branch, says *reuse
the saved ID if this team installed it*:

```swift
let teamsMatch = installedApp.team?.identifier == team.identifier
    || (installedApp.team == nil && installedApp.resignedBundleIdentifier.contains(team.identifier))
// "This app is already installed with the same team, so use the same resigned bundle
//  identifier as before ... to prevent it from installing as a new app."
```

SideStore commit [`2873e2ec`](https://github.com/SideStore/SideStore/commit/2873e2ec6a798543c802aead805a2e2a052a57d8)
(a logging change) rewrote the rule as:

```swift
let teamsMatch = (installedApp.team?.identifier == team.identifier || installedApp.team == nil)
                 && installedApp.resignedBundleIdentifier.contains(team.identifier)
```

The suffix check used to be a fallback for records with no team; it is now
mandatory. One month later, [`f3a18d61`](https://github.com/SideStore/SideStore/commit/f3a18d61efae65b05dc935fff75b89225efdb0ff)
made **Append Team ID** optional at import. Every app installed with it
unchecked is now refreshed under the wrong App ID. The two changes are
incompatible. The same lookup also chooses the App ID for SideBackup-based
backup/restore/deactivate, so those flows are probably affected for unsuffixed
apps too. That was inferred from the code; it was not tested.

## 3. Append Team ID

- **When it applies:** only in `UserCustomizationOperation`. That means install
  or update of an IPA/source app, and only when **Settings → User Customizations
  → Customize AppID** is enabled.
- **Install-only?** Yes. It sets a field on the operation's context.
- **Persisted per app?** No. Neither `InstalledApp` nor `UserDefaults` stores it.
  A same-as-original custom ID is stored as `nil`.
- **Does Refresh honor it?** No. Refresh has no customization step and starts
  from `appendTeamID = true`.
- **Does Refresh rebuild the identifier on its own?** Yes, whenever
  `getPreferredBundleID` returns `nil`. For unsuffixed IDs that is always.
- **Does turning it off create an App ID that Refresh can use?** It creates and
  uses the correct App ID (`com.dippo.hermes`, already registered by Xcode).
  Refresh would reuse it if `getPreferredBundleID` returned the saved ID; the
  regression prevents that.
- **Stale state from the first import?** The failed default import left the App
  ID `com.dippo.hermes.<TEAM>` on the portal. The installed-app record is not
  stale: device logs show `resigned = com.dippo.hermes` and `team = <TEAM>` at
  Refresh time. Removing that App ID would not help; Refresh would register it
  again.
- **Is it meant for this use case?** Yes. Upstream issue
  [#1385](https://github.com/SideStore/SideStore/issues/1385) asked for control
  over the team suffix at install time, which led to the option. Docs don't say
  whether it is install-only. A per-install option that Refresh silently undoes
  is a defect, not a design.

## 4. Device state (read-only inspection)

iPhone 15 Pro Max, iOS 26.6.2. Tools: `devicectl` app inventory and container
reads; `pymobiledevice3 provision dump` (misagent CopyAll, read-only);
SideStore console logs copied from its Documents folder.

**Installed apps:**

- Talaria: `com.dippo.hermes` 0.1.0 (1), installed as `App.app`, i.e. by SideStore.
- SideStore: `com.SideStore.SideStore.<TEAM>`, `0.7.0-20260911.328+6032424a` (0700).
- `com.dippo.hermes.uitests.xctrunner`, the XCTest runner.

No suffixed Talaria is installed.

**Installed provisioning profiles for Talaria's App IDs** (15 profiles total on the device):

| Created (UTC) | App ID | Expires (UTC) | Origin |
| --- | --- | --- | --- |
| 10-03 13:16 | `com.dippo.hermes` | 10-10 13:16 | Xcode |
| 10-05 14:35 | `com.dippo.hermes.<TEAM>` | 10-12 14:35 | Failed default import |
| 10-05 14:43 | `com.dippo.hermes` | 10-12 14:43 | Import, Append off |
| 10-05 14:50 | `com.dippo.hermes.<TEAM>` | 10-12 14:50 | **Refresh** |
| 10-05 14:59 | `com.dippo.hermes` | 10-12 14:59 | Manual re-import, Append off |
| 10-05 15:10 | `com.dippo.hermes.<TEAM>` | 10-12 15:10 | **Refresh** |
| 10-05 15:14 | `com.dippo.hermes.<TEAM>` | 10-12 15:14 | **Refresh** |

All Talaria profiles have `<TEAM>`, `get-task-allow`, keychain group `<TEAM>.*`
and no app groups. **Every Refresh installed only a suffixed profile.** Before
this fix, the newest valid profile for the installed app expired
**2026-10-12 14:59 UTC**.

**SideStore's own log of the 10:14 CDT Refresh** (independently re-read):
`installedResignedID=com.dippo.hermes, installedTeam=<TEAM>, targetTeam=<TEAM>,
teamsMatch=false` → `preferredBundleID result: nil` → `Constructed mangled
bundleID: com.dippo.hermes.<TEAM> (… appendTeamID: true …)`. The 09:59 re-import
logged `appendTeamID: false` → `com.dippo.hermes`.

**SideStore database:** it lives in the app-group container, which `devicectl`
will not list. The record's fields are visible in the log line above. There is
one Talaria entry in My Apps.

**App IDs:** profiles exist for both `com.dippo.hermes` and
`com.dippo.hermes.<TEAM>`, so both App IDs are registered. The portal itself was
not queried (that needs Apple credentials).

## 5. Solution candidates, least to most invasive

| | Option | Verdict |
| --- | --- | --- |
| A | Correct SideStore state or settings | **Not possible on stock 0.7.** No setting reaches Refresh. The record is already correct. The `.contains(team)` test cannot pass for `com.dippo.hermes`. |
| B | Different install sequence (reset metadata, re-import) | **No.** Any install that keeps `com.dippo.hermes` produces the same record, and Refresh ignores it. Deleting records risks SideStore treating Talaria as a new app. |
| C | Different IPA packaging | **No.** Refresh never reads anything from the IPA that could change the choice, and the unsigned IPA is already correct. |
| D | Newer SideStore | **Not available.** `develop`/`nightly` (2026-09-20), `main` and `staging` all keep the rule. There is no newer release and no open PR. |
| E | **Minimal SideStore patch** | **Works.** It restores AltStore's rule in `getPreferredBundleID`. Details below. |
| F | Bundle-ID migration | **Not needed.** It is the only stock-SideStore route, and it loses the data container and Keychain (details below). |

**F in detail.** Switching to SideStore's default identity
(`com.dippo.hermes.<TEAM>`) or a new Talaria ID gives a new data container
(saved host, preferences and cache gone). It also gives a new application
identifier, so the Keychain token is unreachable and Talaria must re-pair.
iOS offers no migration across bundle IDs: shared containers would need a
pre-migration build plus app groups. The old app would also remain, and with the
XCTest runner that hits the free-account 3-app limit. A team-suffixed ID can't
be baked into a public IPA either, because every user's team differs. **By source analysis, public
users installing fresh with default settings get `com.dippo.hermes.<their team>`
and already refresh correctly on stock SideStore.** This was not physically tested. The defect only affects
installs that must keep an exact ID, such as this phone's pre-existing app.

### E: the patch

`SideStore/Core/Operations/PipelineOperations/FetchProvisioningProfilesOperation.swift`, `getPreferredBundleID`:

```diff
-            // Teams match if installedApp.team has same identifier as team (or team is nil)
-            // AND installedApp.resignedBundleIdentifier actually contains the team's identifier.
-            let teamsMatch = (installedApp.team?.identifier == team.identifier || installedApp.team == nil)
-                             && installedApp.resignedBundleIdentifier.contains(team.identifier)
+            // Teams match if installedApp.team has same identifier as team,
+            // or if installedApp.team is nil but resignedBundleIdentifier contains the team's identifier.
+            // An app installed by this team keeps its resigned bundle identifier on refresh, even when
+            // it has no Team ID suffix (e.g. installed with "Append Team ID" unchecked).
+            let teamsMatch = installedApp.team?.identifier == team.identifier
+                             || (installedApp.team == nil && installedApp.resignedBundleIdentifier.contains(team.identifier))
```

- **Faulty assumption:** that every same-team install carries the Team ID
  suffix. That stopped being true once the suffix became optional.
- **Effect on other installs:**
  - Suffixed installs: unchanged; `.contains` was already true.
  - A team change (record team ≠ current team): unchanged; it still constructs
    a new ID.
  - Unsuffixed installs: Refresh and backup now reuse the saved ID.
  - One edge case changes: re-importing an existing app *with* Append checked
    would keep the saved unsuffixed ID instead of adding the suffix. This
    matches AltStore's documented intent. An upstream PR could additionally
    honor an explicit customization choice during that pipeline.
- **Upstream hardening (optional):** `RefreshAppOperation` should refuse a
  profile whose App ID ≠ `installedApp.resignedBundleIdentifier`. Otherwise
  Refresh fails loudly instead of showing "7 days".
- **Custom build lifetime:** the custom build is needed only until upstream
  releases the fix. The patched SideStore refreshes and updates itself normally,
  because its own ID contains the team. Updating to an unpatched SideStore
  would bring the bug back. The patch is small, self-explanatory and
  upstreamable.

## 6. Physical validation

Performed 2026-10-05, 10:44–11:12 CDT, on the same iPhone. LocalDevVPN was used
for SideStore operations and Tailscale for Talaria. Talaria was never uninstalled,
reinstalled or re-imported.

**Backups first.** These were read-only copies to the owner-only directory
(private location withheld):

- Talaria: preferences and 14 cached bridge snapshots.
- SideStore: pairing file, preferences and anisette configuration.

Keychain items can't be exported. They are preserved by never deleting the app.

**Patched SideStore.** It was built from `6032424a` plus the patch, using the
repo's own `make build / fakesign / ipa` flow with Xcode 26.6.

| Artifact | SHA-256 |
| --- | --- |
| Patched IPA | `47e06b49…7f6f4f` |
| Official 0.7.0-alpha IPA, kept for rollback | `e334f86e…22b5` (matches GitHub's release digest) |

Compared with the official IPA, only the following differ. The file layout and
`Info.plist` key set are identical.

- the patched hunk;
- the plain `0.7.0` version string (CI decorates the official one);
- Xcode/SDK build metadata.

The patched IPA was served once on the LAN and opened with
`sidestore://install?url=` by `devicectl`. The owner tapped **Install**, then
**Keep App Extensions (Register App ID for Each Extension)** to match the
existing widget App ID, then left AppID Customization unchanged
(`com.SideStore.SideStore`, Append Team ID on). SideStore re-signed itself as
`com.SideStore.SideStore.<TEAM>`, reusing its existing App IDs.

The self-install then hung until SideStore was swiped away. This is the known
0.7.0-alpha keep-alive hang, fixed upstream in `0c7a9bdc`. iOS then completed
the install. On launch, SideStore confirmed the new bundle path and saved its
staged record. Its pairing file, data and My Apps list survived. iOS now
reports SideStore as `0.7.0` (0700). Its sign-in session did not survive: the
owner had to **sign in again with 2FA**.

| Check | Result |
| --- | --- |
| Refresh 1 (10:59 CDT): Talaria's days badge | Log: `preferredBundleID result: com.dippo.hermes` → `Using preferredBundleID`. Existing App ID `com.dippo.hermes` reused. Device received profile `<TEAM>.com.dippo.hermes`, expiring **10-12 15:59:47 UTC**. **PASS** |
| Refresh 2 (11:09 CDT): days badge | Same path. Profile expires **10-12 16:09:03 UTC**. No prompts. **PASS** |
| Refresh All (11:12 CDT) | Talaria: `com.dippo.hermes`, expires 10-12 16:12:18. SideStore refreshed itself on its unchanged path (`com.SideStore.SideStore.<TEAM>` + `.AltWidget`, expires 10-12 16:12). **PASS** |
| Wrong-ID profiles after the fix | None. The last `com.dippo.hermes.<TEAM>` profile was created at 15:14 UTC, before the fix. |
| Renewed profile covers the installed binary | Each renewed profile contains the same two team certificates as the 14:59 profile Talaria was installed with. |
| Installed identity | Still `com.dippo.hermes` 0.1.0 (1), with an unchanged bundle path, i.e. no reinstall. No suffixed duplicate. |
| App-container data | The preferences file is byte-identical to the pre-change backup. The owner confirmed the saved Mac Studio host, bots, history and preferences are unchanged. |
| Keychain authentication | Mac Studio was Connected with no pairing prompt. The bridge recorded new runs authenticated by its single iPhone credential (the same one behind all 101 previous Talaria commands). The bridge still has two credentials (operator, iPhone), so there was no re-pairing. |
| Fresh Hermes messages | Bridge run #30 (11:02:31 CDT): `TALARIA_FIXED_REFRESH_OK`. Run #31 (11:10:54): `TALARIA_SECOND_REFRESH_OK`. Both in the existing canonical bot chat. |

Not tested: waiting for a profile to actually expire, a reboot, cellular-only
refresh, background (automatic) refresh, and installs of other apps with
extensions.

## 7. Recommendation

1. **Keep the existing legacy development identifier `com.dippo.hermes` on the tested phone.** The investigated legacy build needed no
   change.
2. **Use the patched SideStore build** on this phone until upstream ships the
   fix. Weekly maintenance is now the ordinary SideStore Refresh, or Refresh
   All, with LocalDevVPN connected.
3. **Submit the patch upstream.** It applies cleanly to SideStore `develop`
   (`0dd743f7`). It wasn't submitted, because nothing may be published without
   approval. Suggested companion change: make `RefreshAppOperation` reject a
   profile whose App ID differs from the installed app's.

### Operating notes and risks

- **Don't let SideStore update itself** to an unpatched build. That includes
  Stable/Nightly updates and any re-install from iloader. The bug would return.
  If an update is needed, rebuild it from the new source plus this patch
  (`git apply`, then `make build fakesign ipa`). Install it the same way, then
  swipe SideStore away if the self-install hangs.
- **Rollback:** install `build/sidestore/SideStore-0.7.0-alpha-official.ipa` the
  same way. Talaria would then need the manual re-import with Append off again.
- After any SideStore reinstall, **sign in again** before the next refresh is
  due.
- **Customize AppID** is no longer needed for Talaria refreshes. It is still on.
  If left on, every future IPA import shows the dialog. For SideStore's own
  IPA, keep its ID and leave **Append Team ID checked**.
- **Apps with extensions:** the 0.7.0-alpha base lacks `develop`'s
  extension-suffix fix (`6bc8b347`). Combined with this patch, extensions of
  *unsuffixed* apps would get the parent's App ID. Only SideStore (suffixed,
  unaffected) and Talaria (no extensions) are managed here. Prefer a `develop`
  base for other apps.
- The unused App ID `com.dippo.hermes.<TEAM>` is still registered on the
  portal. It is harmless; leave it.
- The free-account 3-app limit is currently filled by SideStore, Talaria and
  the XCTest runner.

### Migration implications

None. The bundle ID, application identifier, Team, data container and Keychain
group are unchanged. A bundle-ID migration would give a new container and an
unreachable Keychain token, so it would cost the saved host, preferences and
pairing. It would gain nothing over the patch.

## 8. Artifacts

- `docs/sidestore/0001-restore-preferred-bundle-id-team-rule.patch`
  (committed). It applies to `6032424a` and `develop`.
- `build/sidestore/` (git-ignored, local only): both IPAs, `SHA256SUMS.txt` and
  `BUILD_REPORT.md` (toolchain and commands).
- Raw SideStore console logs and profile dumps contain account/device signing
  metadata. They were kept privately and not committed.
