# Talaria — UI Architecture

Native SwiftUI control surface for Hermes Agent running on a Mac Studio.
Hermes never runs on the phone.

```
iPhone app ──Tailscale──▶ hermes-mobile-bridge ──▶ Hermes (Mac Studio)
```

Production startup uses `BridgeHermesClient`; explicit Simulation and UI tests
use `MockHermesBackend`. Every view and store depends on the service protocols in
`Hermes/Services/Protocols`. Both clients use the same views and stores. See `INTEGRATION_POINTS.md` for the exact seams.

- iOS 18.0+, iPhone, portrait-first (landscape allowed)
- Swift 6 language mode, default `MainActor` isolation, approachable concurrency
  (the UI-test target uses Swift 5 mode for XCUITest ergonomics)
- No third-party dependencies (SwiftUI, Swift Charts, PhotosUI, UserNotifications)

---

## 1. Project layout

```
Hermes.xcodeproj              Hand-written project; folders are synchronized groups
Hermes/
  App/                        Entry point, composition root, navigation, route table
  Domain/                     Value types (Sendable, Codable): Run, Profile, Approval, …
  Services/
    Protocols/                HermesClient + every service protocol, events, errors, notifications
    Local/                    Local-only state: preferences, saved hosts, snapshot cache, drafts
    Mock/                     MockHermesBackend, fixtures, scripted run engine, simulation controls
  Stores/                     @Observable state holders consumed by views
  DesignSystem/               Theme, formatters, status views, content states, shared components
  Features/
    Home/ Chat/ Runs/ Tasks/ Bots/ More/
  Resources/Assets.xcassets   Accent color, app icon, mock chart images
HermesTests/                  Swift Testing unit tests (parser, formatting, domain, mock backend)
HermesUITests/                Screen tour + degraded-state tests (also produce screenshots)
```

New files dropped into these folders are picked up automatically, because the
project uses `PBXFileSystemSynchronizedRootGroup`.

---

## 2. Navigation

Five tabs, each with its own `NavigationStack` (`App/RootView.swift`):

| Tab | Root view | Purpose |
|---|---|---|
| Home | `HomeView` | Status: needs attention, active, recent, upcoming, Studio |
| Chat | `ConversationListView` | Conversations → `ConversationView` |
| Tasks | `TasksView` | Segments: Running · Scheduled · Kanban · Completed |
| Bots | `BotsView` | Hermes profiles presented as bots → `ProfileDetailView` |
| More | `MoreView` | Hosts, usage, memory, skills, tools, MCP, integrations, logs, settings |

**One destination table.** Every pushable screen is a case of `Route`
(`App/Navigation.swift`). Every stack registers the same table with
`.routeDestinations()` (`App/RouteDestinations.swift`). So Run Detail, a
conversation, a task or a profile can be pushed from any tab, which keeps the
reusable screens reusable.

**`AppRouter`** owns the selected tab and each tab's path. It handles cross-tab
moves such as `startNewChat(profileID:)`, `showTasks(_:)` and
`openConversation(_:)`, so notification deep links can use it later.

**Sheets** are used for short, focused input:

| Sheet | Opened from |
|---|---|
| `SteerSheet` | Send instruction |
| `RunSettingsSheet` | Composer settings line |
| `RunSummarySheet` | Response details |
| `NewTaskSheet` | Tasks, profile |
| `RoutineEditView` | Routine detail |
| `EditProfileView` | Profile detail |
| `HostEditorView` | Hosts |

Destructive actions use `confirmationDialog`.

**Run Detail** (`Features/Runs/RunDetailView.swift`) is reachable from:

- Home active and recent rows, and attention rows
- Chat live-run "Details" and the conversation menu
- Tasks running and completed rows, task detail and routine detail
- Profile detail
- Logs

---

## 3. State and data flow

```
                  ┌────────────────────── HermesClient (protocols) ─────────────────────┐
 views ──read──▶ stores ──requests──▶ services                     events.subscribe(after:)
   ▲                ▲                                                         │
   └── @Observable ─┴──────────── AppEnvironment.handle(envelope) ◀───────────┘
```

- **`AppEnvironment`** (`App/AppEnvironment.swift`) is the composition root. It
  owns the client, the stores, the router, toasts and the single app-wide event
  subscription. Each event goes to every store's `apply(_:)`. When the link
  comes back, it refreshes everything; if the transport dropped, it first
  resubscribes from the last cursor so missed events replay. It also turns
  state transitions into notifications via `NotificationPolicy`.
