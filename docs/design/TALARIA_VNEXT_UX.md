# Talaria vNext: interface design spec

Status: design pass for the next major implementation. No code in this document.
Author: lead UI/UX pass, 2026-10-05, based on the working tree at `c198f24` (branch
`codex/public-release-preparation`).
Audience: Codex (implementation brief), and the product owner.

Labels used throughout:

- **[client]** Deterministic behavior in the iOS app.
- **[bridge]** Behavior that needs `hermes-mobile-bridge` (exists, or marked *new*).
- **[hermes]** Behavior that needs upstream Hermes.
- **[LLM]** Behavior whose result depends on a model. Never let the UI depend on it for correctness.

---

## 1. Existing Talaria audit

### 1.1 What exists today (verified in code, not from docs)

| Area | Current state | Files |
|---|---|---|
| Navigation | Five tabs: Home · Chat · Tasks · Bots · More, each with its own `NavigationStack`. One shared `Route` table (`.routeDestinations()`), `AppRouter` owns tab and paths. Home tab badge = attention count. | `App/RootView.swift`, `App/Navigation.swift`, `App/RouteDestinations.swift` |
| Home | `List(.insetGrouped)`: status header (host menu, connection label, one status line "2 running · 1 needs you · next routine in 47m"), Needs Attention, Active, Recent (5), Upcoming, Host metrics grid. Renders the bridge `/home` aggregate. | `Features/Home/*` |
| Chat | Conversation list grouped Pinned/Today/Yesterday/7 Days/Older, search, swipe rename/delete/pin. `ConversationView` is the only chat; hides the tab bar; composer owns the bottom edge. | `Features/Chat/*` |
| Composer | Attach menu (Files/Photos/Camera), text field, in-field mic (native dictation into editable text), Send/Stop slot. Modes: `send`, `steer` (instructions go to the running run), `clarify` (answer + choice chips), `busy`. `RunSettingsBar` one-liner opens `RunSettingsSheet`. | `ComposerView.swift`, `ComposerMedia.swift`, `RunSettingsView.swift` |
| Live run | `LiveRunBlock` inside the assistant message: ✓ ● ○ steps, elapsed, inline `ApprovalCard`, Send Instruction / Stop / Details. Never a bare spinner. | `LiveRunBlock.swift`, `Runs/LiveSteps.swift` |
| Run Detail | Pushed screen: state, failure callout with Retry, approval, live steps, controls, result, full timeline (event log), metadata, tokens. Reachable from everywhere. | `Runs/RunDetailView.swift`, `RunTimeline.swift` |
| Approvals | `ApprovalCard` with availability model (actionable / unavailableRemotely / ambiguous / expired). **Bridge rejects every dangerous-approval decision** (`resolveApproval` always throws). Clarifications are answerable through the composer. | `Runs/ApprovalCard.swift`, `Domain/Approval.swift` |
| Bots | Roster with Desktop blob avatars, status dot, activity line, model line; 15 s refresh. Detail: identity → Chat → activity → configuration → skills/tools → management. Create/Edit (`BotEditorView`: name, description, SOUL, provider+model, skills, toolsets, MCP), Duplicate, Hide. | `Features/Bots/*` |
| Tasks | Segments Running · Scheduled · Kanban · Completed. Routine edit/pause/run-now, Kanban board + task detail with transitions. | `Features/Tasks/*` |
| More | Hosts, Usage, Skills, Tools, MCP, Memory, Integrations, Logs, Settings, Capabilities, Simulation. Memory/Integrations/Logs are unsupported by the bridge and capability-hidden. | `Features/More/*` |
| Design system | `Theme` (Talaria blue accent; attention orange; failure; success; steering indigo), `Tag`, `StatusDot` (one ring every ~4.7 s), `SectionHeader` (Desktop-style tracked caps), `.panel()`, `FailureCallout` + `StatusCopy` (raw codes → plain sentences), `ProfileAvatar` + `IdentityColor` (Desktop hash hue), `KeyValueRow`, `CommandBlock`, `TagCloud`, `LoadableContent`, `ConnectionBanner`, `ToastCenter`, `.haptic()` gated by preference. | `DesignSystem/*` |
| Stores | `@Observable` `MainActor`: `ConnectionStore`, `HomeStore` (bridge aggregate, patched by events), `ActivityStore` (single source of run/approval truth, merges by sequence), `ConversationListStore`, `ConversationModel`, `ProfileStore`, `TaskStore`, `RoutineStore`. `AppEnvironment` owns one replayable SSE subscription and an atomic `AppliedBridgeState` checkpoint. | `Stores/*`, `App/AppEnvironment.swift` |
| Offline | Snapshot cache hydrates instantly; banner says "Last-known state · updated 4m ago"; controls disable; idempotency receipts, `command_uncertain` never auto-retried. | `Services/Local/*`, `ContentStates.swift` |
| Voice | Native on-device `SFSpeechRecognizer` dictation into the composer (tap to start/stop, Cancel restores). No audio leaves the phone. No TTS. | `ComposerView.swift` |
| Notifications | Local notifications only while the app is alive; no APNs. | `NotificationService.swift` |
| Tests | Unit (Swift Testing), UI tours that tap tab names `"Chat"`, `"Bots"`, `"Tasks"` and labels such as `"Send"`, `"Voice input"`, `"Stop dictation"`, `"Add attachment"`, `"Send Instruction"`. | `HermesTests/`, `HermesUITests/` |

Deployment target is iOS 18.0; the code already branches on `#available(iOS 26.0, *)` (`pinnedTopBar` → `safeAreaBar`).

### 1.2 Backend facts that constrain the design

These come from `BRIDGE_API.md`, `BOT_MODE_AUDIT.md`, `BridgeHermesClient.swift` and `hermes_mobile_bridge/api.py`. Several contradict assumptions in the agreed architecture; see §1.4.

1. **Dangerous approvals cannot be answered from the phone.** Every choice, including deny, returns `409 exact_target_unavailable`. Upstream has no exact-target approval primitive. The only remote action is Stop for the whole run.
2. **Clarifications are answerable but short-lived.** They need a pending observation, the same upstream connection generation and an age under **290 s**. Replay never refreshes them. Secret, sudo and terminal-buffer prompts are Mac-only.
3. **No defaults or recommendations exist on attention items.** Fields are `id/run_id/conversation_id/profile/kind/state/observed_at/expires_at/can_respond/limitation/details{command|description|question|choices}`.
4. **Bot = native Hermes profile, with exactly one canonical "Bot Chat".** `POST /conversations?profile=` targets *bridge backends* (normally only `default`), not bots. A Bot Mode agent such as Research Orchestrator cannot have a second thread today.
5. **Model, provider and reasoning are fixed when a conversation is created.** The bridge deliberately does not change them later, because upstream `config.set reasoning` writes global defaults. Bot chats use `follow_profile_config`, so a **profile default** change does reach the next run of that bot's chat.
6. **Bot edits** (`PATCH /bots/{id}`): name, description, SOUL, model+provider (pair from inventory), skills, toolsets, MCP. Hermes may answer `409 bot_model_confirmation_required`, which the client confirms with `confirm_expensive_model`. **No reasoning, voice or pause field exists.**
7. **Runs**: `starting/running/waiting_for_input/stop_requested/complete/failed/cancelled/unknown`. Stop is cooperative and not proof of termination. Steering is `queued`, never "consumed". `unknown` blocks retry and blocks further submission in that conversation. The current Swift mapping folds `unknown` into `.disconnected`, which is wrong for the new design (§18).
8. **Handoffs and fan-out are mostly invisible.** Subagents appear only as tool calls (`ToolKind.delegate`). Kanban tasks have assignees, attempts, reassign and reclaim. Cross-profile delegation inside Hermes is not observed.
9. **Home `/home`** already returns active runs, pending attention, failed/unknown runs, blocked Kanban cards, failed cron jobs, recent completions (runs plus Kanban done), upcoming jobs, **all Kanban cards** (so review-state cards can be derived), coverage errors and `observed_at`.
10. **No capture/inbox endpoint, no routing endpoint, no APNs, no TTS.** Archive exists (`PATCH /conversations/{id} {archived}`), but the UI never uses it.
11. **Live roster** on the Studio today: Hermes (default), Research Orchestrator, Research Worker. Codex and Muse are future profiles; the design must not hard-code names.

### 1.3 Reuse / modify / remove (summary; detail in §19–21)

- **Reuse as-is:** stores and event loop, snapshot checkpointing, idempotent command layer, `StatusCopy`/`FailureCallout`, `ProfileAvatar`/`IdentityColor`, `StatusDot`, `Tag`, `SectionHeader`, `KeyValueRow`, `CommandBlock`, `MarkdownView`, `ToolActivityView`, `TranscriptItem`, `ComposerMedia`, `ComposerDictation`, `LiveSteps`/`StepLine`, `RunTimeline`, `ToastCenter`, `.haptic`, `BotEditorView`, Kanban/Routine detail screens, Host editor, Settings.
- **Modify:** `RootView` (3 tabs + Ask accessory), `HomeView` → `NowView`, `ConversationListView` → `ThreadsView`, `ConversationView` (thread header, RunCard, pinned Needs You, result footer), `ComposerView` (thread Ask, push-to-talk), `LiveRunBlock` → `RunCard`, `RunDetailView` → `StepsSheet`, `ApprovalCard` → `NeedsYouCard` family, `BotsView`/`ProfileDetailView` → `AgentsView`/`AgentDetailView`, `RunSettingsSheet` → `AskOptions`, `AttentionItem` → `NeedsYouItem`, `RunState` mapping.
- **Remove from navigation:** Tasks tab, More tab, Home host metrics grid, Run Detail as a pushed destination, Memory/Integrations/Logs screens (unsupported), "Groups" placeholders, mock suggestion chips tied to mock IDs. Nothing working is deleted. The Kanban board, Scheduled view, usage, skills, tools and MCP move behind Studio and Threads.

### 1.4 Where the agreed direction needs correcting

1. **"Approve / Reject" on Needs You is mostly not possible today.** Design the full approval card, but in Phase 1 dangerous approvals render as **"Approve on your Mac"** with Stop and "At my desk". The actionable Needs You items Talaria *can* resolve are clarifications, decisions, Kanban reviews and interventions. Do not ship a fake Approve button.
2. **"Later" cannot postpone Hermes.** A clarification expires in under five minutes whatever the phone does. On those items, Later is honest copy: "Hermes stops waiting at 3:42 PM." Later is a real local snooze only for items without a short Hermes deadline: interventions, reviews and Mac-only approvals.
3. **"This thread only" model changes don't exist for running threads.** Hermes fixes model and reasoning when the session is created. Phase 1 scopes are **Next ask** (creation-time override) and **Agent default** (`PATCH /bots`). "Until changed" is folded into Agent default plus a one-tap **Revert** that Talaria remembers. A real per-thread switch needs a new capability (§18).
4. **Reasoning effort per agent and agent pause don't exist** in the contract. Reasoning is creation-time only, for backend conversations. Pause applies to routines, not agents. Phase 1 shows reasoning as a next-ask option and says agent-level reasoning is set on the Mac. There is no fake pause switch.
5. **Threads per agent require one bridge endpoint.** Without `POST /bots/{id}/conversations`, "Ask Research to find a compressor part" can only land in Research's single canonical Bot Chat, and the work-item model collapses into one thread per agent. This is the one backend item I recommend treating as a Phase 1 prerequisite (§18, §25).
6. **Auto-routing has no backend.** Phase 1 routing is deterministic and client-side: name prefix → that agent, otherwise Hermes. Charm does the same (a wake word plus a narrow rule, no model call). Model-based routing comes later and is never required for correctness.

---

## 2. Design thesis

**Talaria is a remote for work, not a window onto a desktop.** Every screen answers one of three questions in under two seconds: *Does anything need me? What is happening? What came back?* Every interaction finishes with the phone going back in your pocket.

Five commitments that follow:

1. **Work is the noun.** People open threads ("Find replacement compressor part"), not runs, sessions or profiles. Runs, steps and event logs are evidence inside a thread, one tap down.
2. **Needs You is sacred.** Only things blocked on you appear there, and they are the only cards with an elevated, tinted surface. If Needs You is empty, the screen literally says *Nothing needs you*, and that is the success state.
3. **Hand off, then walk away.** Sending never navigates you into a waiting screen. You get a one-line confirmation ("Handed to Research") and the work shows up on Now.
4. **The screen never lies.** No ✓ before Hermes confirms, no percentage without a real denominator, no "Synced" before the bridge acknowledges, no Approve button that can't approve. Unknown is shown as unknown, and stale data carries its age.
5. **Agents are people you can ask, not settings to visit first.** Ask works without choosing anyone. When you do care, the agent is one tap away: in the route chip, on Agents, or by saying its name.

---

## 3. Final information architecture

```
Tab bar:   Now        Threads        Agents
Accessory: [ ⤓ ]  [ (◐) Ask Hermes…                    🎙 ]   ← Ask + Capture, above the tab bar
```

| Destination | Answers | Contains |
|---|---|---|
| **Now** (default) | "What needs my attention right now?" | Status line, Needs You, Working, Done, Next Up, Outbox (only when non-empty) |
| **Threads** | "What work exists and where is it?" | All work items (conversations + Kanban tasks), search, filters, Board (Kanban) |
| **Agents** | "Who can I ask, and how are they set up?" | Roster with state, Agent detail with operational settings, routines per agent |
| **Ask** (global) | "Do something." | Tap to type, hold to talk, visible route, reroute |
| **Capture** (global) | "Keep exactly this." | Verbatim text/voice/photo/file/link, offline queue |
| **Studio** (secondary screen, not a tab) | "Is the Mac OK? What else is there?" | Connection, hosts, usage, skills, tools, MCP, capabilities, settings, simulation |

**Work item** is a client projection over existing records (§18):

- `conversation` work item: a Hermes session plus its observed runs, attention items and artifacts.
- `task` work item: a Kanban task plus its attempts, comments and activity (when `kanban` is supported).
- Routine output arrives as conversations (`source: cron`) and is a normal work item tagged *Routine*.

