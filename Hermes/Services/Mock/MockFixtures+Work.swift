import Foundation

extension MockFixtures {
    // MARK: Runs

    static func runs(_ clock: MockClock) -> [Run] {
        func event(_ kind: RunEventKind, _ title: String, at date: Date, detail: String? = nil,
                   status: StepStatus = .done, tool: ToolKind? = nil, duration: TimeInterval? = nil) -> RunEvent {
            RunEvent(timestamp: date, kind: kind, title: title, detail: detail, status: status, toolKind: tool, duration: duration)
        }

        let benchStart = clock.ago(seconds: 222)
        let iosStart = clock.ago(minutes: 12)
        let notesStart = clock.ago(minutes: 24.8)
        let arxivStart = clock.ago(minutes: 6)

        return [
            Run(id: "r-bench", title: "Analyzing provider benchmark", profileID: MockID.researcher, conversationID: "c-researcher",
                taskID: "t-bench", routineID: nil, hostID: MockID.studio, trigger: .chat, state: .running,
                startedAt: benchStart, endedAt: nil, currentAction: "Running Python analysis",
                events: [
                    event(.started, "Run started", at: benchStart),
                    event(.modelSelected, "Claude Opus 5.5 · reasoning medium", at: benchStart.addingTimeInterval(1)),
                    event(.tool, "Read AGENTS.md", at: benchStart.addingTimeInterval(4), detail: "AGENTS.md", tool: .files, duration: 0.3),
                    event(.tool, "Searched repository", at: benchStart.addingTimeInterval(9), detail: "p95|ttft — 14 matches in 5 files", tool: .files, duration: 1.2),
                    event(.tool, "Opened benchmark results", at: benchStart.addingTimeInterval(16), detail: "results/2026-09-30.csv", tool: .files, duration: 0.4),
                    event(.tool, "Running analysis.py", at: benchStart.addingTimeInterval(31), detail: "uv run analysis.py --group-by hour --correlate prompt_tokens", status: .active, tool: .code),
                    event(.planned, "Preparing response", at: benchStart.addingTimeInterval(31), status: .pending),
                ],
                model: MockModels.opus, reasoning: .medium, project: MockProjects.providerBench,
                usage: TokenUsage(input: 38_210, output: 1_204, cached: 22_000, reasoning: 3_880)),

            Run(id: "r-ios", title: "Updating Talaria repo", profileID: MockID.caddy, conversationID: "c-caddy",
                taskID: "t-ios", routineID: nil, hostID: MockID.studio, trigger: .chat, state: .waitingForApproval,
                startedAt: iosStart, endedAt: nil, currentAction: "Waiting for approval",
                events: [
                    event(.started, "Run started", at: iosStart),
                    event(.modelSelected, "Claude Sonnet 5 · reasoning low", at: iosStart.addingTimeInterval(1)),
                    event(.tool, "Ran git pull --rebase", at: iosStart.addingTimeInterval(6), detail: "12 files changed, 348 insertions(+), 97 deletions(-)", tool: .terminal, duration: 3.1),
                    event(.tool, "Read 3 files", at: iosStart.addingTimeInterval(14), detail: "openapi.yaml, Package.swift, Makefile", tool: .files, duration: 0.6),
                    event(.tool, "Ran make generate", at: iosStart.addingTimeInterval(40), detail: "Generated 41 files in Sources/HermesAPI", tool: .terminal, duration: 18.4),
                    event(.approvalRequested, "Approve rm generated-cache.json", at: iosStart.addingTimeInterval(62), status: .active),
                    event(.planned, "Rebuild with swift build", at: iosStart.addingTimeInterval(62), status: .pending),
                    event(.planned, "Summarize changes", at: iosStart.addingTimeInterval(62), status: .pending),
                ],
                model: MockModels.sonnet, reasoning: .low, project: MockProjects.hermesIOS,
                usage: TokenUsage(input: 61_400, output: 2_310, cached: 48_000), pendingApprovalID: "a-rm"),

            Run(id: "r-notes", title: "Consolidating weekly notes", profileID: MockID.dex, conversationID: "c-dex",
                taskID: nil, routineID: nil, hostID: MockID.studio, trigger: .chat, state: .waitingForApproval,
                startedAt: notesStart, endedAt: nil, currentAction: "Waiting for approval",
                events: [
                    event(.started, "Run started", at: notesStart),
                    event(.modelSelected, "Hermes 4 70B", at: notesStart.addingTimeInterval(1)),
                    event(.tool, "Found 9 meeting notes", at: notesStart.addingTimeInterval(5), tool: .files, duration: 0.8),
                    event(.tool, "Read 9 files", at: notesStart.addingTimeInterval(12), tool: .files, duration: 1.9),
                    event(.tool, "Created Weekly/2026-W40.md", at: notesStart.addingTimeInterval(48), tool: .files, duration: 0.2),
                    event(.approvalRequested, "Approve changes to Index.md", at: notesStart.addingTimeInterval(55), status: .active),
                    event(.planned, "Archive meeting links", at: notesStart.addingTimeInterval(55), status: .pending),
                ],
                model: MockModels.hermes70, reasoning: .off, project: MockProjects.notes,
                usage: TokenUsage(input: 24_900, output: 3_120), pendingApprovalID: "a-index"),

            Run(id: "r-arxiv", title: "Triaging new arXiv submissions", profileID: MockID.analyst, conversationID: "c-analyst",
                taskID: "t-arxiv", routineID: nil, hostID: MockID.studio, trigger: .chat, state: .running,
                startedAt: arxivStart, endedAt: nil, currentAction: "Reading abstracts (14 of 38)",
                events: [
                    event(.started, "Run started", at: arxivStart),
                    event(.modelSelected, "GPT-5.1 · reasoning high", at: arxivStart.addingTimeInterval(1)),
                    event(.tool, "Searched arXiv (cs.CL, cs.LG)", at: arxivStart.addingTimeInterval(8), tool: .web, duration: 2.2),
                    event(.tool, "Fetched 38 submissions", at: arxivStart.addingTimeInterval(30), tool: .web, duration: 19),
                    event(.tool, "Reading abstracts (14 of 38)", at: arxivStart.addingTimeInterval(52), status: .active, tool: .browser),
                    event(.planned, "Flag KV-compression papers", at: arxivStart.addingTimeInterval(52), status: .pending),
                    event(.planned, "Preparing response", at: arxivStart.addingTimeInterval(52), status: .pending),
                ],
                model: MockModels.gpt, reasoning: .high, project: nil,
                usage: TokenUsage(input: 92_000, output: 1_800, reasoning: 12_400)),

            finished("r-cleanup", "Clean up stale build scripts", profile: MockID.caddy, conversation: "c-cleanup", task: "t-cleanup",
                     start: clock.ago(minutes: 56), end: clock.ago(minutes: 48), state: .completed, model: MockModels.sonnet,
                     retrySupported: true,
                     project: MockProjects.docs, usage: TokenUsage(input: 44_200, output: 2_950, cached: 30_100),
                     summary: "Removed 4 unreferenced scripts; build passes.", tools: [
                        ("Searched 214 files", .files), ("Ran git rm on 4 files", .terminal), ("Edited package.json", .files), ("Ran npm run build", .terminal),
                     ]),
            finished("r-triage", "Inbox triage", profile: MockID.dex, conversation: nil, routine: "rt-triage",
                     start: clock.ago(minutes: 64), end: clock.ago(minutes: 62), state: .completed, model: MockModels.hermes70,
                     usage: TokenUsage(input: 8_100, output: 640), summary: "12 new emails, 1 needs a reply today.", trigger: .routine,
                     tools: [("Checked inbox", .mcp), ("Sent to Telegram · Home", .messaging)]),
            finished("r-alerts", "Server alerts digest", profile: MockID.dex, conversation: "c-telegram",
                     start: clock.ago(hours: 2.05), end: clock.ago(hours: 2), state: .completed, model: MockModels.hermes70,
                     usage: TokenUsage(input: 15_300, output: 820), summary: "demo-worker offline since 03:12; gateway restarted twice.", trigger: .external,
                     tools: [("Ran journalctl on demo-worker", .terminal), ("Read hermes-gateway logs", .terminal)]),
            finished("r-morning", "Morning report", profile: MockID.dex, conversation: "c-morning", routine: "rt-morning",
                     start: clock.ago(hours: 3.3), end: clock.ago(hours: 3.2), state: .completed, model: MockModels.hermes70,
                     usage: TokenUsage(input: 11_800, output: 410), summary: "3 events, 2 PRs waiting on review.", trigger: .routine,
                     tools: [("Checked weather", .web), ("Listed open pull requests", .mcp), ("Sent to Telegram · Home", .messaging)]),
            finished("r-nightly", "Nightly research sweep", profile: MockID.researcher, conversation: "c-nightly", routine: "rt-nightly",
                     start: clock.ago(hours: 9), end: clock.ago(hours: 8.93), state: .failed, model: MockModels.opus,
                     usage: TokenUsage(input: 21_000, output: 300),
                     failure: "OpenRouter returned 429 Too Many Requests after 3 retries.", trigger: .routine,
                     tools: [("Searched 6 sources", .web), ("Fetch failed", .web)]),
            finished("r-bench-1", "Run provider latency benchmark", profile: MockID.researcher, conversation: "c-researcher", task: "t-bench",
                     start: clock.ago(days: 1, hours: 0.4), end: clock.ago(days: 1, hours: 0.3), state: .completed, model: MockModels.opus,
                     project: MockProjects.providerBench, usage: TokenUsage(input: 52_000, output: 2_100, reasoning: 4_200),
                     summary: "Local wins TTFT; Nous Portal best p95 of the hosted providers.",
                     tools: [("Read bench.py", .files), ("Ran uv run bench.py", .terminal)]),
            finished("r-papers", "This week in agent research", profile: nil, conversation: "c-papers",
                     start: clock.ago(days: 1.1), end: clock.ago(days: 1.08), state: .completed, model: MockModels.sonnet,
                     usage: TokenUsage(input: 33_000, output: 1_500), summary: "Five papers summarized.",
                     tools: [("Searched arXiv and Semantic Scholar", .web), ("Visited 2 pages", .browser)]),
            finished("r-deploy", "Deploy docs site to Fly.io", profile: MockID.caddy, conversation: nil, task: "t-deploy",
                     start: clock.ago(days: 1, hours: 3), end: clock.ago(days: 1, hours: 2.9), state: .cancelled, model: MockModels.sonnet,
                     project: MockProjects.docs, usage: TokenUsage(input: 9_000, output: 200),
                     failure: "Stopped by you.", tools: [("Ran fly deploy", .terminal)]),
            finished("r-embed", "Compare embedding models", profile: MockID.researcher, conversation: nil, task: "t-embed",
                     start: clock.ago(days: 1, hours: 6), end: clock.ago(days: 1, hours: 5.4), state: .completed, model: MockModels.opus,
                     usage: TokenUsage(input: 71_000, output: 4_400), summary: "bge-m3 best recall@10; nomic-embed fastest.",
                     tools: [("Ran eval_embeddings.py", .code), ("Wrote report.md", .files)]),
            finished("r-kv", "Explain KV cache quantization", profile: nil, conversation: "c-kv",
                     start: clock.ago(days: 2.2), end: clock.ago(days: 2.1), state: .completed, model: MockModels.local,
                     usage: TokenUsage(input: 1_900, output: 610), summary: "Explained with table and example.", tools: []),
            finished("r-eval", "Evaluate Hermes 4 tool calling", profile: MockID.researcher, conversation: nil, task: "t-eval",
                     start: clock.ago(days: 2, hours: 4), end: clock.ago(days: 2, hours: 3.7), state: .failed, model: MockModels.hermes405,
                     usage: TokenUsage(input: 12_000, output: 90),
                     failure: "hermes_execution_error", tools: [("Ran eval_tools.py", .code)]),
            finished("r-gateway", "Fix flaky gateway reconnect", profile: MockID.caddy, conversation: "c-caddy", task: "t-gateway",
                     start: clock.ago(days: 3, hours: 1), end: clock.ago(days: 3, hours: 0.5), state: .completed, model: MockModels.sonnet,
                     project: MockProjects.hermesIOS, usage: TokenUsage(input: 88_000, output: 6_100, cached: 60_000),
                     summary: "Exponential backoff + stale socket cleanup.",
                     tools: [("Read gateway/session.py", .files), ("Edited 2 files", .files), ("Ran pytest", .terminal)]),
            finished("r-hygiene", "Weekly repo hygiene", profile: MockID.caddy, conversation: nil, routine: "rt-hygiene",
                     start: clock.ago(days: 5), end: clock.ago(days: 4.98), state: .completed, model: MockModels.sonnet,
                     usage: TokenUsage(input: 19_000, output: 900), summary: "Pruned 6 merged branches across 3 repos.", trigger: .routine,
                     tools: [("Ran git branch --merged", .terminal)]),
        ]
    }