- **Stores** (`Stores/`) are `@Observable`, `MainActor`, and injected
  individually with `.environment(store)`:

| Store | Holds |
|---|---|
| `ConnectionStore` | Saved hosts, active host, per-host `HostStatus` and capabilities, run options. Keeps last-known capabilities when a degraded status arrives without them. |
| `HomeStore` | The bridge's aggregated `HomeSummary`. Live run events patch active and recent in place; structural changes trigger a debounced refetch. Home never assembles state from other services. Also produces the attention list (bridge items plus local connection issues) used by Home and the tab badge. |
| `ActivityStore` | Runs and approvals across the host: the single source of run state for Home rows, chat live blocks, Tasks and Run Detail. Merges by `Run.lastSequence` and ignores stale snapshots, so replayed and live events can overlap safely. |
| `ConversationListStore` | Conversation list and loaded transcripts, kept current by events. Caches recent transcripts. |
| `ConversationModel` | Per-screen state for one conversation (new or existing): draft, attachments, run configuration and composer mode. |
| `ProfileStore`, `TaskStore`, `RoutineStore` | Profiles, Kanban tasks and routines. |
| `Resource<Value>` | Generic loader for the lower-frequency More screens. |

- **Phases versus data.** Each store keeps a `LoadPhase` separate from its data,
  so a failed refresh never blanks last-known content. `LoadableContent`
  chooses among loading, offline-without-cache, error, empty and content. Cached
  content always wins.

### Local-only state (the phone is not the source of truth)

| What | Where |
|---|---|
| UI preferences, notification categories, dismissed failures | `AppPreferences` (UserDefaults) |
| Saved hosts and active host | `SavedHostStore` |
| Last-known snapshots: host status, home, runs, approvals, conversations, recent transcripts, profiles, tasks, routines, event cursor | `SnapshotCache` (Caches directory, JSON) |
| Composer drafts | `DraftStore` |

On launch, stores hydrate from snapshots immediately, and the connection banner
labels them as last-known until the bridge answers.

---

## 4. Domain models (`Hermes/Domain`)

All models are `nonisolated` value types (`Sendable`, `Codable`, `Hashable`).

| Concept | Type | Notes |
|---|---|---|
| Host | `Host`, `HostStatus`, `ConnectionState`, `HostResources`, `RunOptions` | `ConnectionState`: connected · connecting · reconnecting · bridgeOffline · hermesOffline · authenticationRequired |
| Capability | `HermesCapability` | sessions, runs, runReplay, steering, stop, approvals, profiles, cron, kanban, usage, skills, tools, mcp, artifacts, memory, attachments, integrations, logs |
| Conversation | `Conversation`, `Message`, `MessagePart` | Every conversation belongs to a profile (`Profile.defaultID` for default). Parts: markdown, tools, image, file, error, event |
| Run | `Run`, `RunState`, `RunEvent`, `ToolCall`, `RunOutcome` | Stable IDs; events carry an ordered `sequence`. `steps` gives the ✓ ● ○ checklist. `displayState(isLive:)` shows active runs as *disconnected* over a degraded link |
| Approval | `ApprovalRequest`, `ApprovalAvailability`, `ApprovalDecision` | Availability: actionable · unavailableRemotely · ambiguous · expired |
| Task | `HermesTask`, `TaskStatus`, `TaskActivity`, `TaskDraft` | Kanban columns: Ready · In Progress · Blocked · Completed (failed and cancelled fold into Completed) |
| Profile ("Bot") | `Profile`, `ProfileStatus`, `ProfileTint` | A Hermes profile. "Bot" is UI vocabulary only |
| Routine | `Routine`, `RoutineSchedule`, `RoutineResult`, `RoutineDraft` | Cron jobs |
| Home | `HomeSummary`, `AttentionItem` | The bridge's aggregate |
| Knowledge | `MemoryEntry`, `Skill`, `ToolInfo`, `MCPServer`, `Integration` | |
| Diagnostics | `UsageReport`, `LogEntry` | Usage is tokens and runs only; no pricing |

---

## 5. Service protocols (`Services/Protocols`)

`HermesClient` bundles one implementation of each protocol:

| Protocol | Responsibility |
|---|---|
| `HostService` | Connect and disconnect, host status, run options |
| `HomeService` | Aggregated Home summary |
| `HermesEventStream` | `subscribe(after: EventCursor?)`: one ordered, replayable feed of `HermesEvent`s |
| `ConversationService` | List, transcript, create, rename, delete, pin, send |
| `RunService` | List runs, pending approvals, stop, steer, retry, resolve approval |
| `ProfileService` | List profiles, update model and skills |
| `TaskService` | List, create, move, start Kanban tasks |
| `ScheduleService` | List, pause/resume, run now, edit, delete routines |
| `MemoryService`, `SkillService`, `ToolService`, `IntegrationService`, `UsageService`, `LogService` | More screens |
| `NotificationService` | Deliver `HermesNotification`s (local implementation today) |

All protocols are `AnyObject, Sendable`. Errors are normalized to `HermesError`:

- `bridgeUnreachable`, `hermesOffline`, `unauthorized`, `timeout`: connectivity
- `unsupported(capability)`
- `notFound`
- `rejected(reason)`

---

## 6. Capability-aware UI

Capabilities come from `HostStatus.capabilities`, read via `ConnectionStore.supports(_:)`.
Nothing assumes a host supports everything.

| Mechanism | Used for |
|---|---|
| `CapabilityGate` | Wraps whole screens. Shows `CapabilityUnavailableView`, or progress if the host has never been seen |
| Hidden | Tasks segments (`cron`, `kanban`); composer attachments (`attachments`); profile picker and Bots list (`profiles`); Home "Upcoming" (`cron`); Start Task (`kanban`) |
| Disabled with "Unavailable" | More rows for usage, memory, skills, tools, mcp, integrations, logs |
| Controls | Stop requires `stop`; Send Instruction and composer steering require `steering`; Retry requires `runs` |
| Approvals | Without `approvals`, every approval renders as "unavailable remotely": no Approve or Deny buttons |

Settings › Simulation › Disabled capabilities toggles any of these live, so the
degraded UI can be checked without changing the host.

---

## 7. Connection and degraded states

| State | What the user sees |
|---|---|
| Connected | Live data; status dot in the Home header |
| Connecting / Reconnecting | Spinner in the header and banner; data shown as last-known |
| Bridge offline | Explanation, "Showing last-known state · updated 4m ago", Reconnect, a Needs Attention row; active runs shown as *Last known* |
| Hermes offline (bridge up) | Same treatment, distinct copy |
| Sign-in required | "Pair Again" plus a red attention row |
| Capability unavailable | `CapabilityUnavailableView` or hidden/disabled controls |
| Stale cache, no connection | Cached lists with banner; a full `OfflineContentView` only when nothing is cached |

The banner sits under inline navigation bars (`.connectionBanner()`) and inside
large-title lists (`ConnectionNoticeSection`). Composers and controls disable
while disconnected.

Backgrounding the app doesn't stop runs. On return from background, the app
reconnects if the link dropped, and the event stream replays from the last
cursor.

---

## 8. Chat and active runs

- **`ConversationView`** is the only chat implementation. Bot chats use it with
  a profile ID.
- **`MessageView`** renders the parts of a message:
  - user bubble, or full-width assistant text
  - `MarkdownView`: block parser with code blocks (copy, light highlighting) and tables
  - `ToolActivityView`: tool calls collapsed by default; more than three fold behind "Used N tools"
  - images (`ImageAttachmentView`), files, errors (with Retry), system events
- **`LiveRunBlock`** appears on the assistant message of an active run. It
  contains:
  - the ✓ ● ○ step list
  - elapsed time and current action
  - inline `ApprovalCard`
  - Send Instruction, Stop and Details

  It never shows a bare spinner.
- **`ComposerView`** changes with the run:
  - Normal: send a message.
  - Steerable run: the composer switches to steering ("Instructions go to the running task").
  - Busy run (approval pending, stopping): input disabled, Stop available.
  - Disconnected: input disabled, with an explanation.
- **`RunSettingsBar`**: profile, model, reasoning and project collapse into one
  line above the input and open `RunSettingsSheet`.
- **Telemetry** (elapsed, model, tokens, tools) lives behind the footer's ⓘ in
  `RunSummarySheet`, not in every reply.

### Approvals

`ApprovalCard` reads `effectiveAvailability(remoteApprovalsSupported:)`:

| Availability | Card shows |
|---|---|
| actionable | Deny, plus Approve as a menu button (long-press: *Approve for this session*) |
| unavailableRemotely / ambiguous | "Approval required on the Studio", the reason, View Details, and Stop Run if supported. **No Approve button.** |
| expired | Explanation only |

`ApprovalDetailView` adds the reason, a unified diff (`DiffView`), affected
paths, expiry and the run link.

---

