# Writable Bot Chat validation — 2026-10-03

> Historical device evidence. Legacy development identifier: `com.dippo.hermes`.
> The public release now uses `xyz.majorminor.talaria`. These observations concern
> the existing legacy installation; they do not validate the new public identity.
> That physical installation is preserved untouched during public release preparation.

This milestone continues `28a5f59` on `codex/bot-mode-milestone`. Nothing was
pushed or published. Canonical lifecycle/source details are in
[BOT_MODE_AUDIT.md](BOT_MODE_AUDIT.md).

## Result and Studio deployment

One Chat tap on a visible bot now opens a writable persistent native canonical
`Bot Chat`, initializing a missing row with Hermes Desktop's hidden,
profile-following, eager-title lifecycle. No intro/model turn is sent during
initialization. Both Bots and main Chat return the same mobile conversation ID;
no generic default-profile chat is created as a fallback.

The existing guarded updater deployed the bridge after isolated validation.
Private configuration and existing SQLite databases were backed up using SQLite's
backup API in a private location (path withheld).
The `default` source now explicitly grants `bot_mode_roster:true` and
`bot_chat_control:true`. Credentials, journal and the existing private Tailscale
HTTPS route were preserved. Both dedicated services are healthy and advertise
Bot Mode, writable Bot Chat and modern clarifications. Installed Hermes remains
`4bb9e57bfde8a0affb5553eff13ed6e1f14147f1`.

| Bot | Native profile | Actual model/provider | Canonical result |
| --- | --- | --- | --- |
| Hermes | `default` | `gpt-5.6-luna` / `openai-codex` | Initialized from phone; message completed |
| Research Orchestrator | `research-orchestrator` | `gpt-6.1-sol` / `openai-codex` | Initialized from phone; message/tools completed; history reopened |
| Research Worker | `research-worker` | `gpt-5.6-luna` / `openai-codex` | Initialized/opened from phone; no production message requested |

Authenticated HTTPS reads and direct read-only source database checks confirmed
exactly one hidden `Bot Chat` row per profile and matching Bots/Chat IDs. All three
retain separate canonical identities and persistent source transcripts.
Live bridge records show one canonical mobile relationship for each. Exact-title
lookup is refreshed on opens/reads; the source root/tip relationship is checked.
Hidden/removed membership fails safely without deleting history or minting a
replacement. Source profile configuration remains native; no bot names/models
are hardcoded in production code.

## Physical iPhone results

The signed app was installed on the connected iPhone 15 Pro Max using local
signing settings and the phone's existing pairing. Actual XCTest actions exercised:

- **Research Orchestrator:** Bot detail, visibly hittable `research-terminal` skill
  row, enabled Chat, initialization/open, send, streamed response and tool activity.
  The run completed with 71 `assistant.delta` events and two started/completed
  tools: `skill_view` for the attached native-profile skill, then the Research
  Terminal helper's read-only `search "Hermes"`. The skill result identifies the
  actual `research-orchestrator` skill directory; this is source execution evidence,
  not a UI identity label. Actual session metadata retained `gpt-6.1-sol` and
  `openai-codex`.
- **Recovery:** background/home and foreground, termination/relaunch, reopen via
  Bots, then open from main Chat with the same response/history. Screenshots retain
  the streaming/tool panel and the reopened transcript. The live bridge relationship
  and stable conversation ID were independently checked.
- **Hermes:** initialize/open, safe identity-only send, streamed assistant response
  and completion (16 deltas). No tools were requested.
- **Research Worker:** initialize/open writable canonical chat, screenshot; no
  production model execution was requested for this bot.

All three distinct physical tests passed across the initial Hermes/Worker run and
corrected Orchestrator rerun. The first Orchestrator attempt failed only its skill
traversal assertion: full-page swipes skipped the row and reached the long SOUL
section. Short overlapping collection-view drags corrected the test. No message
was sent in that failed attempt. Initial lock/toolchain readiness and a test-target
signing-team requirement were resolved before execution; they are not app defects.

