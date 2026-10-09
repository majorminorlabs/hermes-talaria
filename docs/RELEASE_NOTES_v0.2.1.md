# Talaria v0.2.1

Talaria 0.2.1 / build 3 adds in-app approvals for Hermes command prompts.

- Approve once, approve for the session, or deny. Every tap is tied to that exact request.
- Late taps are rejected safely with “No longer pending” if the Mac answers first or Hermes times out.
- Swipe a pending approval on Now to Approve once or Deny; Stop is on the leading swipe.
- Requires Hermes with server-request approvals (4bb9e57 or newer). Older Hermes falls back to “Approve on your Mac.” Capability detection also supports newer Hermes builds that advertise the contract.
- The bridge includes capability detection and the local `reconcile-run` operator command for explicitly resolving orphaned unknown/uncertain runs with an audit record and coverage gap.
- Lock screen and notification approvals are not included, by design.

The approval implementation passed 100 Swift tests, 5 approval UI tests and
113 bridge tests (1 opt-in integration test skipped), plus physical approval
checks on the same functional source at 0.2.0 / build 2. See the
[validation record](https://github.com/majorminorlabs/tools-talaria/blob/v0.2.1/docs/IN_APP_APPROVALS_VALIDATION.md).
Version 0.2.1 / build 3 does not yet have a separate physical acceptance run.

Download `Talaria-v0.2.1.ipa` and verify `SHA256SUMS.txt`. The IPA and archive are
unsigned; use your own signing through
[SideStore](https://github.com/majorminorlabs/tools-talaria/blob/v0.2.1/docs/SIDESTORE_USER_GUIDE.md)
or [Xcode](https://github.com/majorminorlabs/tools-talaria/blob/v0.2.1/docs/XCODE_INSTALL.md).
Keep your installed app identity and Team stable to preserve local data.
The bridge source package is `hermes-mobile-bridge-v0.2.1.tar.gz`.

This remains a prerelease. iOS 18 runtime, stock SideStore/new-account signing
and expiry/refresh cases remain unverified. Live Activity updates have no
APNs/background guarantee. Existing release artifacts remain available.
