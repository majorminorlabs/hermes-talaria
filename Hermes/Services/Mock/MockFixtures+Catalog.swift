import Foundation

extension MockFixtures {
    // MARK: Memory

    static func memory(_ clock: MockClock) -> [MemoryEntry] {
        func entry(_ id: String, _ content: String, _ scope: MemoryScope, profile: String? = nil, source: MemorySource,
                   title: String? = nil, conversation: String? = nil, _ date: Date, tags: [String] = []) -> MemoryEntry {
            MemoryEntry(id: id, content: content, scope: scope, profileID: profile, source: source, sourceTitle: title,
                        conversationID: conversation, createdAt: date, updatedAt: date, tags: tags)
        }
        return [
            entry("mem-1", "provider-bench runs with uv. Use `uv run bench.py`, never the system Python.", .agent, profile: MockID.researcher,
                  source: .conversation, title: "Researcher", conversation: "c-researcher", clock.ago(minutes: 30), tags: ["provider-bench", "tooling"]),
            entry("mem-2", "OpenRouter rate-limits heavily between 01:00 and 03:00. Stagger nightly sweep requests or prefer Nous Portal at night.", .agent, profile: MockID.researcher,
                  source: .routine, title: "Nightly research sweep", conversation: "c-nightly", clock.ago(hours: 8.9), tags: ["providers"]),
            entry("mem-3", "Prefers concise answers. Use tables for comparisons and lead with the conclusion.", .user,
                  source: .conversation, title: "This week in agent research", conversation: "c-papers", clock.ago(days: 12), tags: ["style"]),
            entry("mem-4", "hermes-ios: run `make generate` after pulling schema changes; the generated cache must be cleared before rebuilding.", .agent, profile: MockID.caddy,
                  source: .conversation, title: "Caddy", conversation: "c-caddy", clock.ago(minutes: 11), tags: ["hermes-ios"]),
            entry("mem-5", "Never push or deploy without explicit confirmation, even when a task says \"ship it\".", .user,
                  source: .manual, clock.ago(days: 30), tags: ["safety"]),
            entry("mem-6", "Primary machine is the Mac Studio. demo-worker is a Linux box used for low-priority jobs; it drops off Tailscale occasionally.", .user,
                  source: .conversation, title: "Server alerts digest", conversation: "c-telegram", clock.ago(days: 20), tags: ["hosts"]),
            entry("mem-7", "Notes vault is at demo/notes (Obsidian). Weekly notes go in Weekly/YYYY-Www.md and are linked from Index.md.", .agent, profile: MockID.dex,
                  source: .conversation, title: "Dex", conversation: "c-dex", clock.ago(days: 2), tags: ["notes"]),
            entry("mem-8", "Morning report: three bullets — calendar, reviews, weather. Send to Telegram · Home before 7:15.", .agent, profile: MockID.dex,
                  source: .skill, title: "morning-report", clock.ago(days: 14), tags: ["routine"]),
            entry("mem-9", "Deploying hermes-docs needs FLY_API_TOKEN in ~/.hermes/.env.", .agent, profile: MockID.caddy,
                  source: .conversation, title: "Deploy docs site", clock.ago(minutes: 47), tags: ["hermes-docs", "deploy"]),
            entry("mem-10", "Paper triage rubric: reproducibility 0.4, novelty 0.3, relevance 0.3.", .agent, profile: MockID.analyst,
                  source: .conversation, title: "Analyst", conversation: "c-analyst", clock.ago(days: 4), tags: ["research"]),
            entry("mem-11", "Usually reviews results in the evening; prefers summaries ready by 8 AM.", .user,
                  source: .conversation, title: "Morning report", clock.ago(days: 25), tags: ["schedule"]),
            entry("mem-12", "Time Machine backups of the Studio run nightly around 03:00 and take ~40 minutes.", .agent, profile: MockID.caddy,
                  source: .conversation, title: "Caddy", conversation: "c-caddy", clock.ago(days: 3), tags: ["studio"]),
        ]
    }

    // MARK: Skills