**Historical Research Terminal limitation at `a6b854e`:** the read-only helper returned exit
code 1, `RESEARCH_TERMINAL_API_TOKEN_FILE is required`. The assistant accurately
reported that no search results/source title were returned. The chat, native skill
access, tool invocation and streaming paths succeeded, but successful Research
Terminal retrieval is not claimed. No credential inspection, research job creation,
publication, external message or destructive research operation was performed.
That milestone did not change the missing authentication reference. The credential
wiring is resolved in the follow-up below.

Ignored local evidence: `build/bot-chat-validation/` contains sanitized live run
metadata and phone screenshots, including `attached-research-terminal-on-iphone.png`,
`mobile_research_check_done.png`, `research-orchestrator-history-after-relaunch.png`
and `same-bot-chat-opened-from-chat-tab.png`. Result bundles:

- `<private-local-evidence>`
  (Hermes/Worker passed; initial skill traversal failed).
- `<private-local-evidence>`
  (corrected Orchestrator, passed).

## Research Terminal credential follow-up — 2026-10-03

Continues `a6b854e`. The existing bearer token was already stored in
`~/.config/research-terminal/hermes-api-token`, owned by the service
user with mode `0600`. No new Research Terminal credential was created.
The helper reads a plain-text token from `RESEARCH_TERMINAL_API_TOKEN_FILE` and
uses it as an HTTP bearer token. It has no Keychain lookup and deliberately does
not source the production Research Terminal `.env`.

The native `research-orchestrator/.env` already supplied both the token-file path
and `RESEARCH_TERMINAL_API_BASE_URL=http://127.0.0.1:8000/api/v1`. The missing piece
was the profile's empty `terminal.env_passthrough` list. The dedicated backend
starts with the default Hermes home, then binds the selected bot's profile and
secret scope. Routed profile variables do not enter process-global `os.environ`;
Hermes forwards explicitly declared names from the bound profile into terminal
children. Adding a shell export or bridge-wide secret would therefore be the
wrong scope for this installation.

Only the following list was merged into the existing machine-local
`~/.hermes/profiles/research-orchestrator/config.yaml`:

```yaml
terminal:
  env_passthrough:
    - RESEARCH_TERMINAL_API_TOKEN_FILE
    - RESEARCH_TERMINAL_API_BASE_URL
```

Keep the other terminal settings when applying this fragment. The token contents
stay in the existing owner-only file; profile `.env` holds its non-secret path.
Research Terminal's API uses the same file through `RESEARCH_HERMES_API_TOKEN_FILE`.
The API service's existing `.env` and orchestration profile permissions were
preserved. No app, bridge runtime, launchd plist, production database, or Research
Terminal source change was needed. A private profile-config backup is under
a private location (path withheld).

Both dedicated user LaunchAgents were stopped and bootstrapped after an idle-run
check, then became healthy. Hermes caches the passthrough list per profile home,
so a backend restart is necessary after editing it. The on-disk profile config
and existing token path survive service restarts; both LaunchAgents have
`RunAtLoad` and `KeepAlive` and are enabled in `gui/<service-user-uid>`. Login/reboot startup is
configured; an actual logout or Mac reboot was not performed.

Validation used the existing completed run UUID
`<redacted-validation-id>`, titled
`<existing-completed-run-title>`:

- Direct helper `status <existing-run-UUID>` returned exit `0`, `ok:true`, and
  `status:completed`. The same endpoint without authorization returned `401`.
- After restarting both Studio services, the live bridge opened the existing
  Research Orchestrator canonical Bot Chat and invoked `skill_view`, then the
  helper's `status` command without inline exports. Run
  `<redacted-validation-id>` completed with two tools and 34 assistant
  deltas. Its terminal result returned exit `0`, `ok:true`, and the existing
  title/status to the same conversation. Evidence is ignored under
  `build/research-terminal-validation/`.
- The connected physical iPhone remained locked. The signed app/test build
  succeeded, but Xcode could not launch the device test; it was cancelled before
  any phone prompt was sent. Physical-device validation was not repeated. The
  same paired credential and canonical conversation were validated through the
  live bridge above. Test build log: `<private-local-evidence>`.

**Remaining Research Terminal limitation:** the live API is in PostgreSQL runtime
mode. Its authenticated `/api/v1/hermes/research/{reference}` endpoint works with
the helper's `status` command and canonical run UUID/archive ID. The skill still
advertises legacy `search`, whose `/hermes/knowledge/search` route is absent in
this mode and returns `404`. Legacy `R-...` identifiers should not be assumed to
resolve in the canonical archive. Migrating the search surface is separate from
credential wiring; no SQLite fallback or research job was introduced.