Fan-out inside Hermes stays inside the one work item that started it.

---

## 4. Navigation specification

### 4.1 Tab bar

| Tab | Label | SF Symbol | Badge |
|---|---|---|---|
| Now | "Now" | `circle.dotted.circle` (selected: `circle.circle.fill`) | Count of **actionable-now** Needs You items (not snoozed, not Mac-only). No badge for Mac-only items. |
| Threads | "Threads" | `bubble.left.and.text.bubble.right` | None. Unread is shown inside the list, not as a badge. |
| Agents | "Agents" | `person.2` | None |

Tab reselect pops to root; reselecting at root scrolls to top (system behavior). `AppTab` becomes `.now, .threads, .agents`.

### 4.2 Ask and Capture placement: the tab bar accessory

**Decision:** Ask and Capture live in a persistent **bottom accessory directly above the tab bar**. This uses iOS 26 `tabViewBottomAccessory` with `tabBarMinimizeBehavior(.onScrollDown)`, the same pattern as the Music mini-player. When the tab bar minimizes on scroll, the accessory folds inline beside it, so it never covers content.

Why this and not the alternatives:

- **Floating action button:** not an iOS idiom. It covers list content and is one-target only, but Ask needs tap, hold and a route chip.
- **A fourth "Ask" tab** (or the `.search`-role tab slot): a tab is a place, but Ask is an action that must keep context. You'd lose the current screen, and you can't hold a tab to talk.
- **A toolbar button:** top-of-screen, two-handed, and invisible inside long lists.
- **The accessory:** thumb-reachable, always present, native, and it can carry three affordances (Capture, route chip + field, mic) without looking like a dashboard.

**iOS 18 fallback:** the same `AskBar` view attached with `.safeAreaInset(edge: .bottom)` on each tab root, above the standard tab bar, on `.bar` material. The deployment target stays at 18 (§25 lists raising it as optional).

**Inside a thread** the tab bar and accessory are hidden (existing behavior). The thread's composer *is* Ask, scoped to that thread. Capture stays reachable from the composer's `+` menu (§10.1).

Accessory anatomy (44 pt tall content, 8 pt horizontal insets):

```
┌──────────────────────────────────────────────────────────┐
│ [⤓]  (◐ Auto) Ask Hermes…                          [🎙]  │
└──────────────────────────────────────────────────────────┘
  │     │        │                                    │
  │     │        └ tap: open Ask sheet, keyboard up   └ tap: toggle dictation (accessibility path)
  │     └ route chip: tap = Agent picker                hold: push-to-talk (same as holding the field)
  └ Capture: tap = Capture sheet; hold = voice capture
```

- The route chip shows the *current default target*: "Auto" (Hermes routes) or a pinned agent's avatar + name when Ask was opened from an Agent context.
- Placeholder: "Ask Hermes…" in Auto; "Ask Research…" when targeted.
- **Holding anywhere on the field region or the mic** starts push-to-talk (§9.4). Holding the Capture glyph starts voice capture (§10.3). The two hold targets are 120+ pt apart and use different glyphs, tints and overlay layouts.

### 4.3 Push navigation (per-tab `NavigationStack`, shared `Route` table)

| Route | Screen | From |
|---|---|---|
| `.thread(WorkItemID)` | `ThreadView` (conversation) or `TaskThreadView` (Kanban) | Now rows/cards, Threads, Agent detail, deep links |
| `.newThread(AskSeed)` | Only used when the user explicitly picks "Open thread" after sending | Ask confirmation |
| `.agent(String)` | `AgentDetailView` | Agents, avatars in thread header, route chip "View agent" |
| `.routine(String)` | `RoutineDetailView` (existing) | Next Up, Agent detail |
| `.board` | `KanbanView` (existing, demoted) | Threads toolbar |
| `.scheduled` | `ScheduledView` (existing) | Now › Next Up "All", Agent detail |
| `.studio` | `StudioView` (replaces More) | Now nav-bar connection chip, Agents toolbar |
| `.hosts`, `.host(id)`, `.usage`, `.skills`, `.skill`, `.tools`, `.mcp`, `.mcpServer`, `.settings`, `.capabilities` | Existing screens | Studio |
| `.approval(id)` | Existing `ApprovalDetailView`, retitled "Request details" | NeedsYouCard "Details" |

`.run(id)` stays in the enum for deep links but resolves to the run's thread with the Steps sheet open. If the run has no conversation, it shows Steps as a full sheet.

### 4.4 Sheets

| Sheet | Detents | Opened by |
|---|---|---|
| `AskSheet` | medium → large; keyboard up | Accessory tap, Agent "Ask", deep link |
| `CaptureSheet` | medium | Accessory Capture tap, composer `+` › Capture, deep link/share later |
| `AgentPicker` | medium | Route chip, "Reroute" |
| `StepsSheet` | medium, large | RunCard "Steps", result footer "Steps", `.run` deep link |
| `SteerSheet` (existing, restyled) | medium | RunCard "Add instruction" when the composer isn't visible (Now swipe, Agent detail) |
| `ModelPicker` → `ScopeChoice` | large (picker), then inline scope step | Agent detail › Model, Ask options › Model |
| `RiskConfirmSheet` | medium (fitted) | Any medium/high-risk action (§11.8) |
| `LaterMenu` | `Menu` (not a sheet) | NeedsYouCard Later |
| `BotEditorView` (existing, renamed "Edit Agent") | large | Agent detail › Edit configuration |
| `HostEditorView` (existing) | large | Studio, pair again |

Modals that cover the whole screen: Camera (existing `UIImagePickerController`). Nothing else.

### 4.5 Context menus (long-press)

| On | Items |
|---|---|
| Work item row (Now/Threads) | Open · Mark as Read/Unread · Pin/Unpin · Ask in This Thread… · View Agent · Steps (if a run exists) · Archive · *Delete…* (destructive, confirm) |
| NeedsYouCard | Open Thread · Details · Later ▸ presets · Dismiss (interventions only) |
| Agent row | Ask \<Agent\>… · Talk to \<Agent\> (starts push-to-talk targeted) · Change Model… · View Routines |
| Result message | Copy · Share · Steps · Ask a Follow-up… · Capture This Result (verbatim copy into Capture) |
| Route chip | Agent list (quick reroute) · Auto |

### 4.6 Swipe actions

| List | Leading | Trailing |
|---|---|---|
| Threads rows | Read/Unread (blue) · Pin (orange is reserved; use `.gray`) | Archive (gray, full-swipe allowed) · More… (context sheet) |
| Now › Working rows | none | Stop (destructive tint; opens `RiskConfirmSheet`, never stops on full swipe) |
| Now › Done rows | Mark Read | Archive |
| NeedsYouCard | **none.** Cards keep their actions visible; swiping decisions is too easy to do by accident. |
| Outbox rows | none | Delete (local) |

### 4.7 Back behavior

- Standard edge-swipe back in all stacks.
- Opening a thread from a Now card pushes onto the **Now** stack, not a cross-tab jump. Back returns to Now with scroll position kept.
- The Ask sheet dismisses on swipe down; the draft is kept per target (`DraftStore` key `ask.<target>`).
- After sending from Ask, the sheet dismisses and you stay where you were. "Open" on the confirmation toast pushes the thread on the current stack.
- Notification taps (local today, APNs later) and deep links switch to the Now tab and push the target onto a reset Now stack.

### 4.8 Deep-link destinations (URL scheme `talaria://`, also App Intents later)

| URL | Result |
|---|---|
| `talaria://now` | Now tab, root |
| `talaria://thread/{workItemID}` | Now stack → thread |
| `talaria://thread/{workItemID}/steps[?run={runID}]` | Thread with the Steps sheet |
| `talaria://needs/{itemID}` | Now, scrolled to and highlighting that card (1 s tint pulse) |
| `talaria://agent/{agentID}` | Agents → detail |
| `talaria://ask?agent={id}&text={…}` | Ask sheet pre-filled; **never auto-sends** |
| `talaria://ask/voice?agent={id}` | Ask sheet already listening (for the Action Button later) |
| `talaria://capture?text={…}` | Capture sheet pre-filled; saves only on explicit Save |
| `talaria://capture/voice` | Capture sheet already recording |
| `talaria://studio` | Studio screen |

---

## 5. Now

### 5.1 Layout

```
Now                                         (● Studio)      ← large title; trailing connection chip
1 needs you · 2 working · next routine 7:00 AM              ← status line (subheadline, medium)

NEEDS YOU  1
┌──────────────────────────────────────────────────────────┐
│ ◐ Research Worker · Compressor part search      3m left  │  ← who · thread · deadline
│ Which supplier should I contact first?                   │  ← request (headline)
│ [ Grainger ]  [ Ferguson ]  [ Answer… ]                  │  ← actions
│ Later ▾                                                  │
└──────────────────────────────────────────────────────────┘
Later (2) · 1 at your desk                              ›   ← snoozed summary row

WORKING  2
(◐) Fix Talaria notifications                      14m
    ● Running xcodebuild test…                             ← live current action
(◐) Research RTX 5070 local models                  3m
    ● Reading 4 sources

DONE
• ✓ Morning brief                              Routine · 7:02
    Three items: car wash pump quote, …                    ← unseen dot leading
  ✓ MAJOR//MINOR article outline                Muse · 2h

NEXT UP
  7:00 AM  Morning brief · Hermes
  Sun      Weekly backup check · Hermes                All ›
```

- `List(.plain)` with `listSectionSpacing(.compact)`. Section headers use the existing `SectionHeader` (tracked caps, trailing count).
- NeedsYouCards sit in rows with clear row backgrounds and 16 pt horizontal insets, 8 pt between cards. Working, Done and Next Up are plain rows with separators inset to the text column.
- **No host metrics grid.** CPU, memory and latency move to Studio.

### 5.2 Navigation bar and header

- Large title **"Now"**. The brand word "Talaria" leaves the operational screen (it stays in Studio › About and pairing).
- Trailing toolbar item: `ConnectionChip`, a 7 pt `StatusDot` plus the host's short name ("Studio"). Tap pushes `.studio`. With multiple hosts, long-press gives a host switcher menu. Its states:
  - Connected: green dot, secondary text.
  - Connecting/reconnecting: mini progress view and "Connecting".
  - Offline: gray `wifi.slash` and "Offline".
  - Hermes down: orange triangle and "Hermes".
  - Pairing needed: red lock.
- **Status line** (one `Text`, wraps at large sizes), built deterministically:
  - `N need you` (attention color) when actionable items exist; otherwise `Nothing needs you` (secondary, with a small `checkmark` glyph).
  - `· N working` (accent) when active work exists.
  - `· next routine 7:00 AM` when a routine is due in the next 12 h.
  - When degraded, it is replaced by the connection sentence: `Studio unreachable · as of 12m ago` plus an inline **Retry** button (borderless).

### 5.3 Needs You section

- Order: (1) items with a live deadline, soonest first; (2) actionable items, newest first; (3) Mac-only items; (4) failures and interventions.
- Show the **first 3** cards in full. If there are more, a row reads "**4 more** · 2 approvals on Mac, 2 failures"; tapping it expands inline with a snappy animation.
- **Grouping** [client]: items with the same `kind`, the same agent and the same work item collapse into one `NeedsYouGroupCard` ("3 approvals from Research Worker · Supplier search"). Expanding shows compact sub-rows. Bulk actions exist only for low-risk intervention types: "Dismiss all 3", or "Retry all" for failed runs whose `controls.retry` is true. Never bulk-answer questions or decisions.
- **Snoozed** items leave the section and are summarized in one quiet row, "Later (2) · 1 at your desk ›", which pushes a plain list of snoozed items with an "Unsnooze" swipe.
- **Empty:** the section header disappears and a single row reads `✓ Nothing needs you` (body, secondary; a green checkmark is the only color). No illustration and no extra copy. If there are also no Working and no Done items, the row reads `Nothing needs you. Hermes is idle.`

### 5.4 Working section

- Rows are `WorkItemRow(.live)`: avatar (28 pt) with status dot, title (2 lines), and a live line with the current action and an elapsed time (monospaced digits, ticking).
- Sources: active bridge runs (grouped to their work item, one row per work item even with several runs) and Kanban tasks in progress.
- Max 5 rows, then "**All working (7)** ›" → Threads with the `Active` filter.
- Tap → thread. Trailing swipe → Stop (confirm). Long-press → context menu.
- **Empty:** the section is omitted. The status line already says nothing is working.

### 5.5 Done section

- Shows results that are worth seeing [client, deterministic]:
  - work items whose latest run is `completed` and ended in the last 24 h, where the run is bridge-owned or a routine result;
  - Kanban tasks that moved to done in the last 24 h.
  Unseen items come first, then up to 5 total.
- Failures never appear here; they are interventions in Needs You.
- Row: outcome glyph (`checkmark.circle.fill`, success), title, then one line of the result (first meaningful sentence of the final assistant text, up to 120 chars), agent name and time. A leading blue unread dot appears until the thread is opened.
- "Earlier ›" → Threads (All).
- **Empty:** omitted.

### 5.6 Next Up

- Shown only when routines are due in the next 24 h. Up to 3 single-line rows: time, routine name, agent. "All ›" → `.scheduled`.
- Paused routines never appear here.

### 5.7 Outbox (conditional)

- Appears at the very top, above Needs You, only when local unsent items exist:
  - "**2 captures waiting for Studio**" (auto-sync, §10.5);
  - "**1 ask not sent**" (needs a tap to send, §9.8);
  - "**1 uncertain**" (command receipt pending; check before resending).
- Row → `OutboxView` (plain list with per-item state and actions).

### 5.8 Refresh behavior

- Live updates come from the SSE stream (existing). Rows reorder with list animation; a row moving from Working to Done animates out and in. Under Reduce Motion it is a crossfade.
- Pull-to-refresh → `environment.refreshAll()` (existing), using the standard system spinner.
- Foreground → reconnect if needed, then refresh (existing `scenePhase` handling).
- A relative-time `TimelineView` updates "as of" labels every 30 s.