    private static func finished(_ id: String, _ title: String, profile: String?, conversation: String?, task: String? = nil,
                                 routine: String? = nil, start: Date, end: Date, state: RunState, model: ModelRef,
                                 retrySupported: Bool? = nil,
                                 project: ProjectContext? = nil, usage: TokenUsage, summary: String? = nil,
                                 failure: String? = nil, trigger: RunTrigger = .chat,
                                 tools: [(String, ToolKind)]) -> Run {
        var events = [RunEvent(timestamp: start, kind: .started, title: "Run started"),
                      RunEvent(timestamp: start.addingTimeInterval(1), kind: .modelSelected, title: model.displayName)]
        let span = end.timeIntervalSince(start)
        for (index, tool) in tools.enumerated() {
            let offset = span * Double(index + 1) / Double(tools.count + 1)
            let failed = state == .failed && index == tools.count - 1
            events.append(RunEvent(timestamp: start.addingTimeInterval(offset), kind: .tool, title: tool.0,
                                   status: failed ? .failed : .done, toolKind: tool.1))
        }
        switch state {
        case .completed: events.append(RunEvent(timestamp: end, kind: .completed, title: "Completed"))
        case .failed: events.append(RunEvent(timestamp: end, kind: .failed, title: "Failed", detail: failure, status: .failed))
        case .cancelled: events.append(RunEvent(timestamp: end, kind: .cancelled, title: "Stopped", detail: failure))
        default: break
        }
        return Run(id: id, title: title, profileID: profile, conversationID: conversation, taskID: task, routineID: routine,
                   hostID: MockID.studio, trigger: routine != nil ? .routine : trigger, state: state,
                   startedAt: start, endedAt: end, currentAction: nil, events: events, model: model,
                   reasoning: .medium, project: project, usage: usage, pendingApprovalID: nil,
                   failureReason: failure, resultSummary: summary, retrySupported: retrySupported)
    }