To diagnose a regression, inspect names and metadata without displaying `.env`
or token contents:

1. Check ownership, mode `0600`, readability, and nonempty content of the token
   file as the service user; never print its contents or put it in a command.
2. Check the two variable names in the native profile `.env` and the passthrough
   list in that same profile's `config.yaml`. The bridge's environment is not the
   selected bot's credential source. Preserve profile isolation.
3. Verify the configured loopback API and its OpenAPI routes. Missing-variable
   errors indicate forwarding; `401` indicates authentication; `404` can indicate
   an unsupported route or unknown record rather than a credential failure.
4. After confirming no active/unknown bridge runs, restart the dedicated backend
   and bridge using `scripts/stop-bridge.sh` and `scripts/start-bridge.sh`, then
   check `scripts/status-bridge.sh` and repeat a read-only helper status request
   through the bot. Do not restart unrelated Research Terminal workers/gateways.

The physical opt-in regression `testResearchTerminalAuthenticatedStatus` builds
successfully; its device execution remains unverified while the phone is locked.
It accepts
an existing completed run UUID through `TEST_RUNNER_HERMES_RESEARCH_REFERENCE`, alongside
`TEST_RUNNER_HERMES_WRITABLE_BOTS_UI=1`. It opens the paired canonical chat, sends
only a status request, checks the successful response, and reopens its history
after relaunch. Independently inspect live tool events for exit `0` and `ok:true`;
a model's completion marker alone is insufficient authentication evidence.

Secret cleanup checked the actual token bytes against 249 tracked source, evidence,
service-log, bridge-journal, and launchd files, with zero matches. No staged file
contains credentials. The token file is outside this repository; validation
artifacts are covered by the existing `build/` ignore rule. Relevant launchd
plists contain file references rather than the Research Terminal token itself.

## Automated validation

- **Bridge: 42 passed, 0 skipped/failed**, with `HERMES_BRIDGE_E2E=1`.
  Ten new canonical lifecycle/protocol regressions cover absence, reuse, concurrent
  taps, eager title failure/retry, native send/profile identity, same CID in main
  Chat, hidden/removed history retention, authorization/configuration gates,
  mismatched registry roots/profiles, busy native turns and modern clarification.
- **Installed-source end-to-end:** an isolated Hermes home and deterministic local
  model, with no production provider credentials. Concurrent initialization of all
  three identities, distinct native model/SOUL/skills, source history, same-CID list,
  tools, stop/steer, two-question clarification after transport reconnect, replay,
  bridge restart and cold Hermes restart all passed. Cold Orchestrator execution
  again proved its native model/SOUL/skill context. Process loss leaves the interrupted
  generic run unknown and never resends its prompt.
- **Studio lifecycle/configuration: 8 passed.**
- **Full Swift unit/UI: 46 passed, 10 explicitly skipped, 0 failed; 56 total.**
  Optional physical/isolated-stack/Studio tests are skipped unless explicitly enabled.
  Includes 26 BridgeIntegrationTests and existing simulation UI coverage. Result:
  `<private-local-evidence>`.
- Signed physical build/install succeeded. `git diff --check` passed.

Logs: `<private-local-evidence>`, `<private-local-evidence>`,
`<private-local-evidence>`, `<private-local-evidence>`.
No token/configuration/signing material is added to repository artifacts.

## Dynamic discovery and deliberately deferred work

Existing fresh roster/15-second visible refresh/foreground/reconnect behavior is
preserved. Automated tests exercise new membership, hidden/removed membership and
preserved historical rows without an app rebuild. The earlier read-only milestone's
Studio-owned temporary probe discovery/removal evidence remains historical; it was
not repeated with a production probe in this pass.

Bot creation/editing, profile deletion/archive, model/SOUL/skill configuration UI,
rooms and destructive approval responses remain deferred. Independent Desktop
clients can attach to the same source session; the bridge does not claim exclusive
per-client ownership or full observation of Desktop-created runs. Modern source
clarification locks still permit cross-client races before the batch settles.
Phone stop/steer and clarification actions were not physically exercised here;
they passed bridge, Swift and actual installed-Hermes isolated tests.

