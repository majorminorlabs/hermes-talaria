# Mac Studio service setup

This guide installs a small persistent adapter between Talaria (the iPhone app) and the installed Hermes desktop API. Hermes remains the execution runtime. The bridge exposes only the mobile contract in [BRIDGE_API.md](../BRIDGE_API.md).

## Service layout and ownership

Run installation as the ordinary macOS account that owns Hermes, not with `sudo`. The installer uses these locations:

| Data | Location |
|---|---|
| Installed bridge releases, current pointer, private config/state, backend token and mobile credential metadata | `~/Library/Application Support/HermesMobileBridge` (directory mode 0700; private files mode 0600) |
| Bounded lifecycle-only JSON logs (raw child stdout/stderr discarded) | `~/Library/Logs/HermesMobileBridge` |
| User launchd jobs | `~/Library/LaunchAgents/xyz.majorminor.talaria-mobile-bridge.plist` and `~/Library/LaunchAgents/xyz.majorminor.talaria-mobile-backend.plist` |
| Installed Hermes source (default) | `~/.hermes/hermes-agent` |

The installer creates a standalone Python environment for the bridge. It does not install packages into the Hermes virtual environment, alter Hermes source, or change existing Hermes gateways. It configures a dedicated Hermes desktop backend process on loopback, using the selected Hermes home (by default the existing `~/.hermes`) and a private workspace. Each profile exposed by the bridge must have its own exclusive backend; avoid directing multiple bridge profiles at a single dashboard listener. The backend's structured session socket has one event owner, so do not attach an independent desktop client to the same live session while expecting both clients to control/observe it reliably.

The automatic installer exposes the default profile and only explicitly authorized boards (`--board default` for the current Studio). Additional profiles need separate exclusive backends and private configuration. Private configuration, state, and secret files are mode restricted to the service user. The state directory contains the durable run/event journal and credential hashes; preserve it across updates and restarts. Keep it on local Studio storage, outside synchronized folders, and include it in a protected backup plan. Logs are stored separately and must not be copied into public support bundles without review. The supervisors discard raw child stdout/stderr and log only service start/stop/exit metadata. Each role uses a 1 MiB lifecycle log with two rotated backups. This prevents request bodies, authorization headers and upstream token URLs from entering those logs; private bridge journal/debug data remains protected state, not a public support bundle.

## Install and inspect

The installer accepts audited Hermes commit `4bb9e57bfde8a0affb5553eff13ed6e1f14147f1` (full Bot Mode/media) or legacy `2a4c9afd7bd` and its existing Python environment. It uses the existing `~/.hermes` home by default and starts a distinct desktop backend process on loopback. It does not replace or edit any existing gateway or upstream source. From a clone of this repository:

```sh
./scripts/install-bridge.sh \
  --hermes-source "$HOME/.hermes/hermes-agent" \
  --hermes-home "$HOME/.hermes" \
  --bridge-port 8787 \
  --hermes-port 9119 \
  --bot-management --bot-chat --bot-mode --board default
./scripts/status-bridge.sh --json
```

Optional `--workspace PATH` sets the dedicated backend's working directory. The default workspace is private under the installation root. Add one `--board NAME` per Kanban board you intentionally authorize for the mobile profile. Review directory and port choices before installation. To use an alternate Python 3.11+ interpreter, pass `--python PATH`.

`status-bridge.sh` reports the service processes, local bridge/Hermes health and the HTTPS endpoint configuration. It does not return a mobile bearer token. Service controls are `start-bridge.sh` and `stop-bridge.sh`; update with `update-bridge.sh` after checking for active or uncertain runs. `uninstall-bridge.sh` removes the jobs and runtime but retains configuration, state and mobile credential records. `uninstall-bridge.sh --purge` explicitly deletes those retained files.

