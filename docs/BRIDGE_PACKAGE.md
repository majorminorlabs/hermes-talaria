# Talaria Studio bridge package

This archive contains the Studio bridge, installer, service templates and setup
documentation. It contains no iPhone app, Hermes backend installation, saved host,
pairing token, private configuration or Python virtual environment.

## Set up

1. Install/configure an audited Hermes backend and Python 3.11+ on your Mac.
2. Extract this archive and change into `hermes-mobile-bridge-release`.
3. Run `./scripts/install-bridge.sh --bot-management --bot-chat --bot-mode --board default`.
4. Configure Tailscale HTTPS using `./scripts/configure-tailscale.sh`.
5. Check `./scripts/status-bridge.sh` and create a mobile credential using
   `./scripts/pairing-token.sh --name iPhone`.
6. Install Talaria separately and pair it through **More → Hosts → Add Host**.

Read [full installation](INSTALL.md), [Studio setup](STUDIO_SETUP.md),
[using Talaria](USING_TALARIA.md), [SideStore](SIDESTORE.md) and
[troubleshooting](TROUBLESHOOTING.md) for exact steps and validation.
Development builds require the full Talaria repository, not this bridge package.
License: [MIT](../LICENSE); dependency attributions: [notices](../THIRD_PARTY_NOTICES.md).