## Signing reconciliation

The pre-existing project/scheme changes were inspected and kept unchanged locally,
excluded from this milestone. Parsing the project as property-list objects confirms
its only semantic changes are personal `DEVELOPMENT_TEAM` assignments in the app's
Debug and Release settings; the remaining diff is serializer ordering. The shared
scheme's existing removal of UI-test `parallelizable="NO"` is also left uncommitted.
Test-target signing was supplied via a local `xcodebuild DEVELOPMENT_TEAM=…` override.
No personal team assignment, device ID, certificate, provisioning profile, Apple
credential or secret is committed. This preserves the user's existing local signing
work while keeping the shared project portable.


## Three-track sprint after 69261f1 (2026-10-03)

### Research Terminal PostgreSQL search

The existing authenticated helper calls `POST /api/v1/hermes/knowledge/search`.
PostgreSQL startup omitted the SQLite-backed Hermes router and never registered
that path. The PostgreSQL compatibility router now mounts the same path/auth/schema,
uses canonical archive sources/findings and maps finding evidence to source IDs.
Both backends share response serialization and token relevance rules. The helper
and iPhone need no backend-specific search branch.

The Research Terminal checkout was broadly dirty before this sprint. Its captured
index was preserved byte-for-byte across seven baseline paths. Eight scoped source,
test and documentation changes are applied there and loaded by the live API; their
complete baseline-relative patch and hashes are committed in
`patches/research-terminal-postgres-search/`. This is deliberately not a clean-HEAD
patch and must be reconciled with the existing migration work before an upstream
Research Terminal commit. No corpus migration or write was performed.

The own-UID API process was gracefully terminated with zero queued/running research
jobs; its existing system launchd service restarted it. Direct authenticated helper
search returned five existing records for `Hermes`, including source
`<redacted-validation-id>`, “Hermes: Memory-Efficient Pipeline Inference
for Large Models on Edge Devices”. The agent verified all five IDs against the
active corpus through the in-process read-only app. The same source/title/ID was
returned through the live HTTPS bridge canonical Research Orchestrator chat.

The physical phone sent the safe search, loaded `research-terminal`, invoked its
helper normally without exporting credentials, and received `SPRINT_PHONE_PG_SEARCH_OK`
with five records and that source. Bridge event evidence records `ok:true` and the
successful tool exit. The phone UI's prefix assertion passed; an additional test
assertion incorrectly expected Markdown title text in the same accessibility element
and failed. That assertion is corrected; the rerun was blocked by the phone lock and its
unstarted queued test was stopped. No research job, publication or external message was created.

### Native bot management

Bridge create/update/hide/duplicate uses Hermes `profiles.create`,
`profiles.configure`, `profiles.list` and `profiles.describe` at 4bb9e57. Native
metadata namespace replacement and its revision CAS are respected, so rename followed
by hide/unhide preserves title and Desktop presentation metadata. A live host with
111 enabled skills exposed the initial 100-entry guard; create/update now allow a
bounded 512 installed selections, and the phone omits unchanged inherited selections.

The phone form uses dynamic provider/model, installed-skill, toolset and MCP inventory.
Name, description and SOUL are edited through typed fields. Native expensive-model
confirmation is respected for edits. Create clones the native default profile's
configuration/auth-sharing semantics; no credential value crosses the bridge.
Hard delete is omitted; hide retains canonical history and is reversible on Desktop.

A live bridge probe was created, renamed, given edited description/SOUL and an empty
skill selection, duplicated and opened twice to the same writable canonical chat.
Hermes Desktop visibly showed its native edited identity and final upload reply.
The duplicate and original probe were hidden using Hermes semantics; histories remain.
After bridge plus backend restart, the original title/description, canonical ID,
history and native prompt path persisted. One first cold reopen returned a bounded
`upstream_uncertain` response; after inspecting the persisted chat, read-back and a
new safe prompt succeeded. No uncertain prompt was automatically replayed.

Physical creation reached the bridge and surfaced the 111-skill guard; the corrected
flow needs a final phone re-run. Another UI attempt overlapped service deployment and did not submit a create command;
the diagnostic test now verifies field values and enabled state before tapping Create.
That rerun could not start while the phone remained locked.
Do not count physical creation/edit as passed until that run completes.