    static func skills(_ clock: MockClock) -> [Skill] {
        [
            Skill(id: "sk-github-pr", name: "github-pr-workflow", summary: "Branch, commit, open and update pull requests with a consistent checklist.",
                  category: "Software development", isEnabled: true, version: "1.4.0", origin: .bundled, usageCount: 86, lastUsedAt: clock.ago(minutes: 48),
                  instructionsPreview: "1. Create a branch named after the task.\n2. Keep commits small and descriptive.\n3. Run the test suite before opening the PR.\n4. Never force-push shared branches.",
                  requiredToolsets: ["terminal", "file"]),
            Skill(id: "sk-debugging", name: "systematic-debugging", summary: "Reproduce, isolate, hypothesize, verify — before changing code.",
                  category: "Software development", isEnabled: true, version: "1.1.0", origin: .bundled, usageCount: 31, lastUsedAt: clock.ago(days: 3),
                  instructionsPreview: "Always reproduce the failure first. Write down the hypothesis before editing code. Verify the fix against the original reproduction.",
                  requiredToolsets: ["terminal"]),
            Skill(id: "sk-tdd", name: "test-driven-development", summary: "Write a failing test, make it pass, refactor.",
                  category: "Software development", isEnabled: true, version: "1.0.2", origin: .bundled, usageCount: 12, lastUsedAt: clock.ago(days: 6),
                  instructionsPreview: "Red → green → refactor. Each change should be driven by a failing test.", requiredToolsets: ["terminal", "file"]),
            Skill(id: "sk-docker", name: "docker-management", summary: "Inspect, restart and clean up containers on the host.",
                  category: "DevOps", isEnabled: true, version: "0.3.0", origin: .local, usageCount: 7, lastUsedAt: clock.ago(days: 9),
                  instructionsPreview: "Prefer `docker compose` over raw `docker run`. Ask before pruning volumes.", requiredToolsets: ["terminal"]),
            Skill(id: "sk-arxiv", name: "arxiv", summary: "Search and summarize arXiv papers with proper citations.",
                  category: "Research", isEnabled: true, version: "2.0.0", origin: .hub, usageCount: 64, lastUsedAt: clock.ago(minutes: 6),
                  instructionsPreview: "Use the arXiv API for search. Cite as [Author et al., Year](link). Separate claims from results.", requiredToolsets: ["web"]),
            Skill(id: "sk-bench", name: "benchmark-analysis", summary: "Load benchmark CSVs, compute percentiles and plot latency distributions.",
                  category: "Research", isEnabled: true, version: nil, origin: .agentCreated, usageCount: 9, lastUsedAt: clock.ago(minutes: 4),
                  instructionsPreview: "Load with pandas. Report p50/p95/p99. Plot with matplotlib, one chart per question. Save under results/plots/.",
                  requiredToolsets: ["code_execution", "file"]),
            Skill(id: "sk-plan", name: "plan", summary: "Break a request into steps and keep a todo list while working.",
                  category: "Productivity", isEnabled: true, version: "1.2.0", origin: .bundled, usageCount: 203, lastUsedAt: clock.ago(minutes: 2),
                  instructionsPreview: "For anything over three steps, write the plan first and update it as you go.", requiredToolsets: ["todo"]),
            Skill(id: "sk-obsidian", name: "obsidian", summary: "Read and write notes in an Obsidian vault, respecting links and templates.",
                  category: "Note-taking", isEnabled: true, version: "1.0.0", origin: .hub, usageCount: 48, lastUsedAt: clock.ago(minutes: 24),
                  instructionsPreview: "Use [[wikilinks]]. Respect templates in Templates/. Never rename files without asking.", requiredToolsets: ["file"]),
            Skill(id: "sk-morning", name: "morning-report", summary: "Three-bullet daily briefing delivered to Telegram.",
                  category: "Productivity", isEnabled: true, version: nil, origin: .agentCreated, usageCount: 41, lastUsedAt: clock.ago(hours: 3.2),
                  instructionsPreview: "Calendar, reviews, weather. Three bullets, no preamble.", requiredToolsets: ["web", "messaging"]),
            Skill(id: "sk-excalidraw", name: "excalidraw", summary: "Produce hand-drawn style diagrams as .excalidraw files.",
                  category: "Creative", isEnabled: false, version: "0.9.1", origin: .bundled, usageCount: 2, lastUsedAt: clock.ago(days: 40),
                  instructionsPreview: "Emit valid Excalidraw JSON. Keep diagrams under 30 elements.", requiredToolsets: ["file"]),
            Skill(id: "sk-youtube", name: "youtube-content", summary: "Fetch transcripts and summarize videos.",
                  category: "Media", isEnabled: false, version: "1.0.0", origin: .hub, usageCount: 0, lastUsedAt: nil,
                  instructionsPreview: "Fetch the transcript, then summarize by chapter.", requiredToolsets: ["web"]),
            Skill(id: "sk-gworkspace", name: "google-workspace", summary: "Read Gmail, Calendar and Drive via OAuth.",
                  category: "Productivity", isEnabled: false, version: "0.5.0", origin: .hub, usageCount: 0, lastUsedAt: nil,
                  instructionsPreview: "Requires OAuth setup on the host before use.", requiredToolsets: ["web"]),
        ]
    }