    // MARK: Approvals

    static func approvals(_ clock: MockClock) -> [ApprovalRequest] {
        [
            ApprovalRequest(id: "a-rm", runID: "r-ios", conversationID: "c-caddy", profileID: MockID.caddy, kind: .command,
                            summary: "Delete the stale generated cache before rebuilding",
                            command: "rm generated-cache.json", workingDirectory: "demo/talaria",
                            paths: ["generated-cache.json"], diff: nil,
                            reason: "Matches a dangerous-command pattern: file deletion (rm).",
                            risk: .moderate, requestedAt: clock.ago(minutes: 11), expiresAt: nil,
                            availability: .actionable, allowsSessionApproval: true, onTimeout: "Hermes will block this command.", approvalChoices: ["once", "session", "deny"]),
            ApprovalRequest(id: "a-index", runID: "r-notes", conversationID: "c-dex", profileID: MockID.dex, kind: .fileWrite,
                            summary: "Link the new weekly note and archive three meeting links",
                            command: nil, workingDirectory: "demo/notes", paths: ["Index.md"],
                            diff: """
                            --- a/Index.md
                            +++ b/Index.md
                            @@ -3,6 +3,7 @@
                             ## Weekly
                            +- [[Weekly/2026-W40]] — Sep 29 – Oct 3
                             - [[Weekly/2026-W39]] — Sep 22 – 26
                             - [[Weekly/2026-W38]] — Sep 15 – 19

                            @@ -14,9 +15,6 @@
                             ## Meetings
                            -- [[Meetings/2026-09-29 Infra sync]]
                            -- [[Meetings/2026-09-30 Hermes roadmap]]
                            -- [[Meetings/2026-10-01 Bench review]]
                            +- This week's meetings: see [[Weekly/2026-W40]]
                            """,
                            reason: "Edits a file outside the run's working set.",
                            risk: .low, requestedAt: clock.ago(minutes: 24), expiresAt: nil,
                            availability: .unavailableRemotely("Dex is running in a terminal session on the Studio. The bridge can't target this prompt, so approve it there."),
                            allowsSessionApproval: false),
        ]
    }