## 9. Reusable components (`DesignSystem/`, `Features/Runs/`)

| Component | Use |
|---|---|
| `StatusDot` | State dot; pulsing for live work; respects Reduce Motion |
| `RunStateLabel`, `CurrentActionLabel` | Run state; tinted capsule only for attention states |
| `ElapsedText`, `RelativeTimeText` | Self-updating times |
| `ProfileAvatar`, `ProfileAvatarWithStatus` | Muted monogram identity tiles |
| `ConnectionLabel`, `ConnectionBanner`, `ConnectionNoticeSection` | Link state |
| `LoadableContent`, `OfflineContentView`, `ErrorContentView`, `LoadingRows` | Content states |
| `CapabilityGate`, `CapabilityUnavailableView` | Capability gating |
| `KeyValueRow`, `CommandBlock`, `SectionHeader`, `ProjectChip`, `StatusPill` | Building blocks |
| `RunRow`, `RecentRunRow`, `LiveSteps`, `StepLine`, `RunTimeline` | Run presentation |
| `ApprovalCard`, `DiffView` | Approvals |
| `ToastCenter` + `.toastOverlay()` | Non-blocking feedback; `perform(success:_:)` wraps async actions |
| `.haptic(_:trigger:)` | Haptics gated by the user preference |
| `Theme` | State colors. The only saturated hues; everything else is system materials. Dark mode uses its own validated accent (`#5F92EE`) |

---

## 10. Mock architecture (`Services/Mock`)

- **`MockHermesBackend`** simulates the bridge and the host behind it, and
  conforms to every protocol. Every request goes through `perform(_:)`, which
  applies:
  - latency
  - reachability, based on the simulated connection state
  - capability checks (throws `unsupported`)
  - failure injection
- **`MockEventLog`** gives every event a cursor, keeps a ring buffer, replays
  from a cursor, and emits `resyncRequired` when the cursor is too old.
- **`MockFixtures`** holds a consistent world relative to `now`:
  - 2 hosts and 5 profiles (default, Caddy, Researcher, Dex, Analyst)
  - 10 conversations; 18 runs (4 active); 2 approvals (one actionable, one Studio-only)
  - 13 tasks; 4 routines; plus memory, skills, tools, MCP, integrations and logs
- **`MockRunEngine` + `MockScripts`** drive runs step by step: planned steps,
  tools, approvals (approve, deny or expire branches), streamed markdown,
  attachments, completion and failure. Steering and stop are simulated
  realistically. New chats pick a script from the prompt: anything mentioning
  "delete", "clean" or "remove" triggers an approval.
- **`SimulationControls`** (Settings › Simulation, mock only) sets:
  - connection state, latency, run speed
  - failing requests, empty account
  - disabled capabilities
- **Launch arguments** (UI tests and QA):
  - `-uiTesting`: use the UI-test storage sandbox
  - `-resetState`: clear that sandbox first
  - `-simulate bridgeOffline|hermesOffline|authRequired|reconnecting`
  - `-emptyData YES`
  - `-runSpeed <n>`: speed up scripted runs

---

## 11. Testing

```sh
# Unit tests + UI tests (iPhone 17 Pro simulator)
xcodebuild -project Hermes.xcodeproj -scheme Hermes \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Save tour screenshots to a folder
TEST_RUNNER_SCREENSHOT_DIR=/tmp/hermes-shots xcodebuild … -only-testing:HermesUITests test
```

- `HermesTests`: Markdown parser, formatters, run steps and sequencing,
  approval availability, Home aggregation, capability and offline errors,
  Studio-only approvals, approve → run completes, cursor replay.
- `ScreenTourTests`: walks every major screen.
- `InteractionTests`: approve → run completes; new chat → approval → deny;
  steer a running run → stop it.
- `DegradedStateTests`: offline with cache, Hermes offline, sign-in, empty account, offline without cache.

---

## 12. Deliberately deferred

| Item | Status |
|---|---|
| Multi-bot groups and @mentions | Not first-class in Hermes. A disabled "Groups — Later" row marks the place in Bots. |
| Bot Mode backend objects | Bots are profiles. Richer Bot Mode can extend `Profile` and `ProfileService`. |
| Remote push (APNs) | Not available yet. `NotificationPolicy` and `LocalNotificationService` are in place; settings explain the limitation. |
| Camera capture, voice input | Placeholders in the composer. Photos and Files pickers work locally; upload is an integration point. |
| Full profile, SOUL and tool configuration | Read-only in `EditProfileView`; model and skills are editable. |