    // MARK: Tools

    static let tools: [ToolInfo] = [
        ToolInfo(name: "terminal", toolset: "terminal", summary: "Run shell commands on the host.", availability: .available),
        ToolInfo(name: "process", toolset: "terminal", summary: "Manage long-running background processes.", availability: .available),
        ToolInfo(name: "read_file", toolset: "file", summary: "Read files from the host filesystem.", availability: .available),
        ToolInfo(name: "write_file", toolset: "file", summary: "Create or overwrite files.", availability: .available),
        ToolInfo(name: "patch", toolset: "file", summary: "Apply targeted edits to files.", availability: .available),
        ToolInfo(name: "search_files", toolset: "file", summary: "Search file names and contents.", availability: .available),
        ToolInfo(name: "web_search", toolset: "web", summary: "Search the web.", availability: .available),
        ToolInfo(name: "web_extract", toolset: "web", summary: "Fetch and extract readable page content.", availability: .available),
        ToolInfo(name: "browser_navigate", toolset: "browser", summary: "Drive a headless browser.", availability: .available),
        ToolInfo(name: "browser_snapshot", toolset: "browser", summary: "Capture the accessibility tree of a page.", availability: .available),
        ToolInfo(name: "vision_analyze", toolset: "vision", summary: "Describe and analyze images.", availability: .available),
        ToolInfo(name: "image_generate", toolset: "image_gen", summary: "Generate images.", availability: .needsSetup("Set FAL_KEY on the host.")),
        ToolInfo(name: "text_to_speech", toolset: "tts", summary: "Synthesize speech for voice replies.", availability: .available),
        ToolInfo(name: "execute_code", toolset: "code_execution", summary: "Run Python in a sandbox with tool access.", availability: .available),
        ToolInfo(name: "delegate_task", toolset: "delegation", summary: "Spawn subagents for parallel work.", availability: .available),
        ToolInfo(name: "memory", toolset: "memory", summary: "Read and update persistent memory.", availability: .available),
        ToolInfo(name: "session_search", toolset: "session_search", summary: "Search past conversations.", availability: .available),
        ToolInfo(name: "todo", toolset: "todo", summary: "Maintain a task list during a run.", availability: .available),
        ToolInfo(name: "cronjob", toolset: "cronjob", summary: "Create and manage scheduled routines.", availability: .available),
        ToolInfo(name: "send_message", toolset: "messaging", summary: "Send messages through connected platforms.", availability: .available),
        ToolInfo(name: "skill_manage", toolset: "skills", summary: "Create, edit and view skills.", availability: .available),
        ToolInfo(name: "clarify", toolset: "clarify", summary: "Ask the user a clarifying question.", availability: .available),
        ToolInfo(name: "ha_call_service", toolset: "homeassistant", summary: "Control Home Assistant devices.", availability: .unavailable("Home Assistant integration is in an error state.")),
        ToolInfo(name: "mixture_of_agents", toolset: "moa", summary: "Query several models and synthesize.", availability: .needsSetup("Requires an OpenRouter key with multi-model access.")),
    ]

    // MARK: MCP