    // MARK: Tasks

    static func tasks(_ clock: MockClock) -> [HermesTask] {
        func activity(_ text: String, _ date: Date, profile: String? = nil, symbol: String = "circle.fill") -> TaskActivity {
            TaskActivity(id: UUID().uuidString, date: date, text: text, profileID: profile, symbol: symbol)
        }
        return [
            HermesTask(id: "t-bench", title: "Benchmark provider latency", summary: "Measure TTFT and throughput for OpenRouter, Nous Portal and local LM Studio. Explain the p95 tail.",
                       status: .inProgress, assigneeProfileID: MockID.researcher, priority: .high, hostID: MockID.studio,
                       project: MockProjects.providerBench, createdAt: clock.ago(days: 2), updatedAt: clock.ago(minutes: 4),
                       startedAt: clock.ago(days: 1, hours: 0.4), completedAt: nil, dependencyIDs: [], blockReason: nil,
                       runIDs: ["r-bench-1", "r-bench"], conversationID: "c-researcher", activity: [
                        activity("Created from conversation", clock.ago(days: 2), symbol: "plus.circle"),
                        activity("First benchmark pass complete", clock.ago(days: 1, hours: 0.3), profile: MockID.researcher, symbol: "checkmark.circle"),
                        activity("Analyzing p95 tail by hour", clock.ago(minutes: 4), profile: MockID.researcher, symbol: "circle.dotted"),
                       ]),
            HermesTask(id: "t-ios", title: "Update Talaria API client", summary: "Regenerate the client from the new OpenAPI schema and rebuild.",
                       status: .inProgress, assigneeProfileID: MockID.caddy, priority: .normal, hostID: MockID.studio,
                       project: MockProjects.hermesIOS, createdAt: clock.ago(minutes: 13), updatedAt: clock.ago(minutes: 11),
                       startedAt: clock.ago(minutes: 12), completedAt: nil, dependencyIDs: [], blockReason: nil,
                       runIDs: ["r-ios"], conversationID: "c-caddy", activity: [
                        activity("Regenerated 41 files", clock.ago(minutes: 11.2), profile: MockID.caddy, symbol: "doc.badge.gearshape"),
                        activity("Waiting for approval: rm generated-cache.json", clock.ago(minutes: 11), profile: MockID.caddy, symbol: "hand.raised"),
                       ]),
            HermesTask(id: "t-arxiv", title: "Triage new arXiv submissions", summary: "Score today's cs.CL and cs.LG submissions with the triage rubric; flag KV-compression work.",
                       status: .inProgress, assigneeProfileID: MockID.analyst, priority: .normal, hostID: MockID.studio,
                       project: nil, createdAt: clock.ago(minutes: 6.5), updatedAt: clock.ago(minutes: 1),
                       startedAt: clock.ago(minutes: 6), completedAt: nil, dependencyIDs: [], blockReason: nil,
                       runIDs: ["r-arxiv"], conversationID: "c-analyst", activity: [
                        activity("Fetched 38 submissions", clock.ago(minutes: 5.5), profile: MockID.analyst, symbol: "arrow.down.circle"),
                       ]),
            HermesTask(id: "t-deploy", title: "Deploy docs site to Fly.io", summary: "Ship the cleaned-up docs build to production.",
                       status: .blocked, assigneeProfileID: MockID.caddy, priority: .high, hostID: MockID.studio,
                       project: MockProjects.docs, createdAt: clock.ago(days: 2), updatedAt: clock.ago(minutes: 47),
                       startedAt: clock.ago(days: 1, hours: 3), completedAt: nil, dependencyIDs: ["t-cleanup"],
                       blockReason: "FLY_API_TOKEN is missing on the Studio. Add it to ~/.hermes/.env and unblock.",
                       runIDs: ["r-deploy"], conversationID: nil, activity: [
                        activity("Deploy stopped by you", clock.ago(days: 1, hours: 2.9), symbol: "stop.circle"),
                        activity("Dependency completed: Remove stale build scripts", clock.ago(minutes: 48), profile: MockID.caddy, symbol: "checkmark.circle"),
                        activity("Blocked: missing FLY_API_TOKEN", clock.ago(minutes: 47), profile: MockID.caddy, symbol: "exclamationmark.octagon"),
                       ]),
            HermesTask(id: "t-specdec", title: "Prototype early-exit speculative decoding", summary: "Add a --draft early-exit mode to bench.py and report acceptance rate next to TTFT.",
                       status: .ready, assigneeProfileID: MockID.caddy, priority: .normal, hostID: MockID.studio,
                       project: MockProjects.providerBench, createdAt: clock.ago(days: 1, hours: 1.4), updatedAt: clock.ago(days: 1, hours: 1.4),
                       startedAt: nil, completedAt: nil, dependencyIDs: ["t-bench"], blockReason: nil,
                       runIDs: [], conversationID: "c-researcher", activity: [
                        activity("Created from Researcher conversation", clock.ago(days: 1, hours: 1.4), symbol: "plus.circle"),
                       ]),
            HermesTask(id: "t-survey", title: "Survey on-device speculative decoding", summary: "Collect methods that work at batch size 1 on Apple silicon; summarize trade-offs.",
                       status: .ready, assigneeProfileID: MockID.researcher, priority: .normal, hostID: MockID.studio,
                       project: nil, createdAt: clock.ago(days: 1), updatedAt: clock.ago(days: 1),
                       startedAt: nil, completedAt: nil, dependencyIDs: [], blockReason: nil, runIDs: [], conversationID: nil,
                       activity: [activity("Created", clock.ago(days: 1), symbol: "plus.circle")]),
            HermesTask(id: "t-digest", title: "Draft weekly AI digest", summary: "Turn this week's triaged papers into the Friday digest.",
                       status: .ready, assigneeProfileID: MockID.analyst, priority: .low, hostID: MockID.studio,
                       project: nil, createdAt: clock.ago(days: 3), updatedAt: clock.ago(days: 3),
                       startedAt: nil, completedAt: nil, dependencyIDs: ["t-arxiv"], blockReason: nil, runIDs: [], conversationID: nil,
                       activity: [activity("Created by routine", clock.ago(days: 3), symbol: "calendar.badge.plus")]),
            HermesTask(id: "t-cron", title: "Migrate cron jobs to demo-worker", summary: "Move low-priority routines off the Studio once demo-worker is stable.",
                       status: .ready, assigneeProfileID: MockID.dex, priority: .low, hostID: MockID.studio,
                       project: nil, createdAt: clock.ago(days: 5), updatedAt: clock.ago(days: 5),
                       startedAt: nil, completedAt: nil, dependencyIDs: [], blockReason: nil, runIDs: [], conversationID: nil,
                       activity: [activity("Created", clock.ago(days: 5), symbol: "plus.circle")]),
            HermesTask(id: "t-cleanup", title: "Remove stale build scripts", summary: "Delete scripts with no references and keep the build green.",
                       status: .completed, assigneeProfileID: MockID.caddy, priority: .normal, hostID: MockID.studio,
                       project: MockProjects.docs, createdAt: clock.ago(hours: 1), updatedAt: clock.ago(minutes: 48),
                       startedAt: clock.ago(minutes: 56), completedAt: clock.ago(minutes: 48), dependencyIDs: [], blockReason: nil,
                       runIDs: ["r-cleanup"], conversationID: "c-cleanup", activity: [
                        activity("Removed 4 scripts; build passes", clock.ago(minutes: 48), profile: MockID.caddy, symbol: "checkmark.circle"),
                       ]),
            HermesTask(id: "t-embed", title: "Compare embedding models", summary: "Recall@10 and latency for bge-m3, nomic-embed and e5-large on the notes corpus.",
                       status: .completed, assigneeProfileID: MockID.researcher, priority: .normal, hostID: MockID.studio,
                       project: nil, createdAt: clock.ago(days: 2), updatedAt: clock.ago(days: 1, hours: 5.4),
                       startedAt: clock.ago(days: 1, hours: 6), completedAt: clock.ago(days: 1, hours: 5.4), dependencyIDs: [], blockReason: nil,
                       runIDs: ["r-embed"], conversationID: nil, activity: [
                        activity("Report written", clock.ago(days: 1, hours: 5.4), profile: MockID.researcher, symbol: "doc.text"),
                       ]),
            HermesTask(id: "t-gateway", title: "Fix flaky gateway reconnect", summary: "Duplicate deliveries after the gateway resumes.",
                       status: .completed, assigneeProfileID: MockID.caddy, priority: .high, hostID: MockID.studio,
                       project: MockProjects.hermesIOS, createdAt: clock.ago(days: 4), updatedAt: clock.ago(days: 3, hours: 0.5),
                       startedAt: clock.ago(days: 3, hours: 1), completedAt: clock.ago(days: 3, hours: 0.5), dependencyIDs: [], blockReason: nil,
                       runIDs: ["r-gateway"], conversationID: "c-caddy", activity: [
                        activity("Fixed and tested", clock.ago(days: 3, hours: 0.5), profile: MockID.caddy, symbol: "checkmark.circle"),
                       ]),
            HermesTask(id: "t-eval", title: "Evaluate Hermes 4 tool calling", summary: "Run the tool-use eval suite against Hermes 4 405B locally.",
                       status: .failed, assigneeProfileID: MockID.researcher, priority: .normal, hostID: MockID.studio,
                       project: nil, createdAt: clock.ago(days: 3), updatedAt: clock.ago(days: 2, hours: 3.7),
                       startedAt: clock.ago(days: 2, hours: 4), completedAt: clock.ago(days: 2, hours: 3.7), dependencyIDs: [],
                       blockReason: "MLX ran out of memory loading the 405B weights.",
                       runIDs: ["r-eval"], conversationID: nil, activity: [
                        activity("Failed: out of memory", clock.ago(days: 2, hours: 3.7), profile: MockID.researcher, symbol: "xmark.octagon"),
                       ]),
            HermesTask(id: "t-landing", title: "Rewrite docs landing page", summary: "Superseded by the new marketing site.",
                       status: .cancelled, assigneeProfileID: MockID.caddy, priority: .low, hostID: MockID.studio,
                       project: MockProjects.docs, createdAt: clock.ago(days: 9), updatedAt: clock.ago(days: 6),
                       startedAt: nil, completedAt: clock.ago(days: 6), dependencyIDs: [], blockReason: nil,
                       runIDs: [], conversationID: nil, activity: [activity("Cancelled", clock.ago(days: 6), symbol: "minus.circle")]),
        ]
    }