The launchd jobs are per-user LaunchAgents with start-on-login and crash restart behavior. Apple documents that a user LaunchAgent runs on behalf of the logged-in user and is terminated at logout; it is not a pre-login system daemon. This keeps the service under the Hermes owner account and avoids root permissions. If the Mac reboots, the jobs return when that account logs in. If the Mac must provide service before any login, that is a different root LaunchDaemon design and is not included here. [Apple's launchd guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) describes the user-session launch and logout behavior.

## Tailscale HTTPS

The bridge listens only on `127.0.0.1:8787`. Use Tailscale Serve as an HTTPS reverse proxy:

```sh
./scripts/configure-tailscale.sh
tailscale serve status
```

The intended mapping is HTTPS port 443 on the Studio's tailnet hostname to `http://127.0.0.1:8787`. Your URL has this form (replace this placeholder):

```text
https://your-mac.your-tailnet.ts.net
```

Use the URL printed by `configure-tailscale.sh` if the Studio's MagicDNS name changes. The helper checks the existing Serve configuration and refuses to replace unrelated routes; it does not enable Tailscale Funnel. Tailscale documents `tailscale serve --bg --https=443 http://127.0.0.1:8787` as a persistent background HTTPS reverse proxy to a loopback service. Serve terminates TLS using a certificate for the tailnet DNS name and keeps the endpoint within the tailnet. [Tailscale Serve CLI](https://tailscale.com/docs/reference/tailscale-cli/serve) · [Serve vs. Funnel](https://tailscale.com/docs/features/tailscale-funnel).

In the Tailscale admin console:

1. Enable MagicDNS and HTTPS certificates under DNS settings if they are not enabled.
2. Allow the intended iPhone/device identity to reach the Studio on TCP 443 in the tailnet access policy.
3. Keep Funnel disabled for this service. Serve makes the endpoint available within the tailnet; Funnel would make it reachable from the public internet.
4. Verify the configured route with `tailscale serve status`, and verify from the app using the HTTPS hostname while the phone is connected to Tailscale.

Tailscale HTTPS certificate provisioning requires enabling HTTPS in the tailnet and uses the Studio's `*.ts.net` MagicDNS name. Tailscale notes that device hostnames and the tailnet DNS name appear in the public Certificate Transparency ledger when a certificate is issued. This publishes the names, not access to the device; tailnet access controls still apply. Review the Studio machine name before enabling the certificate if it contains private identifying information. [Tailscale HTTPS certificates](https://tailscale.com/docs/how-to/set-up-https-certificates).

TLS is only the transport layer. The bridge still requires `Authorization: Bearer ...` for every API and event-stream request, checks the token's scopes/profile allowlist, and supports revocation. Do not add a certificate-validation bypass or send a bearer token in a URL. The app's production networking expects HTTPS without an ATS exception.

## Pair and revoke a phone

Create a credential for the app:

```sh
./scripts/pairing-token.sh --name iPhone
```

The helper records its generated token in a private, mode-0600 `mobile-pairing.json` file so it can be shown later; the bridge credential store retains only the token hash and registry metadata. The default output gives pairing instructions but redacts the token. Display it in a private interactive terminal only when ready to enter it directly on the phone:

```sh
./scripts/pairing-token.sh --show
```

Use **More → Hosts → Add Host** in Talaria. Enter the stable HTTPS URL and token. Talaria authenticates, then stores the bearer in the iOS Keychain. Do not send credentials in email/chat, paste them into source/config, or capture them in screenshots. Hermes provider keys and the upstream desktop token remain Studio-side. The pairing helper file is a protected plaintext token copy; after Talaria has saved its Keychain credential, remove the transfer copy with `./scripts/pairing-token.sh --forget-transfer`. Revoke the device token if the file is exposed.

List or revoke a device as needed:

```sh
./scripts/pairing-token.sh --list
./scripts/pairing-token.sh --revoke DEVICE_ID
```

Revocation is immediate for new authenticated requests. Removing a host from the phone only deletes the local Keychain credential and saved host record; revoke its Studio token separately if the device should lose access.

The transfer-only plaintext copy can be removed without revoking a paired phone:

```sh
./scripts/pairing-token.sh --forget-transfer
```

## Start, update, and remove

```sh
./scripts/start-bridge.sh
./scripts/stop-bridge.sh
./scripts/status-bridge.sh
./scripts/update-bridge.sh
./scripts/uninstall-bridge.sh
```

Updates install a fresh bridge release and environment while retaining the state database and private configuration. Close clients to new submissions and stop or reconcile active/uncertain chat work before updating. The helper checks all active/unknown states before staging and immediately before stopping; these are preflight snapshots, not an atomic maintenance lock against another client submitting concurrently. Unhealthy startup rolls back to the prior installed runtime. Uninstall retains state/credentials for a later reinstall unless `--purge` is supplied. Tailscale Serve is independently owned by the Tailscale client; inspect it before removing or changing the route. The setup helper refuses to overwrite a route it does not own.

## Failure checks

- **Bridge stopped, Hermes available:** restart the bridge job and check local service status. Persistent run IDs, cursors and device credentials come from the retained bridge state.
- **Hermes backend stopped, bridge available:** Home should distinguish Hermes unavailable from bridge unreachable. Restart the dedicated backend; the bridge reconnects. Do not launch another Hermes process on the same desktop port.
- **Phone cannot connect:** check that it is on the tailnet, MagicDNS resolves the Studio name, the tailnet policy permits TCP 443, Tailscale Serve shows the loopback proxy, and `status-bridge.sh` reports both local services healthy.
- **401/authentication required:** list the credential records and revoke/re-provision deliberately. Do not retry by substituting Hermes dashboard or provider credentials.
- **Run state after reconnect:** the bridge journal is canonical for bridge run identity and retained event replay. Keep its state directory. Expired event history requires the app to resynchronize a canonical snapshot.

## Removal

Run `./scripts/uninstall-bridge.sh` as the service user. It unloads and removes the two LaunchAgents and installed bridge runtime, retaining private configuration, state, and credentials by default. Use `--purge` only when you also intend to delete the bridge's durable IDs, replay journal, pairing metadata, and upstream secret files. Disable only the Tailscale Serve route created by this helper; do not run `tailscale serve reset` if the Studio has unrelated Serve routes. Existing Hermes services/gateways are not removed by bridge uninstall.
