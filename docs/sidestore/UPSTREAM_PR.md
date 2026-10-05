# Draft SideStore issue and pull request

Not submitted. This file holds ready-to-paste text for
[SideStore/SideStore](https://github.com/SideStore/SideStore). It targets
`develop`; the patch applies cleanly to `develop` `0dd743f7` and `0.7.0-alpha`
`6032424a`. Submit only with the owner's approval. Before submitting, check again
that no equivalent issue or PR has appeared.

Use a neutral commit author when submitting. The local patch's placeholder author
is `Talaria investigation <noreply@localhost>`.

---

## Issue

**Title:** Refresh renews the wrong App ID for apps installed with "Append Team ID" unchecked

**Summary**

An app installed with **Customize AppID** enabled and **Append Team ID**
unchecked is signed as its plain bundle ID (e.g. `com.example.app`). A later
**Refresh** or **Refresh All** registers or reuses `com.example.app.<TEAM>`
instead, and installs that profile. The UI reports success and "7 days", but the
installed app's real profile is never renewed. The app stops launching when the
original profile expires.

**Environment**

- SideStore 0.7.0-alpha (`0.7.0-20260911.328+6032424a`, Stable), iOS 26.6.2,
  free Personal Team.
- The same code is present on `develop`/nightly `0dd743f7`, `main` `7488d5cb` and
  0.6.4 (source inspection).

**Steps to reproduce**

1. Settings → User Customizations → enable **Customize AppID**.
2. Install any IPA without extensions. In **AppID Customization**, keep its bundle
   ID, **uncheck Append Team ID**, and Confirm. The app installs as
   `com.example.app`.
3. In My Apps, tap the app's days badge (or Refresh All).

**Expected:** a fresh profile for `<TEAM>.com.example.app`.

**Actual:** a fresh profile for `<TEAM>.com.example.app.<TEAM>`; a second App ID
is registered on first occurrence. The verbose log shows:

```text
[FetchProvisioningProfiles] preferredBundleID check: app=com.example.app,
  installedResignedID=com.example.app, installedTeam=<TEAM>, targetTeam=<TEAM>, teamsMatch=false
[FetchProvisioningProfiles] preferredBundleID result: nil
Constructed mangled bundleID: com.example.app.<TEAM> (… appendTeamID: true …)
```

**Root cause**

`getPreferredBundleID` (`FetchProvisioningProfilesOperation.swift`) only reuses
the installed app's `resignedBundleIdentifier` when it *contains* the Team ID,
even when `installedApp.team` is the current team:

```swift
let teamsMatch = (installedApp.team?.identifier == team.identifier || installedApp.team == nil)
                 && installedApp.resignedBundleIdentifier.contains(team.identifier)
```

This was introduced in `2873e2ec` ("diag: added more logging for fetch
provisioning profiles operation"). Before it, the rule was AltStore's: same team,
**or** (no team **and** suffix). `f3a18d61` later made Append Team ID optional. The
refresh pipeline has no user-customization step, and `appendTeamID` is not
persisted, so Refresh starts from `appendTeamID = true`. When
`getPreferredBundleID` returns `nil`, `provisionAndFetchProfile` therefore builds
`<id>.<TEAM>`.

`RefreshAppOperation` then calls `installedApp.update(provisioningProfile:)` with
that profile without comparing its App ID to `resignedBundleIdentifier`. That is
why the UI shows a fresh expiry.

The same lookup also selects the App ID for SideBackup backup/restore/deactivate.
By inspection, those are likely affected for unsuffixed apps as well; this was
not tested.

---

## Pull request

**Title:** Restore AltStore's preferredBundleID team-match rule so Refresh keeps unsuffixed App IDs

**Description**

Fixes #<issue>.

Since `2873e2ec`, `getPreferredBundleID` reuses an installed app's resigned
bundle identifier only when it contains the Team ID, even if `installedApp.team`
is the current team. Apps installed with **Append Team ID** unchecked (optional
since `f3a18d61`) keep an unsuffixed identifier. Refresh has no customization
step and defaults to `appendTeamID = true`, so it no longer reuses that
identifier. It provisions `<id>.<TEAM>` instead, leaving the installed app's
profile to expire while the UI shows a fresh expiry.

This restores AltStore's rule (still current on AltStore's `marketplace`
branch). A same-team install keeps its resigned identifier. The suffix check
applies only to records without a team.

```diff
-            let teamsMatch = (installedApp.team?.identifier == team.identifier || installedApp.team == nil)
-                             && installedApp.resignedBundleIdentifier.contains(team.identifier)
+            let teamsMatch = installedApp.team?.identifier == team.identifier
+                             || (installedApp.team == nil && installedApp.resignedBundleIdentifier.contains(team.identifier))
```

**Behavior by case**

| Installed record | Before | After |
| --- | --- | --- |
| Same team, suffixed ID | reuse | reuse |
| Same team, unsuffixed ID | **new `<id>.<TEAM>`** | reuse |
| Different team | new ID | new ID |
| No team, ID contains Team | reuse | reuse |
| No team, no suffix | new ID | new ID |

Only the same-team, unsuffixed case changes. Re-importing an existing unsuffixed
app with Append Team ID *checked* now keeps its saved identifier, as AltStore
does ("use the same resigned bundle identifier as before … to prevent it from
installing as a new app").

**Validation** (0.7.0-alpha `6032424a` + this patch, built with
`make build fakesign ipa`; iPhone 15 Pro Max, iOS 26.6.2, free team)

- SideStore installed over the existing install, keeping its own suffixed ID,
  data, pairing file and app list.
- An existing unsuffixed app (`com.example.app`-style, no extensions): two
  single-app Refreshes and one Refresh All. Each logged `preferredBundleID
  result: <unsuffixed id>`, reused the existing App ID and installed a profile for
  `<TEAM>.<unsuffixed id>`. No suffixed profile or App ID was created. The app was
  not reinstalled, and its data and Keychain items survived.
- SideStore refreshed itself on its suffixed ID during Refresh All (unchanged
  path).

**Not covered:** unsuffixed apps *with extensions* on the 0.7.0-alpha base
(`develop` has the extension-ID fix `6bc8b347`); SideBackup flows.

**Possible follow-up (not in this PR):** have `RefreshAppOperation` reject a
profile whose App ID differs from `installedApp.resignedBundleIdentifier`. A
future mismatch would then fail loudly instead of showing a fresh expiry.