### 5.9 Hermes / Studio unreachable

- The status line becomes the connection sentence with Retry (above).
- All sections render from the cache:
  - Section headers gain a trailing "as of 12m ago" (secondary, never tertiary).
  - Working rows render the live line as `Last known: Running xcodebuild… · 12m ago` and the dot stops pulsing.
  - NeedsYouCards keep their content, but every action is disabled and a single footnote reads "Reconnect to answer." The Later menu still works (local).
  - Deadlines that pass while offline turn into the expired treatment (§11.7) on the client clock.
- Pairing required: a pinned intervention card, "Pair this iPhone again", with a **Pair Again** button, is the first Needs You item.
- Never cached and offline: a single `OfflineContentView` with Reconnect (existing component).
- Ask and Capture stay enabled (§9.8, §10.5).

---

## 6. Threads

### 6.1 List

- Large title **"Threads"**. Searchable (`.searchable`, prompt "Search threads"), with **search scopes**: All · Active · Needs You · Unread.
- Toolbar trailing: a filter `Menu` (`line.3.horizontal.decrease`) with:
  - Agent ▸ (multi-select);
  - Source ▸ (iPhone, Desktop, Terminal, Routine, Telegram…);
  - Show Archived (toggle);
  - Board (Kanban) ›, when supported.
  A filled filter icon means a filter is active, and a pill under the search bar shows "Research · Routine ✕".
- Sections:
  1. **Pinned**, if any;
  2. **Active**: work items with active runs, needs-you state or Kanban in progress, ordered needs-you → working;
  3. **Today / Yesterday / This Week / Earlier**: by last activity.
  Search ignores sections and ranks by recency. Bridge search (`?q=` Hermes session search) runs after 300 ms debounce for queries of 3+ characters, merged under a "Matches in Hermes" section with snippets.

### 6.2 WorkItemRow (Threads variant)

```
•(◐) Find replacement compressor part                 9:41
      ✓ Found 3 suppliers; Grainger has it in stock
      Research Worker · Routine                    📎 2
```

- Line 1: unread dot (8 pt accent, leading gutter), avatar (36 pt), title (body semibold, 2 lines), timestamp (caption, secondary, monospaced digits).
- Line 2, the state line: one of
  - `● Running tests… · 4m` (accent);
  - `◐ Needs you: Which supplier?` (attention);
  - `Approve on your Mac` (attention, `desktopcomputer` glyph);
  - `✓ <result snippet>`;
  - `✕ Failed: <plain reason>`;
  - `■ Stopped`;
  - `? Outcome unknown` (secondary);
  - otherwise the last message preview.
- Line 3, metadata (caption, secondary, only when informative): agent name when it isn't Hermes, source tag when not iPhone, `Routine`, `Task` (Kanban), project chip, attachment/artifact count.
- Kanban work items use a `checklist` badge on the avatar corner and show the Kanban state ("In review", "Blocked: missing API token").

### 6.3 Unread / unseen behavior [client]

- `lastSeenAt[workItemID]` is stored locally per host, in `AppPreferences` or a new `SeenStore`.
- A work item is **unread** when `max(latestTerminalRun.endedAt, latestAssistantMessage.createdAt) > lastSeenAt`, **and** that activity didn't come from this phone's own outgoing message.
- Opening the thread marks it seen at that moment. Swipe and context menu toggle it manually.
- Imported or Desktop conversations seen for the first time are **not** unread (avoids a wall of dots after pairing): on first sync, set `lastSeenAt = lastActivity` for everything.

### 6.4 Active vs completed

- Active work items always sort into **Active** regardless of date.
- Completed items carry the result snippet, never the user's question, so the list reads as outcomes.
- Archive hides an item from all scopes except "Show Archived"; it is a `PATCH archived:true` [bridge, exists]. Canonical Bot Chats can't be archived (protected) and don't offer the swipe.

### 6.5 Empty, loading and error states

- Empty (no threads at all): `ContentUnavailableView` titled "No threads yet", description "Ask Hermes something. Work you start here, on your Mac or from routines shows up in this list." No button; the Ask accessory is right there.
- Empty search: `ContentUnavailableView.search(text:)`.
- Empty filtered scope ("Needs You"): one line, "Nothing needs you."
- Loading first time: `LoadingRows(6)` redacted (existing).
- Error with cache: cached list plus `ConnectionNoticeSection` (existing).

---

## 7. Thread detail

### 7.1 Structure (reuses `ConversationView`)

```
‹ Threads   (◐) Find replacement compressor part     ⋯
            Research Worker · Working
─────────────────────────────────────────────────────────
┌ ● Working · Searching supplier catalogs        6m ─────┐  ← WorkStatusBar (pinned, only while active)
│ [Add instruction]  [Stop]                     Steps ›  │
└────────────────────────────────────────────────────────┘

                    Find a replacement compressor for the     ← user bubble (existing)
                    Ingersoll Rand 2475 at the car wash
(◐) Research Worker
   Searching supplier catalogs…                            ← RunCard (collapsed)
   4 steps · Steps ›

   ↳ Hermes started 2 subagents · not tracked from iPhone   ← HandoffMarker / untracked

┌ NEEDS YOU · 3m left ───────────────────────────────────┐  ← pinned above composer while blocked
│ Which supplier should I contact first?                  │
│ [ Grainger ] [ Ferguson ] [ Answer… ]                   │
└─────────────────────────────────────────────────────────┘
[+]  Add an instruction…                             [🎙]   ← thread Ask (composer)
```

- **Navigation title** (existing `ConversationTitle`): avatar, title, subtitle.
  - Subtitle is the agent name plus the work state ("Working", "Needs you", "Done 2m ago", "Last known: working").
  - Tapping the title area opens a small menu: View Agent · Rename · Pin · Steps · Files (N).
- **Toolbar ⋯**: Rename, Pin, Mark Unread, Files, Steps, View Agent, Archive, Delete (destructive confirm).
- **WorkStatusBar** (new, `pinnedTopBar`): shown only while a run in this thread is active.
  - One line: state + current action + elapsed.
  - Controls: **Add instruction** (focuses the composer in steer mode), **Stop** (confirm), **Steps ›** (sheet).
  - It replaces the controls row of `LiveRunBlock`, so controls stay reachable however far you've scrolled.
- **Transcript** (existing `TranscriptItem` / `MessageView`):
  - user bubbles;
  - assistant text full-width;
  - tool groups collapsed (existing `ToolActivityView`, "Used N tools");
  - `RunCard` for the active run inline at the bottom, replacing `LiveRunBlock`'s visual weight (§12);
  - `ResultFooter` under the final assistant message of each completed run.

### 7.2 Result cards

The final assistant message **is** the result. It is not boxed: it reads as text, with a quiet footer.

```
   Grainger has the IR 2475 pump (SKU 32301234) in stock at …
   [markdown body]
   📄 supplier-comparison.pdf   48 KB                          ← ArtifactRow(s)
   ✓ Done · Research Worker · 6m 12s · Steps ›         ⓘ       ← ResultFooter
```

- `ResultFooter` (extends the existing `MessageFooter`): outcome glyph and word, agent, duration, **Steps ›**, and ⓘ (the existing `RunSummarySheet` telemetry).
- Failed run: `FailureCallout` (existing) under the partial output, with **Retry** when `controls.retry` is true. Retry is a **new run**, and the copy says "Runs it again; earlier effects are not undone."
- Stopped: a "Stopped by you" system row; partial output is kept and labeled "Partial: stopped before finishing".
- Unknown: "Outcome unknown. Talaria didn't see this finish. Check on your Mac before asking again." No retry. While the bridge blocks submission, the composer shows "Hermes is still settling this thread" and offers **New thread with this ask**.

### 7.3 Handoffs

- [client] `HandoffMarker` is a single centered system row (caption, secondary, with a `arrow.turn.down.right` glyph):
  - `Hermes → Research Worker` when a Kanban task linked to the thread is assigned or reassigned;
  - `Hermes started a subagent` for a `delegate` tool call.
  It never interrupts reading and never uses color.
- When the observed agent changes between runs inside one thread, the RunCard and ResultFooter show the new agent's avatar. The thread title and header keep the thread's *owning* agent.

### 7.4 Artifacts

- Inline: `ArtifactRow` under the result message whose run produced it (`artifact.run_id`), else under the latest result.
  - Row content: file glyph, name, size, type.
  - Tap → authenticated download → Quick Look (existing).
- Collected: "Files (N)" in the header menu opens a sheet listing all thread artifacts newest-first.
- Discovery is incomplete by contract, so the sheet footer reads "Only files Hermes registered for the phone appear here."

### 7.5 Steering

- While a run is active, the composer is in **steer** mode (existing `.steer`):
  - placeholder "Add an instruction…";
  - indigo field stroke;
  - send glyph `arrow.turn.down.right.circle.fill`;
  - mode line "Goes to the current work. Hermes reads it at its next step."
- After sending, the instruction appears inline as a steering step (`StepLine` "You: …") with the state **Sent**. It never says "Applied" or "Read", because the bridge only reports `queued`.
- Rejected: an inline note "Hermes didn't accept the instruction" with **Send as a follow-up** (queues it as normal text in the composer).

### 7.6 Show Steps

- `StepsSheet` (`RunDetailView` content in a sheet, minus the duplicated header):
  - **Now:** the live checklist (`LiveSteps`);
  - **Timeline:** the full event log (`RunTimeline`), with an event count;
  - **Details:** model, reasoning, project, started/ended, run ID (copyable), tokens.
- With several runs in the thread, a run switcher sits at the top: a segmented-style menu, "Run 3 of 3 · now ▾".
- The event log is never a destination; it is reachable only from Steps.

### 7.7 Starting a follow-up

- When nothing is running, the composer is in **send** mode: "Ask a follow-up…", sending into the same thread (same session, same agent).
- The composer's mode line shows the thread's agent and model, read-only. Tapping it opens Thread Options:
  - Model "Fixed for this thread · <model>" with a footnote: "Hermes sets a thread's model when it starts. Change Research's default or start a new thread to use another model."
  - Buttons: **Change agent default** and **New thread with…**.
- "New thread with this" (context menu on any result): opens Ask targeted at the same agent and prefilled with a quote of the selected result's first line. The user edits, then sends. [client, deterministic; no hidden summary.]

### 7.8 Kanban work items (`TaskThreadView`)

- The existing `TaskDetailView` content, re-ordered as a thread:
  - header (title, assignee avatar, state);
  - **Needs You** card if blocked or in review;
  - body/summary;
  - attempts as RunCard-like rows (state, worker, duration);
  - activity/comments as a timeline;
  - Steps per attempt.
- Actions are the supported transitions from `supported_targets` (existing), each with the risk tier from §11.8.

---

## 8. Agents

### 8.1 List

```
Agents                                              [+]

(◐) Hermes                                     ● Working
    Fix Talaria notifications · 14m
    Sonnet 4.6
(◐) Research Orchestrator                   ◐ Needs you
    Which supplier should I contact first?
    Opus 4.6 · changed 2h ago
(◐) Research Worker                                  2h
    Last: Morning brief
    Haiku 4.5
```

- `List(.insetGrouped)`, one section, no "Default Profile" section. Hermes is the default agent and is pinned first with a subtle `Default` tag.
- Order after Hermes: needs you → working → most recent activity.
- Row:
  - `ProfileAvatarWithStatus` (44 pt), name (body semibold);
  - a trailing state word: "Working", "Needs you", or relative last-active;
  - line 2: current work title, pending request, or "Last: <title>";
  - line 3: model, plus "changed 2h ago" when Talaria changed it recently (§8.4).
- Toolbar: `+` (create agent, existing `BotEditorView`, when `botCreate`). Leading: `ConnectionChip` (same as Now).
- 15 s refresh while visible (existing).
- Hidden agents are not listed. Footer: "Hidden agents are managed in Hermes Desktop."

### 8.2 Identity

- Avatar: Desktop blob face when available, else the identity-hue glyph (existing `ProfileAvatar`). Hermes uses the neutral house glyph.
- Identity hue appears only in the avatar and in the route chip's avatar. Names are always primary-color text. Color never carries meaning alone.
- The written personality comes from the agent's description (one line under the name in detail).
- Voice: a TTS voice per agent, set locally (Phase 2; reserve the row, see §8.5).

### 8.3 Agent detail

```
‹ Agents                                        Edit

(◐ 64)  Research Orchestrator
        Plans research and delegates to workers.

[  Ask Research Orchestrator  ]  [ 🎙 ]                 ← primary row: tap / hold-to-talk

NOW
  ◐ Needs you · Which supplier should I contact first?   ›
  ● Research RTX 5070 local models · 3m                  ›

RUNTIME
  Model              Opus 4.6 · Anthropic             ›
                     Changed from Sonnet 4.6 2h ago · Revert
  Reasoning          Set on your Mac                   ⓘ
  Routines           2 active                          ›
  Voice              Default (Phase 2)

RECENT WORK
  ✓ Morning brief · 7:02                               ›
  ✓ GPU price sweep · Yesterday                        ›
  All threads with Research Orchestrator              ›

CONFIGURATION
  Personality (SOUL)  5 lines …                         ›
  Skills 12 · Toolsets 4 · MCP 2                        ›

  Duplicate Agent
  Hide Agent                                    (destructive)
```