    // MARK: Routines

    static func routines(_ clock: MockClock) -> [Routine] {
        let hour = Calendar.current.component(.hour, from: clock.now)
        let nextTriageHour = (9...18).first { $0 > hour && ($0 - 9) % 2 == 0 } ?? 9
        return [
            Routine(id: "rt-triage", name: "Inbox triage",
                    prompt: "Check the inbox for anything new. Summarize what needs a reply today and send it to Telegram.",
                    schedule: RoutineSchedule(expression: "0 9-18/2 * * *", summary: "Every 2 hours, 9 AM – 6 PM"),
                    nextRunAt: clock.next(hour: nextTriageHour), profileID: MockID.dex, isEnabled: true,
                    lastResult: RoutineResult(outcome: .succeeded, date: clock.ago(minutes: 62), runID: "r-triage", summary: "12 new emails, 1 needs a reply today."),
                    delivery: "Telegram · Home", hostID: MockID.studio, skillIDs: ["sk-plan"]),
            Routine(id: "rt-nightly", name: "Nightly research sweep",
                    prompt: "Sweep arXiv, Hacker News and the provider changelogs for anything relevant to agent tooling. Summarize the top five with links.",
                    schedule: RoutineSchedule(expression: "0 2 * * *", summary: "Every day at 2:00 AM"),
                    nextRunAt: clock.next(hour: 2), profileID: MockID.researcher, isEnabled: true,
                    lastResult: RoutineResult(outcome: .failed, date: clock.ago(hours: 8.93), runID: "r-nightly", summary: "429 Too Many Requests from OpenRouter."),
                    delivery: "Telegram · Research", hostID: MockID.studio, skillIDs: ["sk-arxiv"]),
            Routine(id: "rt-morning", name: "Morning report",
                    prompt: "Calendar for today, PRs waiting on my review, and the weather. Three short bullets.",
                    schedule: RoutineSchedule(expression: "0 7 * * 1-5", summary: "Weekdays at 7:00 AM"),
                    nextRunAt: clock.next(hour: 7, weekdays: [2, 3, 4, 5, 6]), profileID: MockID.dex, isEnabled: true,
                    lastResult: RoutineResult(outcome: .succeeded, date: clock.ago(hours: 3.2), runID: "r-morning", summary: "3 events, 2 PRs waiting on review."),
                    delivery: "Telegram · Home", hostID: MockID.studio, skillIDs: ["sk-morning"]),
            Routine(id: "rt-hygiene", name: "Weekly repo hygiene",
                    prompt: "Prune merged branches and stale worktrees across my repos. Report what you removed; never delete unmerged work.",
                    schedule: RoutineSchedule(expression: "0 18 * * 0", summary: "Sundays at 6:00 PM"),
                    nextRunAt: clock.next(hour: 18, weekdays: [1]), profileID: MockID.caddy, isEnabled: false,
                    lastResult: RoutineResult(outcome: .succeeded, date: clock.ago(days: 4.98), runID: "r-hygiene", summary: "Pruned 6 merged branches."),
                    delivery: nil, hostID: MockID.studio, skillIDs: ["sk-github-pr"]),
        ]
    }
}