    static func mcpServers(_ clock: MockClock) -> [MCPServer] {
        [
            MCPServer(id: "mcp-github", name: "github", transport: .stdio, endpoint: "npx @modelcontextprotocol/server-github",
                      status: .connected, errorMessage: nil,
                      toolNames: ["create_issue", "list_pull_requests", "get_pull_request", "create_pull_request", "merge_pull_request", "search_code", "get_file_contents", "list_commits", "create_branch", "add_comment"],
                      lastConnectedAt: clock.ago(hours: 9)),
            MCPServer(id: "mcp-filesystem", name: "filesystem", transport: .stdio, endpoint: "npx @modelcontextprotocol/server-filesystem ~/Research",
                      status: .connected, errorMessage: nil,
                      toolNames: ["read_text_file", "write_file", "edit_file", "list_directory", "directory_tree", "move_file", "search_files", "get_file_info"],
                      lastConnectedAt: clock.ago(hours: 9)),
            MCPServer(id: "mcp-linear", name: "linear", transport: .http, endpoint: "https://mcp.linear.app/sse",
                      status: .error, errorMessage: "401 Unauthorized — OAuth token expired.", toolNames: [], lastConnectedAt: clock.ago(days: 6)),
            MCPServer(id: "mcp-postgres", name: "postgres", transport: .stdio, endpoint: "uvx mcp-server-postgres postgresql://localhost/bench",
                      status: .disconnected, errorMessage: nil, toolNames: ["query", "list_tables", "describe_table"], lastConnectedAt: clock.ago(days: 2)),
        ]
    }

    // MARK: Integrations

    static func integrations(_ clock: MockClock) -> [Integration] {
        [
            Integration(id: "int-telegram", platform: .telegram, status: .connected, detail: "@example_bot · Home, Research", lastActivity: clock.ago(minutes: 62)),
            Integration(id: "int-discord", platform: .discord, status: .connected, detail: "Lab server · #hermes", lastActivity: clock.ago(days: 1)),
            Integration(id: "int-email", platform: .email, status: .connected, detail: "IMAP · inbox triage", lastActivity: clock.ago(minutes: 62)),
            Integration(id: "int-whatsapp", platform: .whatsapp, status: .disconnected, detail: "Session expired. Re-pair from the host.", lastActivity: clock.ago(days: 8)),
            Integration(id: "int-ha", platform: .homeAssistant, status: .error, detail: "Connection refused at homeassistant.local:8123", lastActivity: clock.ago(days: 2)),
            Integration(id: "int-slack", platform: .slack, status: .notConfigured, detail: nil, lastActivity: nil),
            Integration(id: "int-signal", platform: .signal, status: .notConfigured, detail: nil, lastActivity: nil),
        ]
    }

    // MARK: Logs