- **Primary actions:**
  - **Ask \<Agent\>** (bordered prominent, full width minus mic) opens `AskSheet` targeted at this agent.
  - The mic button supports **hold-to-talk targeted** at this agent, and tap toggles dictation in the Ask sheet.
  - For agents without bridge thread creation (§1.4 #5), Ask goes to the canonical Bot Chat, and the sheet says "Continues Research Orchestrator's chat".
- **Now:** this agent's Needs You items and active work items (rows identical to Now).
- **Runtime:** the operational settings (§8.4–8.6). Only rows the host supports appear; unsupported ones show a quiet value plus ⓘ explaining where to change them, never a disabled control with no explanation.
- **Recent work:** last 3 work items, then "All threads with \<Agent\>" → Threads filtered by agent.
- **Configuration:** read summaries. **Edit** (toolbar) opens the existing `BotEditorView` for name, description, SOUL, skills, toolsets and MCP. That covers full SOUL editing; credentials, raw provider config, memory policy and tool permissions stay on the Mac and are not shown.
- **Management:** Duplicate (low risk), Hide (medium; `RiskConfirmSheet` with the existing copy).

### 8.4 Model picker and scope

Flow:

1. Tap **Model** → `ModelPicker` (pushed inside a sheet, large detent).
   - Search field.
   - "Recent" group (last 5 models chosen on this phone).
   - Then providers as sections, each model row showing name, provider and capability tags (`Reasoning`) from inventory.
   - Checkmark on the current model.
   - The source is `GET /bots/inventory?bot_id=` (existing), falling back to `/inventory/models`.
2. Selecting a different model shows the **scope step** inline at the bottom of the sheet (a fitted card, not a second modal):

```
Use Opus 4.6 for…
 ◉ Research Orchestrator's default
   New work and its chat use it from the next run. Hermes Desktop sees the change.
 ○ My next ask only
   Starts one new thread with Opus 4.6. The default stays Sonnet 4.6.
                                         [ Apply ]
```

   - "Next ask only" appears only when the agent can receive new threads with creation overrides. Those are backend profiles today, or bots once `POST /bots/{id}/conversations` accepts model/provider.
   - When it isn't available, the step is skipped: one confirmation row "Change Research Orchestrator's default to Opus 4.6?" with **Change Default**.
3. **Agent default** → `PATCH /bots/{id} {model, provider}`.
   - On `409 bot_model_confirmation_required`, show a `RiskConfirmSheet` with Hermes's message verbatim ("This model costs more…") and **Use Opus 4.6** (high tier, §11.8: press-and-hold). Resubmit with `confirm_expensive_model:true`.
   - On success, re-read the profile (bridge already re-reads) and toast "Research Orchestrator now uses Opus 4.6".
   - The Runtime row shows "Changed from Sonnet 4.6 · 2h ago · **Revert**" [client: stores `previousModel` + `changedAt` per agent].
   - Revert is one tap (same PATCH, same confirmation rules). The note clears on Revert, on "Dismiss" from the row context menu, or when the server value no longer matches what Talaria set (someone changed it on Desktop; the note then reads "Changed on another device").
4. **Next ask only** → Talaria opens `AskSheet` targeted at the agent with a visible override chip `Opus 4.6 ✕`. The override applies to that single new thread at creation and is cleared after send.

**Why only two scopes:** Hermes has no temporary-override concept. A client-side "until changed" would silently diverge from what Desktop shows. Default + Revert gives the "just until I'm home" behavior honestly.

### 8.5 Reasoning / effort, provider, voice

- **Reasoning:**
  - Next ask: a segmented control in Ask Options (None · Low · Medium · High · Max), shown only when the chosen model reports reasoning support. It maps to `reasoning_effort` at creation (existing). "Max" = `xhigh` when the host lists it.
  - Agent default: not exposed by the bridge. The row shows "Set on your Mac" with ⓘ "Hermes stores reasoning in the agent's configuration, which Talaria can't change yet."
- **Provider/account:** chosen implicitly by the model+provider pair (inventory groups by provider). There is no separate account switcher; that would be credentials territory.
- **Voice** (Phase 2, with TTS): a per-agent local preference among system voices and a "Speak replies" toggle (§9.10). In Phase 1 the row is **not shown** (no dead settings). This spec only reserves its place.

### 8.6 Pause / resume

- There is no agent pause in Hermes. Phase 1 offers **Routines** with a count, pushing a list of that agent's routines with per-routine Pause/Resume toggles (existing `setEnabled`), and a header action "Pause all (2)". That is medium risk: confirm with the list of routines it affects.
- Stopping active work stays per thread. There is no "pause agent" switch until Hermes supports one (§18).

### 8.7 Starting work explicitly with an agent

- Agent detail **Ask** button / mic hold.
- Agent row context menu "Ask \<Agent\>…" / "Talk to \<Agent\>".
- Route chip in Ask (§9.5).
- Saying the agent's name first in Ask voice or text ("Research, find…"), §9.5.

---

## 9. Ask

### 9.1 Collapsed / default state

The accessory (§4.2): `[⤓] (◐ Auto) Ask Hermes… [🎙]`. The field region is a capsule on `.bar`/glass material, secondary placeholder text and a 36 pt avatar chip. Total height is 52 pt including insets (minimizes to 44 pt inline when the tab bar minimizes).

### 9.2 Text entry: AskSheet

```
                 ──                                   ← grabber
Ask   (◐ Auto → Hermes ▾)                    Options
┌──────────────────────────────────────────────────┐
│ Find a replacement compressor for the IR 2475    │
│ at the car wash                                  │
└──────────────────────────────────────────────────┘
[📎] [📷]                                  [🎙]  [↑]
```

- Medium detent with the keyboard up; it grows to large with long text (`lineLimit(1...12)`).
- The header is a single line: "Ask" plus the **RouteChip** (§9.5). Trailing **Options** opens a disclosure that expands in place:
  - Model (creation override, chip-style picker);
  - Reasoning (if supported);
  - Project/workspace (existing projects list, configured IDs only).
  Overrides show as removable chips under the field (`Opus 4.6 ✕`, `Project: talaria ✕`).
- Attachments: the existing `ComposerMedia` pipeline (Files, Photos, Camera, max 4, 10 MiB). They upload only after the thread exists. The bridge's upload is conversation-scoped, so the client creates the conversation, uploads, then submits (existing order in `send`).
- Return inserts a newline. The send button (`arrow.up.circle.fill`, accent) sends. Hardware keyboard ⌘↩ sends.

### 9.3 Sending (walk-away)

1. Tap send → the button becomes a spinner and the field locks. States in the header: "Sending…".
2. Bridge `202 Run` received → the sheet dismisses. A toast appears at the top (existing `ToastOverlay`, extended with an optional action): **"Handed to Research Worker"** · `Open`.
   - The haptic is `.selection`.
   - The new work item appears in Now › Working as "Starting".
   - Copy rules: the toast says "Handed to", because the bridge accepted it. "On it" appears in the row only when the run state becomes `running`.
3. Failure before acceptance → the sheet stays, with an inline error under the field (`StatusCopy` sentence) and **Try Again** (same idempotency key).
4. `command_uncertain` → the sheet dismisses into Outbox as "Not sure this was sent". There is no auto-retry (existing receipt rules). The row offers **Check** (refresh) and, only after the check shows nothing arrived, **Send again** (new key).

From inside a thread, the composer sends without a sheet. The message appears in the transcript, the RunCard appears, and you stay in the thread.

### 9.4 Hold-to-talk

Gesture on the accessory field or mic, the Agent detail mic, the thread composer mic (hold), or the Agent row context action:

| Phase | Trigger | UI | Haptic |
|---|---|---|---|
| Arming | finger down, held 250 ms | nothing yet (avoids accidental taps) | none |
| **Listening** | mic actually capturing (audio engine running, **not** before) | Accessory expands upward into the `VoiceOverlay` (§9.4.1). Header shows the route ("Asking Hermes", or the named agent), a live partial transcript and a level glyph (`waveform` with `.variableColor`, never Siri bars) | `.impact(.medium)` once on capture start |
| Locked (optional) | slide up ≥ 60 pt | lock glyph fills; you can lift your finger; a **Send** button and **Cancel** appear | `.impact(.light)` |
| Cancel | slide left ≥ 80 pt (shows a "Slide to cancel" hint at 40 pt) or tap Cancel | overlay collapses; nothing sent; transcript discarded | `.impact(.soft)` |
| **Transcribing** | release | "Finishing…" while the final recognition result arrives (≤ 1.5 s timeout, then the last partial is used) | none |
| **Review strip** | final text available | Text shown in the overlay with a 1.5 s auto-send ring on the send button. Buttons: **Edit** (opens AskSheet with text), **Cancel** | none |
| Sent | auto-send fires or Send tapped | collapses to the "Handed to …" toast | `.selection` |

- Limit: 60 s per hold. A fuse line along the overlay's top edge shows the remaining time in the last 10 s.
- Under 0.5 s of audio or empty recognition → "Didn't catch that". Nothing is sent and the overlay closes after 1.5 s.
- Setting **Review voice before sending** (Settings › Voice, default off) removes the auto-send ring; you must tap Send.
- Permission denied → the overlay shows "Microphone access is off for Talaria" with **Open Settings**.
- Network recognition (device without on-device support) → the overlay header says "Listening · Apple speech service" (existing honesty).

#### 9.4.1 VoiceOverlay layout

```
┌──────────────────────────────────────────────────────────┐
│ Asking Research Worker                      🔒 slide up   │
│ "find a replacement compressor for the ingersoll…"        │  ← partial, title3, primary
│ ≋≋≋                                ‹ slide to cancel       │
└──────────────────────────────────────────────────────────┘
```

Ask overlays use the **accent** stroke and header glyph `bubble.left`. Capture overlays are visually different (§10.3).

### 9.5 Routing and changing the agent

**RouteChip** shows *where this will go before you send*:

- `◐ Auto · Hermes` (default): avatar plus "Auto" when no agent is targeted and no rule matched.
- `◐ Research Worker` when targeted (opened from Agent context, picked, or matched by name).
- While typing or dictating, if a name rule matches, the chip animates to the matched agent (crossfade) with the label "Research Worker · from your words". Tapping it offers "Send to Hermes instead".

**Deterministic routing rules** [client]:

1. Explicit target (from Agent context or the picker) wins. It is sticky for this Ask only.
2. A **leading address**: the first 1–4 words match an agent's display name or an alias, case-insensitive, followed by `,` `:` or a pause in voice (for example "Research, …", "Hey Codex …", "Ask Muse to …").
   - Aliases: the display name, the name without suffixes like "Orchestrator"/"Worker" when unambiguous, and the native profile key.
   - The matched prefix is **kept** in the text (verbatim), not stripped.
   - Ambiguous matches ("Research" → Orchestrator and Worker) resolve to the agent the user picked last for that alias; otherwise the chip shows "Research ▾ (2)" and requires a pick before send.
3. Otherwise → **Hermes** (the default profile). Hermes can delegate internally. That delegation is Hermes behavior [LLM], shown later as handoff markers if observed.

There is no keyword/topic inference in Phase 1 (unreliable, invisible). An LLM router is a Phase 2 bridge feature that would only *suggest* a chip change before send.

**AgentPicker** (sheet, medium):
- "Auto (Hermes decides)" at top;
- then agents with avatar, name, state and model; the current one is checked.
- "Recent" ordering: the last 3 used agents at the top after Auto.
- Selecting dismisses and updates the chip with `.selection` haptic.

**Reroute after sending:** not supported as a move (Hermes sessions can't change profile). Instead the confirmation toast's context and the thread menu offer **Ask another agent…**, which opens Ask targeted elsewhere and prefilled with the original text. The UI says "Starts a new thread. This one keeps going."

### 9.6 Inside vs outside a thread

| | Outside (accessory / AskSheet) | Inside a thread (composer) |
|---|---|---|
| Creates | a new work item | a new run in the same work item |
| Route | Auto or chosen agent | fixed to the thread's agent (chip shown read-only) |
| While that thread is running | n/a | steer mode ("Add an instruction…") |
| Options | model, reasoning, project overrides | none (thread fixed); "Change agent default" link |
| Voice | hold accessory/mic | hold composer mic; same overlay, header "Adding to this thread" |

### 9.7 Cancellation

- Before send: swipe the sheet down (the draft is kept), or tap ✕ in the voice overlay.
- After send: there is no "unsend". The work item exists, and **Stop** is in the WorkStatusBar and the Now row swipe. A stop within 10 s of sending shows the copy "Stop before Hermes starts?" with the same `RiskConfirmSheet` (medium).

### 9.8 Offline Ask

- The accessory stays enabled. The AskSheet header shows a gray banner "Studio is offline. This won't be sent until you send it again."
- The send button becomes **Save to Outbox**.
- Outbox asks are **never auto-sent** on reconnect: running something hours later is a surprise. On reconnect, Now's Outbox row reads "1 ask not sent · **Send now**". The row shows the original target and an age ("from 2h ago").
- Voice Ask offline is the same: after review, the button reads **Save to Outbox**. Ask copy also offers **Save as Capture instead** (one tap converts verbatim).

### 9.9 Transcription honesty

- "Listening" is shown only while the audio engine is capturing.
- "Finishing…" while waiting on the final result.
- The text sent is exactly the reviewed transcript, with no client rewriting.

### 9.10 Spoken responses (design-ahead, Phase 2)

- "Speak replies" per agent (off by default). When on, and a reply arrives while the thread or Now is foregrounded *and* the reply came from a voice Ask in the last 10 minutes, Talaria speaks the **first two sentences** of the result with that agent's voice.
- A "Speaking" state appears in the WorkStatusBar with a **Stop speaking** control.
- The full text is always on screen. Voice never reads Needs You actions aloud as questions to answer by voice.

---

## 10. Capture

### 10.1 Fastest entry

- **Tap** the Capture glyph (`tray.and.arrow.down`) on the accessory → `CaptureSheet` with the keyboard up. Type, then **Save**. That's two taps plus typing.
- **Hold** the Capture glyph → voice capture (§10.3). Release saves after review.
- Thread composer `+` menu → **Capture** (prefills nothing; capture is never tied to a thread unless chosen).
- Result message context menu → **Capture This** (verbatim copy of the result text with a source link).
- Future (design-compatible, not Phase 1 UI): the Action Button / Control Center / Lock Screen / Siri use App Intents that open `talaria://capture` or save directly through a `CaptureIntent` with the same store. The share sheet uses a Share Extension that writes into the same local queue (App Group container).

### 10.2 CaptureSheet

```
                 ──
Capture                                          Save
┌──────────────────────────────────────────────────┐
│ compressor pressure switch is the Square D       │
│ 9013FHG, check gauge before replacing            │
└──────────────────────────────────────────────────┘
[📷] [🖼] [📎] [🔗 Paste link]         Kind: Note ▾
Saved exactly as written · Add context ▸
```

- The header says **Capture**, never "Ask". There is no agent chip and no route.
- **Kind** (optional, default inferred deterministically): Note · Idea · Task · Link · Photo · File · Voice.
  - Inference [client]: a single URL → Link; only media → Photo/File; voice → Voice; else Note.
  - Kind is metadata for Hermes; it never changes the content.
- **Add context ▸** (collapsed by default):
  - Thread (attach to an existing work item);
  - Agent (who should see it first);
  - Tag (free text).
  All optional. The context goes into the capture's metadata, not into the text.
- Footer, always visible: "**Saved exactly as written.** Hermes won't act on it unless you ask."
- **Save** enables with any content. Save → the sheet dismisses → toast "Saved on iPhone" → then "Saved to Hermes" (when the bridge confirms) replaces it if the toast is still showing. Otherwise the confirmation shows on the Outbox row and the capture's detail.

### 10.3 Voice capture

- The hold gesture is the same as Ask, but the overlay is clearly different:
  - Header glyph `tray.and.arrow.down` and text **"Capturing · word for word"**.
  - Neutral (label-color) stroke, not accent. There is no agent avatar.
  - Transcript set in the body font inside quotation marks.
- On release: **Review** with **Save** (primary), **Edit**, **Discard**. There is **no auto-save countdown**: capture is meant to be exact, so it's reviewed.
- Saved content: the reviewed transcript (marked `transcribed_on_device:true`) plus the **audio** (m4a, AAC 32 kbps mono, ≤ 60 s) when the capture endpoint accepts audio [bridge, new]. Until then, audio stays local and is labeled "Audio kept on iPhone".

### 10.4 Photo, file and link

- Photos/camera/files reuse `ComposerMedia` (sizes, types, JPEG conversion). Max 4 per capture. Captures accept the same types plus audio (when the endpoint supports it).
- Links: a pasted URL is stored verbatim. No fetching or preview generation on the phone in Phase 1 (deterministic; avoids network side effects). The row shows the host name.

### 10.5 Exact semantics and the offline queue

- **Verbatim** [client + bridge]: text is stored byte-for-byte (no trimming beyond a trailing newline), with `created_at` (device clock, ISO-8601 with offset), `client_capture_id` (UUID, idempotency key), `kind`, optional context, and attachments by upload ID.
- **Local queue** [client]: every capture is written first to a local `CaptureStore` (file-backed JSON + media files in Application Support, excluded from backup only if the user opts in), state `queued`.
- **Sync:** while connected, the queue drains FIFO. Each item uses its UUID as the idempotency key, so a retry after a dropped connection is safe (the same key returns the recorded response). Unlike Ask, captures **auto-sync** on reconnect: saving data is not acting.
- **States**, shown on the Outbox row and in capture detail:
  - `Saved on iPhone · waiting for Studio` (queued, offline);
  - `Sending…`;
  - `Saved to Hermes ✓` (bridge confirmed, with its returned ID);
  - `Not saved: <reason>` with **Retry** and **Delete**.
  A ✓ appears only after confirmation.
- **Synced captures** leave the Outbox. They remain visible for 24 h in Now's Done section only if the user had attached a thread; otherwise they are quiet. Captures are not work items until someone asks about them.
- **Ask about this:** the capture detail has **Ask Hermes about this**, which opens Ask prefilled with a reference ("About my capture from 9:41: …"). The capture stays unchanged.

### 10.6 Where captures go on the Studio [bridge, new — §18]

`POST /mobile/v1/captures` writes the verbatim payload to a Hermes-readable inbox. My recommendation is a dated Markdown file plus sidecar files in a configured `captures_root`, which a Hermes skill or the user can process. **Fallback** if the endpoint isn't built: text-only captures become Kanban **triage** tasks (`POST /kanban/tasks`, `title` = first line up to 80 chars, `body` = full verbatim text). Media is not supported in the fallback, and the UI says so.

---

## 11. Needs You

### 11.1 Card anatomy (shared)

```
┌──────────────────────────────────────────────────────────┐
│ (◐) Research Worker · Compressor part search    ⏱ 3m left │  ← meta line: who · thread · deadline
│ Which supplier should I contact first?                    │  ← request: headline, ≤ 3 lines
│ Grainger is closer; Ferguson is $40 cheaper.              │  ← context: subheadline, secondary, ≤ 3 lines
│ [ Grainger  ★ ] [ Ferguson ] [ Answer… ]                  │  ← actions
│ Later ▾                                     Open thread › │  ← secondary row
└──────────────────────────────────────────────────────────┘
```

- Surface: `.panel(tint: Theme.attention)` (soft fill + 7 % orange wash), 14 pt radius, 14 pt padding. These are **the only tinted cards in the app**.
- **Meta line** (footnote): agent avatar (16 pt) and name, `·` thread title (truncates first), trailing deadline:
  - `⏱ 3m left` (attention, monospaced, ticking each second under 2 min);
  - `until 6:00 PM`;
  - or nothing.
- **Request** (headline, primary): the question or what's being requested, never the kind label ("Approval"). Commands render in `CommandBlock` (monospace, max 4 lines, "Show all").
- **Recommended/default:** when the backend supplies one (§18), that choice gets a filled style and a `★` plus "Recommended" accessibility label. The footnote then reads "If you don't answer: Hermes picks Grainger at 3:42 PM", but only when the backend states that behavior. Without backend data, no default is shown or implied.
- **Consequence/risk line** (footnote, secondary; shown for approvals and medium/high actions): "Runs on Mac Studio in ~/talaria · deletes 3 files".
- Actions: max 3 inline buttons (`.bordered`, `controlSize(.regular)`, min 44 pt tall). The primary is `.borderedProminent` only when a recommended choice exists or the action is the obvious one ("Retry"). Further choices go in "More choices ▾".
- **Later ▾** (`Menu`) and **Open thread ›** (borderless) share the bottom row.

### 11.2 Question

Source: a clarification without choices.

- Actions: **Answer…** expands an inline text field inside the card (no navigation), with Send and a hold-to-talk mic. Dictation fills the field, and **sending still needs a tap**.
- Deadline: from `expires_at`. Under 60 s, the meta line turns `failure` color: "⏱ 0:42".
- Later: becomes "**Let it lapse**", with copy in the menu: "Hermes stops waiting at 3:42 PM. What it does next is up to Hermes." Choosing it hides the card locally; it reappears only if still pending.
- After send: the card shows `Sending…`, then "Answer sent ✓" only once the bridge acknowledges (`.success` haptic), then collapses out after 1.2 s. On `stale_attention` it shows "Too late: Hermes already stopped waiting" and moves to expired (§11.7).

### 11.3 Decision

Source: a clarification **with** choices (2–6).

- Choices are buttons. Two or three show inline; more go in a vertical list inside the card (each full-width, 44 pt).
- "Other…" opens the inline text field (same as Question).
- Default/recommended: as §11.1, only from backend data.
- A tap sends immediately; these are low-risk by definition (clarification answers). The tapped button shows a spinner, then the confirmed state.

### 11.4 Approval

Source: a dangerous tool approval (`can_respond=false`, `upstream_fifo_without_exact_target`).

**Phase 1 (current bridge):**

```
│ (◐) Hermes · Clean build cache                 2m ago    │
│ Hermes wants to run                                       │
│ $ rm -rf ~/Library/Developer/Xcode/DerivedData/Talaria*   │
│ 🖥 Approve on your Mac. Talaria can't target this safely.  │
│ [ Stop run ]                          At my desk ▾  Details│
```

- No Approve or Deny buttons.
- **Stop run** is medium risk (`RiskConfirmSheet`: "Stops all of this run. Work already done stays.").
- **At my desk** is the Later default for this type.
- **Details** opens the existing `ApprovalDetailView` (command, reason, patterns).
- Collapses in groups: "3 approvals waiting on your Mac".

**Future (when the bridge advertises exact-target `approvals.respond`):**
- Actions **Deny** (bordered) / **Approve** (prominent), with friction by tier (§11.8).
- "Approve for this session" lives in a long-press menu on Approve (existing).

### 11.5 Intervention

| Source | Request copy | Actions |
|---|---|---|
| Failed run (`failed`) | "Research run failed: \<StatusCopy title\>" | **Retry** (if `controls.retry`; low) · Open thread · Dismiss |
| Unknown outcome (`unknown`) | "Outcome unknown: Talaria didn't see this finish" | **Check on Mac** (opens Details with the explanation) · Dismiss. No Retry. |
| Blocked Kanban task | "Blocked: \<block_reason\>" | **Unblock** (→ `ready` if in `supported_targets`; medium, since it releases work to a dispatcher) · Reassign… (medium) · Open |
| Failed routine (`last_status=error`) | "Morning brief failed at 7:00" | **Run now** (medium: "Runs the routine immediately on Studio") · Pause routine (medium) · Open |
| Host/coverage issue | "Some Studio state is unavailable" | Retry · Studio › |
| Pairing required | "Pair this iPhone again" | **Pair Again** |
| Uncertain command | "Not sure this was sent" | **Check** · then Send again |

Dismiss writes a local acknowledgement (existing `acknowledgedRunIDs`, generalized to `acknowledgedNeedsYouIDs`).

### 11.6 Review

Source: a Kanban task in `review` [client derives this from `/home.kanban` `raw_state == "review"`].

- Request: "Review: \<task title\>"; context = summary/result (3 lines) and "by \<assignee\>".
- Actions:
  - **Mark done** (→ `done`; low).
  - **Send back…** opens the inline field for a note, then sets `todo`/`ready` per `supported_targets` with the note as `summary`/comment. Medium: the consequence line says "Research Worker will pick it up again."
  - Open.
- Later presets apply (real local snooze).

### 11.7 Later presets, deadlines and expiry

`LaterMenu` items (computed per item):

| Preset | Fires [client, local time] | Shown when |
|---|---|---|
| In 1 hour | now + 60 min | always (unless deadline < 1 h) |
| Tonight | today 20:00 (or +3 h if already past 19:00) | before 19:00; hidden after 22:00 |
| Tomorrow morning | next 08:00 | always |
| At my desk | no time; parks in the "At your desk" bucket | always |
| Let it lapse | — (Question/Decision only) | when `expires_at` < 1 h |

- Presets later than the item's deadline show the annotation "(after Hermes stops waiting)" and are disabled for Questions and Decisions.
- Snoozed items re-enter Needs You when their time passes and the app is foregrounded. **No promise of a reminder**: there is no APNs. The menu footer says "Shows up here again. Talaria won't notify you."
- Phase 2 can add a local notification for snooze expiry when notifications are enabled; it's honest because it's device-local.
- **At your desk** bucket: Now's snoozed row reads "1 at your desk". Opening it lists them with a "Done at desk" (dismiss) swipe. Talaria never guesses you're at your desk.
- **Expired** (deadline passed, or the bridge reports expired/stale):
  - The card turns neutral: no tint, `clock.badge.xmark`.
  - Copy: "Hermes stopped waiting at 3:42 PM. It may have continued without this."
  - Actions: Open thread · Dismiss.
  - It stays for 10 minutes, then folds into the thread history only.

### 11.8 Risk-aware friction

Tiers are internal; users see only the friction.

| Tier | Talaria actions in Phase 1 | Friction |
|---|---|---|
| **Low** | Answer clarification, pick a decision choice, retry failed run, mark review done, mark read, pin, archive, duplicate agent, dismiss intervention | Direct tap. Spinner, then the confirmed state. |
| **Medium** | Stop run, unblock/reassign/send back a Kanban task, run routine now, pause routine(s), hide agent, change agent default model, delete thread | `RiskConfirmSheet`: a fitted sheet stating the **exact effect** in one sentence, the target (agent · thread · Studio), and two buttons (Cancel / the verb). Destructive verbs use the destructive role. |
| **High** | Expensive-model confirmation (`bot_model_confirmation_required`). Future: remote approval of money, deletion, credentials or production changes. | `RiskConfirmSheet` plus **press-and-hold 1.2 s** on the confirm button (a filling capsule; release early drains in 0.3 s with no message). Future remote high-risk approvals add **Face ID** (`LAContext` `.deviceOwnerAuthentication`) after the hold. |

- **Voice can never complete a medium or high action**, and it never answers a Needs You card on its own. Voice can fill an answer field; a tap sends it.
- The hold is a `HoldToConfirmButton` (capsule, label "Hold to use Opus 4.6"). It is *not* the Apple Pay ring; the fill runs left to right inside the button.

### 11.9 Needs You state matrix

| State | Visual | Actions |
|---|---|---|
| Pending, actionable | tinted panel, live deadline | enabled |
| Pending, Mac-only | tinted panel, 🖥 line | Stop/Details/Later only |
| Sending | the tapped button shows a spinner; others disabled | — |
| Confirmed | "Answer sent ✓" / "Marked done ✓" for 1.2 s, then removed | — |
| Rejected/stale | inline `StatusCopy` sentence; card becomes expired | Open · Dismiss |
| Snoozed | removed from section; counted in the Later row | Unsnooze |
| Expired | neutral card, clock glyph | Open · Dismiss |
| Offline | content shown, actions disabled, "Reconnect to answer" | Later only |
| Stale cache | meta line adds "as of 12m ago" | disabled until refresh |
| Grouped | one card, "3 …" count, chevron | expand; bulk actions only for low tier |

---

## 12. Runs, results and handoffs

### 12.1 User-facing vocabulary (replaces raw state labels)

| Bridge/run state | Phase 1 `RunState` | Label (row/card) | Glyph/tint |
|---|---|---|---|
| `starting` | `.queued` | "Starting" | gray dot, no pulse |
| `running` | `.running` | "Working" + current action | accent dot, pulse |
| `waiting_for_input` | `.waitingForInput` | "Needs you" | attention `questionmark.bubble.fill` |
| approval observed | `.waitingForApproval` | "Needs you on Mac" | attention `desktopcomputer` |
| steer queued | `.steeringPending` | "Working · instruction sent" | indigo `arrow.turn.down.right` |
| `stop_requested` | `.stopping` | "Stopping…" | gray `stop.circle` |
| `complete` | `.completed` | "Done" | success check |
| `failed` | `.failed` | "Failed" | failure `xmark.octagon.fill` |
| `cancelled` | `.cancelled` | "Stopped" | gray `stop.circle.fill` |
| `unknown` | **`.unknown` (new)** | "Outcome unknown" | gray `questionmark.circle` |
| phone offline while active | `displayState(isLive:false)` → `.disconnected` | "Last known: working · 12m ago" | gray `wifi.slash`, no pulse |
| routine scheduled | (routine) | "Scheduled · 7:00 AM" | gray `calendar.badge.clock` |
| delegated, unobserved | (marker) | "Not tracked from iPhone" | gray `eye.slash` |

- **No percentage progress anywhere.** Progress is the steps checklist, the step count ("6 steps") and the elapsed time.
- Cancelled work never later flips to "Done": `ActivityStore.merge` must refuse a terminal→different-terminal transition unless the bridge sequence is higher *and* the event is an explicit completion. Show a system row "Hermes reported this finished after you stopped it" if that happens.

### 12.2 RunCard (inline in a thread; replaces `LiveRunBlock`)

Collapsed (default):

```
(◐) Research Worker                                   6m
● Searching supplier catalogs
4 steps · Steps ›
```

- No panel fill while working normally. It is text with a 2 pt leading rule in the agent's identity hue at 40 % opacity: the one place hue is used outside avatars, signaling "this is the agent working".
- Tapping the card toggles an expanded inline checklist (`LiveSteps`, max 6 finished steps, then "N earlier steps").
- Controls are not on the card; they live in the pinned WorkStatusBar (§7.1), so the transcript stays calm.
- **Needs you:** the card gets the attention wash and the meta "Needs you: see below". The NeedsYouCard is pinned above the composer.
- **Queued:** "Starting…" and no steps.
- **Steering:** a step "You: \<instruction\> · Sent" in indigo.
- **Stopping:** "Stopping… Hermes finishes its current step first." No pulse.
- **Disconnected:** "Last known: \<action\> · 12m ago", a gray dot, and "Talaria will catch up when it reconnects."

### 12.3 Completion, failure, cancellation

- Completion: the RunCard collapses into the `ResultFooter` under the final message (crossfade, 0.25 s). `.success` haptic **only if this thread is on screen** at completion.
- Failure: `FailureCallout` (plain title + sentence, raw code under Details), Retry when allowed, `.error` haptic if on screen.
- Cancellation: the "Stopped by you" system row, then partial output marked partial. No haptic beyond the confirm tap. If stop is acknowledged but termination unconfirmed for more than 60 s: "Stop requested. Hermes hasn't confirmed it stopped."

### 12.4 Fan-out and handoff

- **Observed subagents** (`delegate` tool calls): one `HandoffMarker` row per batch: "Hermes started 3 subagents". Tapping it expands their tool summaries (existing tool rows).
  - A trailing note reads "**Not tracked from iPhone**" when results aren't observed.
  - If the subagent's tool call completes, its summary appears and the note disappears.
- **Kanban fan-out:** a conversation linked to Kanban tasks is currently not linkable (`task_id=null`). In Phase 1, tasks are separate work items. A task row shows "Started from: \<thread\>" only if the bridge provides the link (§18).
- **Untracked external work** (for example a run Hermes started on another client, or a cron job with no conversation): the work item shows state "Not tracked from iPhone. Check on your Mac" and never a fake spinner.
- Coherence rule: whatever fans out, the user sees **one work item row** with the most important state across its runs: needs you > failed > working > unknown > done.

### 12.5 Result presentation on Now/Threads rows

- Result snippet [client, deterministic]: the first non-heading, non-code paragraph of the final assistant markdown, stripped of markdown, up to 120 chars on Now and 160 on Threads. Never an LLM summary.
- If Hermes's result is only a file: "Created \<filename\>".

---

## 13. Offline, stale and error behavior

### 13.1 Connection states → global treatment

| State | Now status line | Threads/Agents | Thread view | Ask | Capture |
|---|---|---|---|---|---|
| Connected | normal | normal | normal | normal | syncs |
| Connecting (launch) | "Connecting to Studio…" + spinner; content from cache labeled "as of …" | cache + `ConnectionNoticeSection` | cache, controls disabled | enabled (send waits up to 5 s, then Outbox) | queued |
| Reconnecting | "Reconnecting… · as of 3m ago" | same | WorkStatusBar shows last known | enabled → Outbox | queued |
| Bridge offline | "Studio unreachable · as of 12m ago · Retry" | same | composer disabled with reason; Ask button "Save to Outbox" | Outbox | queued, "waiting for Studio" |
| Hermes offline | "Studio is up; Hermes isn't responding · Retry" | same | same | Outbox | **sync allowed** if the capture endpoint lives in the bridge and doesn't need Hermes (it shouldn't) |
| Pairing required | intervention card + "Pairing required" | same | disabled | Outbox | queued |
| Resync (`resync_required`) | "Catching up…" (no error tone) | cache | cache | normal | normal |

### 13.2 Stale data

- Every cached surface shows its age: section header trailing text "as of 12m ago" on Now; `ConnectionBanner` (existing) elsewhere.
- Ages over 24 h read "as of yesterday 6:40 PM".
- Cached run states display through `displayState(isLive:)` (existing), so nothing pulses offline.

### 13.3 Errors

- `StatusCopy` for every user-visible error (existing). Add copies for the new codes: `capture_rejected`, `capture_too_large`, `bot_conversation_unavailable`, `routing_ambiguous` (client), `voice_no_speech` (client), `voice_permission_denied` (client).
- Toast for transient action errors; inline (in card, sheet or row) for errors tied to an object. Never both.

---

## 14. Component system

All new components live in `Hermes/DesignSystem` (generic) or `Hermes/Features/<Area>` (feature-specific). Names fit the existing code.

| Component | Purpose | Hierarchy | Actions | States | Used in |
|---|---|---|---|---|---|
| `WorkItemRow` (`.live`, `.result`, `.thread` variants) | One unit of work | avatar · title · state line · metadata | tap, swipe, context menu | normal, pressed, unread, working, needs-you, mac-only, done, failed, stopped, unknown, last-known (offline), archived | Now, Threads, Agent detail |
| `NeedsYouCard` + `NeedsYouGroupCard` | Something blocked on you | meta · request · context · actions · later | choices, answer field, stop, retry, review actions, Later, open | §11.9 | Now, thread (pinned), Agent detail |
| `LaterMenu` | Snooze presets | Menu | presets | enabled, disabled-after-deadline | NeedsYouCard |
| `AgentAvatar` (= existing `ProfileAvatar` / `WithStatus`) | Identity | — | — | idle, working (pulse dot), needs-you dot, unavailable (desaturated) | everywhere |
| `AgentChip` / `RouteChip` | Where an Ask goes | avatar · name · "Auto"/"from your words" | tap → picker | auto, targeted, matched-by-name, ambiguous, read-only (in thread), disabled (offline still shows) | Accessory, AskSheet, composer |
| `AgentPicker` | Choose a target | Auto · Recent · All | select | loading (cached roster), empty (only Hermes) | Ask, reroute |
| `AskBar` (accessory) | Global entry | Capture · RouteChip · field · mic | tap, hold, chip | normal, pressed, listening (expanded), offline (field gray "Offline: saved to Outbox"), disabled (unpaired: "Pair a Mac to ask") | Tab roots |
| `AskSheet` | Compose an Ask | header (route, options) · field · media · send | send, options, attach, voice | empty, typing, sending, error, offline (Outbox), uncertain | Global |
| `VoiceOverlay` (`.ask`, `.capture`, `.thread`) | Push-to-talk | header · transcript · level · hints | lock, cancel, edit, send/save | arming, listening, locked, transcribing, review (auto-send ring for Ask), no-speech, permission-denied, network-recognition | AskBar, composer, Agent detail, Capture |
| `CaptureSheet` | Verbatim save | field · media · kind · context · footer | save | empty, editing, saving-local, queued, sent, failed | Global |
| `OutboxView` + `OutboxRow` | Local unsent items | kind glyph · preview · state · age | send now, retry, delete, check | queued, sending, confirmed (transient), failed, uncertain | Now › Outbox |
| `ComposerView` (modified) | Thread Ask | mode line · attachments · field · mic · send/stop | send, steer, answer, attach, voice (tap = dictation, hold = push-to-talk) | send, steer, clarify, busy, offline, read-only, unknown-blocked | Thread |
| `WorkStatusBar` | Pinned live controls | state · action · elapsed · controls | add instruction, stop, steps | working, needs-you, steering, stopping, last-known (controls disabled) | Thread |
| `RunCard` | Inline run evidence | agent · current step · step count | expand, steps | queued, working, needs-you, steering, stopping, disconnected | Thread |
| `ResultFooter` (extends `MessageFooter`) | Outcome of a run | outcome · agent · duration · steps · ⓘ | steps, details | done, failed (with retry), stopped, unknown | Thread |
| `StepsSheet` (from `RunDetailView`) | Event log | run switcher · Now · Timeline · Details | copy run ID, share summary | live, finished, timeline-expired ("Older events expired on Studio") | Thread, deep link |
| `ArtifactRow` (from `FileAttachmentView`) | A file Hermes made | glyph · name · size | open (Quick Look), share | normal, downloading (progress), failed | Thread, Files sheet |
| `HandoffMarker` | Agent/subagent transition | glyph · "A → B" / "started N subagents" · tracked note | expand | tracked, untracked | Thread |
| `ConnectionChip` + `StatusLine` | Am I live? | dot · host / sentence | tap → Studio, Retry | §13.1 | Now, Agents |
| `ModelPicker` + `ScopeChoice` | Change model | search · recent · providers · scope | select, apply | loading inventory, error ("Couldn't load models from Studio"), confirmation-required | Agent detail, Ask options |
| `RiskConfirmSheet` | Medium/high friction | title verb · exact effect · target · buttons | confirm, cancel | medium (tap), high (hold, optional Face ID), sending, error | Stop, model, Kanban, routines, hide |
| `HoldToConfirmButton` | Deliberate confirm | capsule fill | press-and-hold | idle, filling, released-early (drain), confirmed | RiskConfirmSheet (high) |
| `EmptyLine` | Calm success states | glyph · one sentence | — | — | Now sections, filtered scopes |
| Existing kept: `StatusDot`, `Tag`, `SectionHeader`, `FailureCallout`, `KeyValueRow`, `CommandBlock`, `TagCloud`, `LiveSteps`, `StepLine`, `RunTimeline`, `MarkdownView`, `ToolActivityView`, `LoadableContent`, `ConnectionBanner`, `ToastOverlay` (gains optional action button) | | | | | |

### 14.1 State matrix (major components)

| Component | Normal | Pressed/selected | Loading | Empty | Offline | Stale | Error | Disabled | Completed | Cancelled |
|---|---|---|---|---|---|---|---|---|---|---|
| AskBar | placeholder + chip | field highlight; hold → overlay | — | — | gray dot in field, "Offline" placeholder; still opens | — | — | unpaired: "Pair a Mac to ask", opens pairing | — | — |
| AskSheet | field + route | — | send spinner | Send disabled | "Save to Outbox" | — | inline sentence + Try Again | send disabled during dictation | dismisses → toast | swipe down keeps draft |
| VoiceOverlay | listening | locked fill | "Finishing…" | "Didn't catch that" | Ask: review → Outbox | — | permission/recognizer sentence + Settings | — | Ask: sent toast; Capture: "Saved on iPhone" | slid away → collapses |
| WorkItemRow | title + state | system highlight | redacted placeholder | n/a | last-known line, no pulse | "as of" in header | failed line | archived (secondary title) | ✓ snippet | "Stopped" |
| NeedsYouCard | tinted | button highlight | button spinner | section → EmptyLine | actions disabled + note | "as of" | stale → expired copy | Mac-only actions only | confirmed ✓ then removed | expired neutral |
| RunCard | live line | expand | "Starting…" | no steps → current action only | last-known | — | failure → FailureCallout | — | → ResultFooter | "Stopped by you" |
| WorkStatusBar | state + controls | — | — | hidden when idle | controls disabled, "Last known" | age | — | Stop disabled when `controls.stop=false` (ⓘ explains) | hides | hides |
| CaptureSheet | field | — | saving | Save disabled | saves locally, "waiting for Studio" | — | inline | — | toast "Saved to Hermes" | Discard confirm if content |
| OutboxRow | preview + state | — | "Sending…" | (view hidden) | "waiting for Studio" | age | "Not saved: …" Retry | — | removed | deleted |
| ModelPicker | list | checkmark | skeleton rows | "No models offered by Studio" | cached list, Apply disabled | — | inline retry | current model row | toast + "Changed from" | Cancel |
| Agent row | name + state | highlight | redacted | "No agents yet" (only Hermes) | last-known state words | "as of" | — | hidden/unavailable: secondary | — | — |

---

## 15. Visual design system

Keep the existing Talaria system (Desktop-derived, flat, one blue). The changes below sharpen hierarchy and make actionable things unmistakable.

### 15.1 Typography (Dynamic Type styles only; SF Pro / SF Mono)

| Role | Style | Weight | Color |
|---|---|---|---|
| Screen title | `largeTitle` (system nav) | bold (system) | primary |
| Status line | `subheadline` | medium | secondary; attention/accent fragments |
| Section header | `footnote` (existing `SectionHeader`) | semibold, uppercase, 0.4 tracking | secondary |
| Card request | `headline` | semibold | primary |
| Row title | `body` | semibold | primary (secondary when archived) |
| State line / card context | `subheadline` | regular (medium for live action) | secondary; state tint for state words |
| Metadata / timestamps | `caption` (not `caption2`) | regular, monospaced digits | **secondary** (never tertiary for information) |
| Commands/paths/IDs | `callout.monospaced()` in blocks, `footnote.monospaced()` inline | regular | primary in blocks |
| Transcript body | `body` (`MarkdownView` existing) | regular | primary |
| Voice transcript | `title3` | regular | primary |

Rule: **tertiary color is reserved for counts and decorative glyphs.** Anything you might need to read uses secondary or better. This fixes current uses of `.tertiary` timestamps (`AttentionRow`, `BotRow`).

### 15.2 Spacing rhythm

- Base unit 4. Scale: 4 · 8 · 12 · 16 · 24.
- Screen gutter 16 (system list).
- Row vertical padding 6–8 (rows land at 56–68 pt with two lines).
- Card padding 14; card-to-card 8; the card's internal gap between blocks is 10.
- Section spacing: `.compact` everywhere.
- Minimum hit target 44×44; card buttons 44 pt tall.

### 15.3 Color

| Token | Meaning | Use |
|---|---|---|
| Accent (Talaria blue `#0150F9` / dark `#5F92EE`, existing) | interactive + live work | buttons, links, send, unread dots, running dot |
| `Theme.attention` (orange) | **needs you** | Needs You cards, badge, attention state words. Never decoration. |
| `Theme.success` | confirmed done | check glyphs only (never fills) |
| `Theme.failure` | failed / destructive / deadline < 60 s | glyphs, destructive buttons |
| `Theme.steering` (indigo) | your instruction in flight | steer mode, steering steps |
| Identity hues | who | avatars, RunCard 2 pt rule, route chip avatar |
| Neutrals | everything else | system label/fill colors |

No gradients. No glass on content surfaces; glass/material only where the system supplies it (tab bar, accessory, sheets, nav bars).

### 15.4 Agent identity treatment

- The avatar is the identity. Sizes: 16 (meta lines, chips), 28 (Now rows), 36 (Threads rows), 44 (Agents list), 64 (Agent detail).
- Working agents get the existing `StatusDot` corner badge (pulsing every ~4.7 s); needs-you agents get a static orange dot.
- Names stay in text color. The identity hue appears only as the avatar tint and the RunCard rule, so a thread never feels "owned" by a color.

### 15.5 Actionable-state treatment

- Actionable = a tinted panel (Needs You) or a button. Informational = a plain row or text.
- Inside any Needs You card there is at most **one** prominent button. The others are bordered.
- Disabled actions always carry a reason nearby (footnote), never a mute gray button alone.

### 15.6 Surfaces and cards

- Only three surface kinds:
  1. Plain list rows (default for everything).
  2. **Tinted panel** (Needs You only).
  3. **Soft panel** (`.panel()` without tint): code/command blocks, the expanded RunCard checklist, and inline answer fields.
- No card-in-card. No outlined cards. Results are never boxed.

### 15.7 Icons

- SF Symbols only, `.imageScale(.small)` inside text lines.
- Fixed meaning:
  - `circle.dotted.circle` Now;
  - `bubble.left.and.text.bubble.right` Threads;
  - `person.2` Agents;
  - `tray.and.arrow.down` Capture;
  - `waveform` listening;
  - `desktopcomputer` Mac-only;
  - `arrow.turn.down.right` steering/handoff;
  - `questionmark.circle` unknown;
  - `eye.slash` not tracked.
- No sparkle/AI icons. The Talaria mark appears only in Studio › About and pairing.

### 15.8 Separators

- System list separators, inset to the text column (aligned after the avatar).
- No separators inside cards; use spacing.
- One `Divider` in the thread above a pinned Needs You card.

### 15.9 Light/dark

- All tokens are adaptive (existing `Theme.adaptive`). The attention wash is 7 % in light and 12 % in dark, so it reads on dark fills.
- Verify contrast ≥ 4.5:1 for secondary text on panel fills in both modes (Codex: add to `TalariaDesignTests`).

### 15.10 Proposed design-system modifications

1. Add `Theme.attentionWash` (adaptive opacity) and use it only via `NeedsYouCard`.
2. Promote `ToastCenter.Toast` to support one optional action ("Open"), with a 4 s display when an action is present.
3. Add `.unknown` to `RunState` with its tint/symbol/labels (§12.1).
4. Replace tertiary timestamps with secondary.
5. Rename user-facing "Bot(s)" → "Agent(s)", "Chat" → "Thread", "Run" → "Steps" (in buttons). Internal type names can stay (`Profile`, `Conversation`, `Run`) to avoid churn.

---

## 16. Motion and haptics

Restraint rules: one motion per state change, ≤ 0.35 s, springs `snappy` or `smooth`. Under Reduce Motion everything becomes a 0.2 s crossfade and the status dot stops pulsing (existing). Haptics go through `.haptic()` (respects the preference).

| Moment | Motion | Haptic |
|---|---|---|
| Ask opening (tap) | system sheet presentation; keyboard rises with it | none |
| Hold-to-talk start | accessory grows upward into the overlay (spring 0.3 s) **after** the mic is live | `.impact(weight: .medium)` at capture start |
| Lock (slide up) | lock glyph fills (`symbolEffect(.bounce)`) | `.impact(weight: .light)` |
| Cancel (slide left) | overlay slides left + fades 0.2 s | `.impact(flexibility: .soft)` |
| Review auto-send ring | 1.5 s linear stroke on the send button | none |
| Successful handoff (202) | sheet dismisses; toast drops in from top; new row inserts at the top of Working | `.selection` |
| Needs You answer confirmed | button content → checkmark (`contentTransition(.symbolEffect(.replace))`), then the card collapses after 1.2 s (height + opacity, 0.25 s) | `.success` |
| Needs You arrives while Now is visible | card inserts with move+opacity; meta line tint pulses once | `.warning` only if the app is foreground and the item is actionable (existing approval haptic) |
| Run state change | state line `contentTransition(.opacity)`; dot ↔ glyph crossfade | none |
| Completion (thread on screen) | RunCard → ResultFooter crossfade 0.25 s | `.success` |
| Completion (elsewhere) | row moves Working → Done via list animation | none |
| Failure (on screen) | FailureCallout fades in. No shake. | `.error` |
| Cancellation confirmed | "Stopped by you" row fades in | none |
| Agent switching (route chip) | avatar + name crossfade 0.2 s; width animates | `.selection` |
| Offline → connected | status line crossfade; "as of" labels disappear; dots resume pulsing | none |
| Capture queued | toast "Saved on iPhone" | `.impact(weight: .light)` |
| Capture synced | toast text replace → "Saved to Hermes" with `checkmark` symbol replace | `.success` only if the toast is still visible |
| Hold-to-confirm | capsule fill linear 1.2 s; early release drains 0.3 s | `.impact(.light)` at start; `.success` on completion |
| Deadline < 60 s | meta line turns failure color, no animation | none |

---

## 17. Accessibility and one-handed use

**One-handed:**

- Ask, Capture, the tab bar, Needs You actions and the composer are all in the bottom 40 % of the screen or reachable through it. Needs You cards are first in Now, but answering them doesn't require top-of-screen controls (their buttons are inside the card, and the card scrolls to the bottom half on demand).
- Hold gestures have tap alternatives: tapping the mic toggles dictation, then you tap Send. Long-press menus have visible equivalents (⋯ menus).
- No critical action lives only in a top toolbar. Stop is in the WorkStatusBar *and* the Now swipe *and* the RunCard context menu.

**VoiceOver:**

- `NeedsYouCard` is one container. The label reads "Needs you. Research Worker asks: Which supplier should I contact first? 3 minutes left." Actions are exposed both as buttons and as `accessibilityActions` (rotor: Grainger, Ferguson, Answer, Later).
- `WorkItemRow`: "Find replacement compressor part. Research Worker. Working: searching supplier catalogs. 6 minutes. Unread." Custom actions: Stop, Mark read, Pin, Archive.
- Push-to-talk under VoiceOver: a double-tap-and-hold gesture works natively. The mic button also offers a "Start voice ask" action that toggles listening, with an announcement "Listening" when capture actually starts and "Sent to Research Worker" on confirmation.
- Deadlines: announce at 60 s and 10 s only (`UIAccessibility.post(.announcement)`) when the card is on screen. No per-second chatter.
- The route chip's label: "Sending to Research Worker, chosen from your words. Double-tap to change."

**Dynamic Type:**

- Rows switch to stacked layouts at accessibility sizes (existing pattern in `ConversationRow`/`AttentionRow`).
- Card buttons wrap to a vertical stack at ≥ `.accessibility1`.
- The accessory grows to 2 lines max, and the placeholder truncates.

**Other:**

- Contrast: secondary text on tinted panels ≥ 4.5:1 (test).
- Color is never the only signal: every state has a word or glyph (existing rule kept).
- Reduce Motion as §16.
- **Differentiate Without Color:** the attention cards also show a leading `hand.raised.fill` glyph on the meta line.
- Bold Text and Smart Invert verified on avatars (blob images marked `accessibilityIgnoresInvertColors`).

---

## 18. Backend and data requirements exposed by the design

### 18.1 Client-only (deterministic, Phase 1)

| Item | Notes |
|---|---|
| `WorkItem` projection | `id` (conversation ID or `task:<id>`), `kind`, `title`, `agentID`, `state` (derived priority: needsYou > failed > working > unknown > done > idle), `runs`, `latestResultSnippet`, `lastActivity`, `isPinned`, `isArchived`, `isUnread`, `artifactCount`, `source`. Built in a new `WorkItemStore` from `ConversationListStore`, `ActivityStore`, `TaskStore` and `HomeStore`. Recomputed on events. |
| `NeedsYouItem` projection | Replaces `AttentionItem` in UI. `kind` (question, decision, approval, intervention(subtype), review), `workItemID`, `agentID`, `request`, `context`, `choices`, `recommendedChoice?`, `deadline?`, `canRespond`, `riskTier`, `groupKey`. Sources: `/home.attention`, `/home.failed_or_blocked`, `/home.kanban` (review), local connection issues, Outbox uncertain receipts. |
| `RunState.unknown` | Map bridge `unknown` to it (currently mapped to `.disconnected`). `.disconnected` stays purely a display state for offline. |
| Snooze store | `[needsYouID: SnoozeUntil(.date | .atDesk)]`, local per host |
| Seen store | `[workItemID: Date]`, local per host |
| Recent models / route aliases / agent model-change notes | local |
| `CaptureStore` + Outbox | local queue, App Group container (ready for extensions later) |
| Deterministic router | name/alias prefix match |
| Result snippet extraction | markdown → first paragraph |

### 18.2 Existing bridge capabilities used

`/home`, `/conversations` (list, create with model/provider/reasoning/workspace, archive via PATCH), `/conversations/{id}/runs` (send with attachment IDs), `/runs/{id}/stop|steer|retry`, `/runs/{id}/events`, `/attention` + `/attention/{id}/respond` (clarifications), `/bots`, `/bots/{id}` (PATCH model/provider with confirm), `/bots/{id}/conversation`, `/bots/inventory`, `/inventory/models`, `/cron` enable/disable/run-now, `/kanban/tasks` PATCH/reassign, `/attachments`, `/artifacts/*`, SSE `/events/stream`.

### 18.3 New bridge work (small to moderate; no Hermes changes)

| # | Capability | Why | Size |
|---|---|---|---|
| B1 | **`POST /bots/{id}/conversations`** (+ include those sessions in `GET /conversations` with `bot_id`) — create a new, non-canonical session for a native bot profile: `session.create {profile: <native>, follow_profile_config: true}`, optional `title`, optional model/provider/reasoning overrides if upstream allows them with `follow_profile_config:false` | Multiple threads per agent; Ask routing to an agent creates a work item, not a message in one long chat | **Moderate.** Upstream `session.create` already accepts `profile`. The bridge must list and resolve non-canonical sessions per bot profile, extending its existing `session.list {profile}` use. **Recommended Phase 1 prerequisite.** |
| B2 | **`POST /captures`** `{client_capture_id, created_at, kind, text, attachment_ids?, context?}` → `{capture_id, stored_at}`, plus `/captures/uploads` accepting audio `audio/mp4` | Verbatim Capture with confirmation | **Small.** It writes files under a configured `captures_root` (0700), with idempotency via the existing receipt layer, and needs no Hermes. |
| B3 | Attention `details.recommended` / `details.default` and `details.on_timeout` passthrough, when upstream clarification payloads carry them | Defaults on decisions | **Small**, if upstream provides them; otherwise nothing to pass through (UI hides it) |
| B4 | `run.unknown` distinguished in the run view (already a state). Ensure `failed_or_blocked` marks `unknown` vs `failed` explicitly | Honest intervention copy | Trivial (already present; client mapping change) |
| B5 | Kanban review transitions: confirm `supported_targets` from `review` (done/todo/ready) and accept a comment/summary in the same PATCH, or expose a comment endpoint | Review cards | Small |
| B6 | Run ↔ Kanban link (`task_id` on a chat run when Hermes created a task from that session), if observable | Fan-out coherence | Moderate; only if upstream records it. Phase 2. |

### 18.4 Upstream Hermes capabilities (flag; not Phase 1)

| # | Capability | Unlocks |
|---|---|---|
| H1 | Exact-target, compare-and-resolve approval responses | Remote Approve/Deny with risk friction (§11.4 future) |
| H2 | Per-session model/reasoning switch that doesn't write global defaults | "This thread only" model change mid-thread |
| H3 | Per-profile reasoning effort setting via `profiles.configure` | Agent-default reasoning |
| H4 | Profile "paused/accepting work" flag | Real agent pause |
| H5 | Structured pending decisions with default + deadline + timeout behavior (Charm's `pending[]`) | Decisions that keep beyond 290 s, meaningful Later |
| H6 | Cross-profile delegation events (`delegation.started/completed` with target profile + child session) | Tracked handoffs and fan-out |
| H7 | APNs relay (bridge-side) | Walk-away with notification; snooze reminders |

### 18.5 LLM-dependent behavior (never required for correctness)

- Thread titles (Hermes auto-titles). The client shows the first line of the ask until a title arrives.
- What Hermes does with an Ask, including delegation.
- Phase 2: model-suggested routing (suggests a chip change before send; never silent).
- Phase 2: TTS short-reply extraction (use the first two sentences deterministically instead).

---

## 19. Existing components to reuse (as-is or near as-is)

- `AppEnvironment`, the event loop, `AppliedBridgeState` checkpointing, `SnapshotCache`, `DraftStore`, `SavedHostStore`.
- `ConnectionStore`, `HomeStore` (as a data source), `ActivityStore` (with the unknown-state fix and the terminal-flip guard), `ConversationListStore`, `ConversationModel`, `ProfileStore`, `TaskStore`, `RoutineStore`.
- `BridgeHermesClient` + `BridgeTransport` + idempotency receipts; `MockHermesBackend` (extend fixtures, §24).
- Design system: `Theme`, `Tag`, `StatusDot`, `SectionHeader`, `.panel()`, `FailureCallout`, `StatusCopy`, `ProfileAvatar`/`ProfileAvatarWithStatus`/`IdentityColor`/`AvatarImageCache`, `KeyValueRow`, `CommandBlock`, `FlowLayout`/`TagCloud`, `ElapsedText`, `RelativeTimeText`, `ConnectionLabel`, `LoadableContent`, `OfflineContentView`, `ErrorContentView`, `LoadingRows`, `CapabilityGate`, `ToastCenter`/`ToastOverlay`, `.haptic`, `Format`.
- Chat internals: `MarkdownView`/`MarkdownParser`, `MessageView` family, `ToolActivityView`, `TranscriptItem`, `ComposerMedia`, `ComposerDictation`, `CameraCapture`, `ImageAttachmentView`, `FileAttachmentView`.
- Runs: `LiveSteps`, `StepLine`, `RunTimeline`, `SteerSheet` (restyled), `ApprovalDetailView`, `DiffView`, `RunSummarySheet`.
- Agents: `BotEditorView` (retitled), `BotInventory`.
- Tasks: `KanbanView`, `TaskDetailView`, `NewTaskSheet`, `ScheduledView`, `RoutineDetailView`, `RoutineEditView`.
- More: `HostsView`, `HostDetailView`, `HostEditorView`, `UsageView`, `SkillsView`, `ToolsView`, `MCPView`, `SettingsView` (incl. Simulation), `CapabilitiesView`.

## 20. Existing components and screens to modify

| From | To | Changes |
|---|---|---|
| `RootView` (5 tabs) | 3 tabs + `AskBar` accessory | iOS 26 `tabViewBottomAccessory` + minimize behavior; iOS 18 inset fallback; badge = actionable Needs You count |
| `AppTab`, `AppRouter` | `.now/.threads/.agents`; `nowPath/threadsPath/agentsPath`; `openThread`, `openNeedsYou`, `ask(seed)`, `capture(seed)` | Remove `startNewChat`/`showTasks`; deep-link handler |
| `HomeView` + `HomeComponents` | `NowView` | Status line, NeedsYou, Working, Done, Next Up, Outbox; drop host grid; `AttentionRow` → `NeedsYouCard` |
| `HomeStore.attentionItems` | `NeedsYouStore` (or `NeedsYouProjection` on `HomeStore`) | Typed items, grouping, snooze, review derivation |
| `ConversationListView` + `ConversationRow` | `ThreadsView` + `WorkItemRow(.thread)` | Scopes, filters, unread, archive swipe, Kanban items, bridge search section |
| `ConversationView` | `ThreadView` | `WorkStatusBar`, pinned NeedsYouCard, `RunCard`, `ResultFooter`, inline artifacts, handoff markers, title menu |
| `ComposerView` | thread Ask | Hold-to-talk on mic (tap still dictates), Capture in `+` menu, read-only route chip in mode line, unknown-blocked mode |
| `RunSettingsBar`/`RunSettingsSheet` | `AskOptions` (inside AskSheet) + Thread Options (read-only) | Remove the profile picker (route chip replaces it) |
| `LiveRunBlock` | `RunCard` | Controls move to `WorkStatusBar`; collapsed by default |
| `RunDetailView` | `StepsSheet` | Sheet presentation, run switcher, no duplicate header |
| `ApprovalCard` | `NeedsYouCard(.approval)` + `.question`/`.decision` | Mac-only design; inline answer field |
| `BotsView`/`BotRow` | `AgentsView`/`AgentRow` | No Default Profile section; state word; model-change note |
| `ProfileDetailView` | `AgentDetailView` | Ask/hold row, Now, Runtime (model+scope, reasoning info, routines), Recent work, Configuration |
| `EditProfileView` (legacy non-Bot-Mode) | keep only for legacy hosts | Not shown when `botMode` |
| `RunState` + `BridgeMapping.run` | add `.unknown`; labels per §12.1 | — |
| `ToastCenter` | optional action | — |
| `MoreView` | `StudioView` | Same rows minus unsupported ones; connection header with metrics moved from Home |
| `NotificationPolicy` | titles use agent + work item; categories unchanged | No promises of remote push |

## 21. Existing components and screens to remove (from navigation; delete code where dead)

- **Tasks tab** and `TasksView` segment shell. Running and Completed are replaced by Now/Threads. Kanban → Threads › Board; Scheduled → Now › Next Up "All" and Agent › Routines. `RunningRunsView`/`CompletedRunsView` can be deleted.
- **More tab** (→ Studio screen).
- Home **Host** section metrics grid (`HostSummaryRows` moves into Studio).
- **Run Detail as a pushed destination** (route resolves to the thread + Steps).
- **Memory / Integrations / Logs** screens and routes: unsupported by the bridge and capability-hidden. Delete `IntegrationsView`, `LogsView` and the memory entry views; keep the memory *metadata* line in Agent detail.
- `NewConversationIntro` hardcoded suggestions keyed to mock IDs (replace with nothing; the Ask field is the intro).
- The "Default Profile" section in Bots.
- Profile picker in `RunSettingsSheet`.
- Mock chart image assets (`MockChartLatency`, `MockChartTopics`) if unused after Usage.
- User-facing vocabulary "Bot", "Chat", "Run Details", "Needs Attention".

---

## 22. Phase 1 implementation boundary

**In:**

1. Three-tab IA, `AskBar` accessory (iOS 26 + 18 fallback), Studio screen.
2. `WorkItem` projection and `WorkItemStore`; `NeedsYouItem` projection; `RunState.unknown`; terminal-flip guard.
3. Now (status line, Needs You with grouping, Later and expiry, Working, Done, Next Up, Outbox).
4. Threads (scopes, filters, unread, archive, Kanban items, Board link).
5. Thread view (WorkStatusBar, RunCard, ResultFooter, StepsSheet, inline artifacts, handoff markers for delegate tools, pinned Needs You, steer/follow-up/unknown modes).
6. Agents list and detail (Ask/hold, Now, Runtime: model + scope + Revert, reasoning info, routines pause; configuration via existing editor).
7. Ask (AskSheet, deterministic routing, AgentPicker, options overrides, walk-away toast, Outbox for offline, uncertain handling).
8. Push-to-talk for Ask and thread composer (listening/locked/cancel/review/auto-send).
9. Capture (sheet, voice capture with review, media, local queue, sync via **B2**, Kanban-triage fallback if B2 isn't ready).
10. Needs You types: question, decision, Mac-only approval, interventions, review; risk tiers (direct, confirm sheet, hold).
11. Bridge **B1** (threads per agent) and **B2** (captures). B3–B5 if cheap.
12. Vocabulary pass, design-system adjustments (§15.10), accessibility (§17), tests (§24).

**Explicitly not in Phase 1:** see §23. Also not in Phase 1: Face ID (no high-risk remote action exists yet), TTS, local snooze notifications.

## 23. Phase 2+ ideas that must NOT leak into Phase 1

- APNs push, Live Activities for running work, widgets, Lock Screen/Control Center/Action Button controls, Share Extension, Siri/App Intents (keep URL routes and the App Group-ready `CaptureStore`, but no extension targets).
- Apple Watch, CarPlay.
- TTS / "Speak replies", per-agent voices.
- LLM-suggested routing.
- Remote dangerous approvals (needs H1), Face ID tier.
- Mid-thread model switch (H2), agent reasoning default (H3), agent pause (H4), structured pending decisions (H5), tracked delegation (H6).
- Routine authoring from scratch, full Kanban board redesign, memory browsing, integrations, logs.
- Link previews/unfurling for captures; on-phone summarization of anything.
- Multi-host merged views (keep the single active host).
- Any analytics/usage charts on Now.

## 24. Codex implementation notes

**Order of work** (each step builds and passes tests):

1. **Domain + stores.**
   - Add `RunState.unknown`; fix `BridgeMapping.run` (`unknown` → `.unknown`); add the terminal-flip guard in `ActivityStore.merge`.
   - Add `WorkItem`, `NeedsYouItem` (+ `NeedsYouKind`, `RiskTier`, `Snooze`), `WorkItemStore`, `NeedsYouStore`, `SeenStore`, `SnoozeStore`, `CaptureStore`/`OutboxStore`. They're pure projections with unit tests for derivation priority, grouping, unread, snooze/expiry and the router.
2. **Navigation shell.**
   - `AppTab` → 3 tabs; `AppRouter` paths and deep links; `AskBar` accessory with the availability split; `StudioView` from `MoreView`.
   - Keep `RouteDestination` as the single table and add `.thread`, `.agent`, `.board`, `.scheduled`, `.studio`.
3. **Now**: replace `HomeView` and build `NeedsYouCard` + `LaterMenu` + `RiskConfirmSheet` + `HoldToConfirmButton`.
4. **Threads + Thread view**: `WorkItemRow`, `ThreadsView`, `ThreadView` changes, `RunCard`, `WorkStatusBar`, `ResultFooter`, `StepsSheet`, `ArtifactRow`, `HandoffMarker`.
5. **Ask**: `AskSheet`, `RouteChip`, `AgentPicker`, router, `VoiceOverlay` + push-to-talk gesture (wrap the existing `ComposerDictation`; add lock/cancel tracking via `DragGesture(minimumDistance: 0)` + `LongPressGesture(minimumDuration: 0.25)` sequenced), toast action.
6. **Agents**: `AgentsView`, `AgentDetailView`, `ModelPicker` + scope + Revert note.
7. **Capture + Outbox** with the B2 client, and the Kanban fallback behind a capability check (`captures` capability from `/capabilities`).
8. **Bridge B1, B2** in `hermes-mobile-bridge` with pytest coverage mirroring the existing `test_bot_chat.py` and `test_uploads.py` patterns. Advertise `features.botThreads` and `features.captures`.
9. **Vocabulary, a11y, contrast tests, UI test updates.**

**Must-keep invariants:**

- Never show Approve/Deny unless `effectiveAvailability(...).isActionable` and the kind is not a dangerous approval on the current bridge.
- Never auto-resend after `command_uncertain`. Outbox asks never auto-send; captures auto-sync with stable idempotency keys.
- ✓/"Done"/"Saved to Hermes" only after a bridge confirmation or terminal event.
- `displayState(isLive:)` for every run display (no pulse offline).
- Cached content always wins over errors (`LoadableContent` rule).
- Haptics only through `.haptic()`.
- Voice never triggers medium or high actions and never sends a Needs You answer without a tap.

**Mock/simulation:**

- Extend `MockFixtures` with clarification questions (with and without choices, including one about to expire), a Mac-only approval, an unknown-outcome run, a Kanban task in review and one blocked, a failed routine, 3 agents including two with an ambiguous "Research" alias, delegate tool calls, and artifacts.
- Simulation controls: "Expire clarification now", "Make next send uncertain", "Fail capture sync".

**Tests to update:**

- UI tests tapping `tabBars.buttons["Chat"|"Bots"|"Tasks"]` move to `"Threads"`/`"Agents"`/`"Now"`.
- `"New Chat"` becomes the Ask accessory (`accessibilityIdentifier("ask-bar")`).
- `"Create Bot"` → `"Create Agent"`.
- Keep the `"Send"`, `"Voice input"`, `"Stop dictation"`, `"Add attachment"`, `"Send Instruction"` labels, or update the tests in the same commit.
- Add: Now empty state ("Nothing needs you"), question answered → confirmed → removed, Mac-only approval has no Approve button, offline Ask → Outbox (no auto-send), offline capture → sync on reconnect, model change + Revert, deterministic routing ("Research, …" → chip), push-to-talk cancel sends nothing.

**Accessibility identifiers to add:** `ask-bar`, `ask-route-chip`, `ask-send`, `capture-button`, `capture-save`, `needs-you-card-<id>`, `needs-you-later`, `work-status-stop`, `steps-button`, `agent-ask`, `agent-model-row`, `scope-agent-default`, `scope-next-ask`, `outbox-row-<id>`.

## 25. Remaining product decisions that genuinely block implementation

1. **Build bridge B1 (threads per agent) in Phase 1?** *Recommendation: yes.* Without it, "Ask Research …" can only continue Research's single Bot Chat, and Threads becomes one-thread-per-agent. If no: Phase 1 routes agent-targeted Asks into canonical Bot Chats and labels them so ("Continues Research Orchestrator's chat"). Only Hermes-default Asks create new threads.
2. **Where captures live on the Studio (B2)?** *Recommendation:* a dedicated `captures_root` inbox of dated Markdown files plus sidecars, which Hermes can read and a skill can triage. Alternatives: an Obsidian vault path, or Kanban triage tasks (text only). This choice decides the endpoint and what "Saved to Hermes" means.
3. **Is the default "Hermes" profile the right Auto target?** *Recommendation: yes,* with Research/Codex/Muse reached by name or picker. If you'd rather have Auto mean "last agent I used", say so; it changes the router default and the chip copy.
4. **Minimum iOS.** *Recommendation:* keep iOS 18 with the inset fallback (cheap). Raising to iOS 26 removes the fallback path and simplifies tab-accessory testing. It's your phone-only app, so either is fine, but Codex needs the answer before building the shell.

Not blocking (decided here; override if you disagree): Kanban tasks appear as Threads; voice Asks auto-send after a 1.5 s review ring (setting to require review); Later presets 1 h / Tonight 20:00 / Tomorrow 08:00 / At my desk; result snippets are deterministic first paragraphs; "Bots" is renamed "Agents" in UI only.
