# Optional Research Terminal setup

Research Terminal runs separately on the Mac. Talaria does not install it or
supply its credentials. Configure a real Hermes Research Orchestrator bot and
install the `research-terminal` skill using your existing Hermes setup.

Reuse an existing Research Terminal API bearer credential. Store it in an
owner-only plain-text file outside all repositories; do not put the token in a
profile configuration, launchd plist, phone form, screenshot or support bundle.
The file and parent directory must belong to the process user. Set file mode
`0600` and parent directory mode `0700` as appropriate for your secret store.

In the Orchestrator's machine-local profile `.env`, set the non-secret path and
base URL (replace both placeholders with your actual values):

```dotenv
RESEARCH_TERMINAL_API_TOKEN_FILE=/path/to/private/token-file
RESEARCH_TERMINAL_API_BASE_URL=http://127.0.0.1:8000/api/v1
```

Merge these names into that profile's `config.yaml`, retaining other settings:

```yaml
terminal:
  env_passthrough:
    - RESEARCH_TERMINAL_API_TOKEN_FILE
    - RESEARCH_TERMINAL_API_BASE_URL
```

Hermes binds environment variables to the selected bot. A global shell export
or bridge-wide credential does not replace this profile passthrough. The helper
reads the token file and sends an HTTP bearer header; it does not read Keychain.
Configure the API's `RESEARCH_HERMES_API_TOKEN_FILE` to use the same credential
where supported by your Research Terminal deployment. Never print its value.

After all live runs are idle, restart the dedicated Hermes backend so it reloads
the profile settings. The bridge's service start/stop commands control its
managed backend; check `status-bridge.sh` afterward. Do not interrupt an active
or uncertain run solely to reload credentials.

Validate a harmless existing-run status or corpus search directly through the
helper, then through **Bots → Research Orchestrator → Chat**. Do not start a new
research job for connectivity validation. An HTTP 401 points to credentials;
a missing token-file variable points to profile passthrough/readability. In
PostgreSQL mode the API must register the canonical authenticated route
`POST /api/v1/hermes/knowledge/search`; a 404 requires the backend compatibility
fix, not a phone change. The existing SQLite route remains supported.

The release does not bundle Research Terminal or its token. Detailed historical
fix/test evidence is retained in the full repository's BOT_MODE_VALIDATION.md
and patches/research-terminal-postgres-search/validation.md, excluded from the
Studio runtime package.
