Talaria is MAJOR//MINOR's native iPhone companion for Hermes on your Mac: persistent
streaming chat, Bot Mode management, tasks/status, attachments and dictation through
a private authenticated Tailscale bridge. Includes the self-hosted bridge package,
installation guides and MIT-licensed source.

The public IPA's permanent bundle ID is `xyz.majorminor.talaria` (0.1.0/build 1).
It is a separate application from the legacy development installation; this release
does not migrate existing legacy data or Keychain credentials.

Use official SideStore with its default Team-ID suffix. Source analysis predicts
normal new-user installation and Refresh without a patch; a second-account physical
install and public-ID signing/Refresh have not been tested. The optional SideStore
patch is retained for advanced same-Team unsuffixed installations, not required
by the default new-user path. No patched SideStore binary is distributed.

Requires an awake, logged-in Mac with an audited Hermes installation, private
Tailscale HTTPS and personal Apple signing. No App Store distribution, APNs push
or guaranteed background execution. The new identity passed Simulator/build and
unsigned packaging checks; the owner's physical phone was not used or changed.

Check downloads against SHA256SUMS.txt and start with docs/INSTALL.md and
docs/SIDESTORE_USER_GUIDE.md. This is an early personal-install prerelease.