    static func logs(_ clock: MockClock) -> [LogEntry] {
        var counter = 0
        func log(_ level: LogLevel, _ category: LogCategory, _ message: String, _ date: Date, detail: String? = nil, run: String? = nil) -> LogEntry {
            counter += 1
            return LogEntry(id: "log-\(counter)", timestamp: date, level: level, category: category, message: message, detail: detail, runID: run)
        }
        return [
            log(.info, .run, "Run started: Analyzing provider benchmark", clock.ago(seconds: 222), run: "r-bench"),
            log(.info, .run, "Run started: Triaging new arXiv submissions", clock.ago(minutes: 6), run: "r-arxiv"),
            log(.warning, .approval, "Approval requested: rm generated-cache.json", clock.ago(minutes: 11), detail: "Run r-ios · Caddy · pattern: rm", run: "r-ios"),
            log(.info, .run, "Run started: Updating Talaria repo", clock.ago(minutes: 12), run: "r-ios"),
            log(.warning, .approval, "Approval requested: write Index.md", clock.ago(minutes: 24), detail: "Run r-notes · Dex", run: "r-notes"),
            log(.info, .run, "Run completed: Clean up stale build scripts (8m 02s)", clock.ago(minutes: 48), run: "r-cleanup"),
            log(.info, .routine, "Routine fired: Inbox triage", clock.ago(minutes: 64), run: "r-triage"),
            log(.info, .connection, "Connected to Mac Studio (18 ms)", clock.ago(minutes: 70)),
            log(.warning, .connection, "Connection lost: Mac Studio", clock.ago(minutes: 71), detail: "URLError -1005: The network connection was lost."),
            log(.info, .run, "Run completed: Server alerts digest", clock.ago(hours: 2), run: "r-alerts"),
            log(.error, .integration, "Home Assistant: connection refused", clock.ago(hours: 2.4), detail: "GET http://homeassistant.local:8123/api/ → ECONNREFUSED"),
            log(.info, .routine, "Routine fired: Morning report", clock.ago(hours: 3.3), run: "r-morning"),
            log(.error, .integration, "hermes-gateway restarted (OOM)", clock.ago(hours: 5.1), detail: "whisper transcription exceeded memory limit; restarted by launchd"),
            log(.error, .integration, "hermes-gateway restarted (OOM)", clock.ago(hours: 5.3), detail: "whisper transcription exceeded memory limit; restarted by launchd"),
            log(.error, .run, "Run failed: Nightly research sweep", clock.ago(hours: 8.93), detail: "openrouter: 429 Too Many Requests (retry 3/3)\nTraceback (most recent call last):\n  File \"tools/web.py\", line 212, in extract\nRateLimitError: 429", run: "r-nightly"),
            log(.warning, .run, "Rate limited by OpenRouter, retrying in 30s (2/3)", clock.ago(hours: 8.95), run: "r-nightly"),
            log(.warning, .run, "Rate limited by OpenRouter, retrying in 10s (1/3)", clock.ago(hours: 8.97), run: "r-nightly"),
            log(.info, .routine, "Routine fired: Nightly research sweep", clock.ago(hours: 9), run: "r-nightly"),
            log(.warning, .connection, "demo-worker unreachable", clock.ago(hours: 19), detail: "No route to host via Tailscale (192.0.2.10)"),
            log(.error, .integration, "MCP server linear: 401 Unauthorized", clock.ago(days: 1), detail: "OAuth token expired. Re-authenticate on the host."),
            log(.info, .run, "Run cancelled: Deploy docs site to Fly.io", clock.ago(days: 1, hours: 2.9), run: "r-deploy"),
            log(.error, .run, "Run failed: Evaluate Hermes 4 tool calling", clock.ago(days: 2, hours: 3.7), detail: "MLX: [metal::malloc] Resource limit exceeded", run: "r-eval"),
            log(.debug, .app, "Snapshot cache restored (8 collections)", clock.ago(minutes: 70)),
        ]
    }

    // MARK: Usage

    static func usage(period: UsagePeriod, now: Date) -> UsageReport {
        let calendar = Calendar.current
        let days: Int = switch period { case .day: 1; case .week: 7; case .month: 30 }
        let pattern = [412, 380, 905, 610, 220, 140, 760, 820, 530, 300, 690, 1_040, 470, 350, 610, 580, 260, 190, 720, 880, 640, 410, 300, 950, 700, 520, 480, 330, 610, 655]
        let daily: [DailyUsage] = (0..<max(days, 7)).reversed().map { offset in
            let date = calendar.startOfDay(for: now.addingTimeInterval(-Double(offset) * 86_400))
            let tokens = pattern[offset % pattern.count] * 1_000
            return DailyUsage(date: date, tokens: tokens, runs: max(3, tokens / 38_000))
        }
        let relevant = Array(daily.suffix(days))
        let totalTokens = relevant.reduce(0) { $0 + $1.tokens }
        let shares: [(ModelRef, Double, Int)] = [
            (MockModels.sonnet, 0.41, 38), (MockModels.opus, 0.27, 17), (MockModels.hermes70, 0.18, 44),
            (MockModels.gpt, 0.09, 9), (MockModels.local, 0.05, 12),
        ]
        let scale = Double(days) / 7
        let models = shares.map { model, share, runs in
            let total = Int(Double(totalTokens) * share)
            return ModelUsage(model: model, usage: TokenUsage(input: Int(Double(total) * 0.93), output: Int(Double(total) * 0.07)),
                              runCount: max(1, Int(Double(runs) * scale)))
        }
        let runCount = models.reduce(0) { $0 + $1.runCount }
        return UsageReport(period: period,
                           totals: TokenUsage(input: Int(Double(totalTokens) * 0.93), output: Int(Double(totalTokens) * 0.07)),
                           runCount: runCount, models: models, daily: relevant)
    }
}