### Attachments and dictation

Secure bridge staging, conversation/run linkage, image/PDF/text native RPCs,
Files import, PhotosPicker, camera preview/cancel and native dictation are implemented.
Privacy strings are added to app Debug/Release settings. The user's personal signing
assignments and scheme changes remain outside commits.

The live HTTPS bridge uploaded a real tiny PNG and Markdown note to the probe's
canonical chat. Hermes replied `SPRINT_LIVE_UPLOAD_OK`, reproduced the exact note
marker and confirmed the image. A separately staged text file survived both service
restarts and was consumed by a new run returning its exact marker. Bridge-managed
staging IDs and native history retain their separate ownership/retention semantics.

Physical camera/photo/file sends and real microphone partial transcription have not
yet been verified in this sprint. The phone has repeatedly locked between runs.
Opt-in physical tests are provided; speech requires a real spoken sentence and never
injects audio into Hermes. This limitation is hardware validation, not a claimed pass.

### Persistence and security

Machine-local `config.json` now grants `bot_mode_management:true`; the private
pre-change backup is beside it. launchd plists remain token-file references and
RunAtLoad/KeepAlive user services remain enabled. The updater preserves this grant,
credentials, journal and pending uploads, and refuses pending mobile mutations as
well as active/unknown runs. Both backend and bridge were restarted in this pass.
Research Terminal search also succeeded from the physical phone after that restart.

Known-credential content scans of tracked sources, delivery patch, scoped logs,
bridge journal and bridge launchd plists passed. Dashboard/mobile/Research Terminal
credentials were compared only in memory and never printed. Token/config files remain
0600; upload directory is 0700 and generated files 0600. The Research Terminal token
stays outside Git; `.gitignore` excludes local environment/signing/pairing files.


### Final automated totals

- Research Terminal: 28 distinct tests passed (13 PostgreSQL pipeline tests,
  15 Hermes client/retrieval tests). The PostgreSQL suite was repeated on the same
  disposable database and passed all 13 again; the four helper-search cases are
  a subset of the 15 and are not double-counted. Ruff passed.
- Bridge: 59 distinct passed, zero skipped/failed, with `HERMES_BRIDGE_E2E=1`. This includes
  the installed 4bb9e57 source in an isolated Hermes home with a deterministic
  local model, native bot lifecycle, canonical chats and restart exercise. The final full
  suite passed 58 before the additional bounded-PDF regression; all five upload
  cases then passed, adding one distinct regression without double-counting.
- Studio service: 9 passed, including pending bot/upload mutation restart guard.
- Full Swift/XCTest simulator run: 65 total, 49 passed, 16 explicitly opt-in
  tests skipped, zero failed. These include the create/edit/hide form and
  upload-to-run transport checks; skipped hardware cases are not claimed passes.
- Physical attempts are recorded separately above. The initial skill-limit
  failure was fixed, and the Markdown accessibility assertion was corrected.
  Physical creation/edit/hide and hardware media/voice remain the completion gate.

The bridge/backend deployment is healthy and all temporary bridge-created profiles
are hidden. Source histories are preserved. Nothing was pushed or published.


PDF follow-up: the Studio initially lacked `pdftoppm` in the launchd PATH. Homebrew
Poppler is now installed under `/opt/homebrew/bin`, already included by the service
launcher. A 596-byte one-page fixture rendered through native `pdf.attach`; the live
bot returned `SPRINT_LIVE_PDF_OK SPRINT_PDF_PROBE_8241`. The test profile was hidden
again afterward. No shell export or additional credential/configuration was required.


## Physical acceptance follow-up — 2026-10-03, 21:31–21:41 CDT

The connected iPhone was initially unlocked. Xcode rebuilt/signed the current
sprint app and installed it over `com.dippo.hermes`, preserving the existing
Keychain pairing and app data. No services were restarted during this pass.

Physical creation succeeded: `Mobile Sprint Probe 20261003C` became native profile
`mobile-sprint-probe-20261003c`. A read-only bridge re-read confirmed the exact
phone-entered description and SOUL, with inherited provider `openai-codex` and
model `gpt-5.6-luna`. Hermes Desktop visibly displayed that same native bot without
a Desktop restart. The device recording showed Wi-Fi active; the phone reached
the existing private HTTPS Tailscale bridge. Cellular was not tested.

The first UI test then failed when it attempted to tap the underlying new bot row
while the Create sheet was still completing its refresh. This is a test race:
existence of a row behind a sheet does not establish that the sheet has dismissed.
The harness now explicitly waits for Create/Save sheets to disappear, also edits
SOUL, and checks background/foreground before canonical chat and relaunch. Fresh
Research search markers prevent an older reply from satisfying the new search
assertion. Files/background and hide-confirmation checks were added to the opt-in
harness. These acceptance checks compiled successfully; they are not claimed as
physical passes.

At 21:34 the iPhone locked again before the corrected test could launch. Repeated
CoreDevice checks through 21:41 reported `passcodeRequired:true`. The queued,
unstarted test was explicitly stopped. No product defect or product-code change
was established. Research repeat, bot edit/hide/chat/relaunch, Files, Photo Library,
Camera, dictation and run background replay remain untested in this follow-up.
The earlier physical Research search evidence above remains valid; it is not a
new pass here. The prior 145 distinct automated passes were not rerun or increased.

Cleanup used the supported Studio bridge hide operation for only the phone-created
temporary bot. Its native profile was retained, with no hard delete or history
removal. This is cleanup, not a claim that the phone Hide control passed. A harmless
74-byte iCloud Drive Files fixture was prepared and then removed before any upload.
No new phone upload or research job occurred. Personal signing/project/scheme edits
remain machine-local and excluded from commits. Full physical acceptance remains
blocked on keeping the phone unlocked throughout the checks.

Evidence: `<private-local-evidence>`,
`<private-local-evidence>`,
`<private-local-evidence>`, `<private-local-evidence>`, and
`<private-local-evidence>`. Evidence is machine-local, not committed.

## Completed physical acceptance — 2026-10-04, 15:49–16:18 CDT

The iPhone 15 Pro Max remained unlocked. The latest signed build was installed over
the existing app, preserving app data and Keychain pairing. Tailscale on the phone
was initially disconnected; reconnecting it in its native app restored access to
the existing private HTTPS hostname. Wi-Fi was active throughout acceptance.
Cellular was not repeated, and Funnel was not enabled. Neither Studio service was
restarted in this pass; the preceding sprint's restart evidence still applies.

Seven distinct physical acceptance tests passed:

| Check | Actual result |
| --- | --- |
| Research Terminal | Phone → canonical Research Orchestrator → native `skill_view` → helper `search "Hermes" --limit 5` returned `ok:true` and five real records. Fresh marker `SPRINT_PHONE_PG_1791148589`, run `<redacted-validation-id>`; first source was **Hermes: Memory-Efficient Pipeline Inference for Large Models on Edge Devices**, record `<redacted-validation-id>`. The result and tool cards rendered after app relaunch, then survived background/foreground. No research jobs were launched. |
| Bot lifecycle | Created native `mobile-acceptance-20261004a` from the phone with name, description and SOUL; inherited safe `gpt-5.6-luna` / `openai-codex`. Immediate roster appearance, refreshed detail, background/foreground, relaunch and writable canonical chat passed. Phone edits to description and SOUL were independently read back and visibly verified in Hermes Desktop's edit dialog. Optional model/skill changes were not repeated physically. |
| Files + active-run recovery | Native Files picker selected a harmless 74-byte text fixture, composer preview appeared, and Hermes reproduced `PHONE_FILE_MARKER_9017` from the file. Home/foreground during the run recovered one assistant response and one consumed attachment, without duplicate send or history. |
| Photo Library | Selected an inspected harmless logo using the native selected-items-only picker, previewed and sent it. Hermes confirmed the image; one 196,659-byte JPEG was consumed in the correct canonical chat. No broad Photos permission was required. |
| Camera | Granted camera permission, captured a new harmless pale-surface photo, used the native preview/Use Photo flow, saw its composer preview and sent it. Hermes described the image; one 990,984-byte JPEG was consumed in the correct chat. |
| Dictation | Granted Speech Recognition and microphone permissions. Native on-device recognition displayed the spoken sentence in the composer while recording. Cancel and Stop passed; the text was edited before ordinary text send and Hermes replied `SPRINT_PHONE_VOICE_OK`. See the media document for the exact received text and acoustic test method. Upload count stayed at three; the voice run had no attachment IDs or tool calls. |
| Hide/cleanup | Phone confirmation explained preserved history. Hide removed the test bot from the phone and Desktop visible lists; Desktop's Hidden list retained it. The native canonical session `<redacted-session-id>` and all ten messages were unchanged, verified by a before/after content hash. No hard delete occurred. |

### Device defect and focused regression

The first dictation authorization attempt crashed with `EXC_BREAKPOINT` in
`swift_task_checkIsolatedSwift`, called from the authorization closure in
`ComposerDictation.start(words:)` on a background framework queue. The closure had
inherited MainActor isolation. Authorization now crosses an explicitly nonisolated,
Sendable callback boundary; recognition callbacks hop to MainActor for UI changes,
and the audio tap uses a narrowly scoped Sendable sink for Speech buffer append.
No recognition audio is sent to Hermes. The updated build passed real dictation.

The new background-queue authorization regression passed. The impacted full
`HermesTests` target then passed **43 distinct tests**, with three explicit live-stack
opt-ins skipped and zero failures. The focused regression is included in those 43,
not counted twice. It adds one distinct test to the prior sprint's 145: **146 distinct
automated suite passes cumulatively**, plus the seven physical acceptance cases.
Unrelated bridge and Research Terminal suites were not rerun.

Initial acceptance retries also corrected test-only issues: offscreen virtualized
form assertions, a reused hidden-bot name correctly rejected by native Hermes,
and whole-app swipes hitting the keyboard rather than the transcript. The fresh
search result is checked after reopening and with drags confined to the transcript.
These did not require feature changes or a UI redesign.

### Evidence and cleanup

Passing physical bundles under `<private-local-evidence>`:

- `<private-result-bundle>` — create/edit/canonical chat.
- `<private-result-bundle>` — camera.
- `<private-result-bundle>` — Files and run recovery.
- `<private-result-bundle>` — Photo Library.
- `<private-result-bundle>` — dictation.
- `<private-result-bundle>` — fresh PostgreSQL search/relaunch.
- `<private-result-bundle>` — Hide.

The Files fixture was removed from iCloud Drive. The three consumed uploads remain
under the existing seven-day staging cleanup policy; native chat attachments and
history have Hermes retention semantics. Photos, recordings, result bundles,
credentials and personal signing/project/scheme changes remain outside commits.
Scoped in-memory comparisons against the three existing credential values found
no matches in changed deliverables, acceptance logs, launchd plists or the bridge
event/run/upload journal. Credential files remain owner-only (0600).
All three sprint tracks now meet physical acceptance. No general Opus polish pass
is required for functional completion.

### Talaria post-design physical regression (2026-10-04)

The latest Talaria build retained `com.dippo.hermes` and existing Keychain pairing.
Physical checks confirmed ordinary canonical chat, normal/accessible Markdown
tables, Research Orchestrator Show All/Show Fewer including `research-terminal`,
Files marker retrieval with background event replay, real native dictation, and
Springboard icon/display name. PostgreSQL search, camera and Photo Library were
not repeated in this focused pass; their actual earlier results above remain the
evidence. Wi-Fi/Tailscale HTTPS worked; cellular was not repeated.

Device testing exposed startup namespace/cache races and slow native bot detail
and clone operations. Known Bot Mode identities now survive transient offline
snapshots, stale roster completions are ignored, avatar warmup is sequential,
and the editor reads confirmed native fields before populating the form. Only
clone RPC/Create/Duplicate and read-only bot detail receive longer bounded
response budgets; credentials, mutation idempotency and upstream native bot
semantics remain unchanged. See TALARIA_REGRESSION_VALIDATION.md for exact
physical results, cleanup, test totals and remaining release gates.

The final Talaria edit/canonical-chat/relaunch case passed on the phone, followed
by Management Hide. Native SOUL/description edits persisted, and all ten canonical
messages had an identical content digest before/after hiding. All three temporary
bots are hidden. The Files fixture is removed and its consumed upload follows the
existing seven-day cleanup policy. All requested post-design physical components
now pass; Talaria is ready for v0.1.0 release cleanup without a general polish pass.
