import Foundation

/// Stable identifiers used across mock fixtures.
nonisolated enum MockID {
    static let studio = "host-studio"
    static let office = "host-demo-worker"

    static let caddy = "bot-caddy"
    static let researcher = "bot-researcher"
    static let dex = "bot-dex"
    static let analyst = "bot-analyst"
}

nonisolated enum MockModels {
    static let sonnet = ModelRef(id: "anthropic/claude-sonnet-5", displayName: "Claude Sonnet 5", provider: "OpenRouter")
    static let opus = ModelRef(id: "anthropic/claude-opus-5.5", displayName: "Claude Opus 5.5", provider: "OpenRouter")
    static let hermes405 = ModelRef(id: "nousresearch/hermes-4-405b", displayName: "Hermes 4 405B", provider: "Nous Portal")
    static let hermes70 = ModelRef(id: "nousresearch/hermes-4-70b", displayName: "Hermes 4 70B", provider: "Nous Portal")
    static let gpt = ModelRef(id: "openai/gpt-5.1", displayName: "GPT-5.1", provider: "OpenAI")
    static let local = ModelRef(id: "qwen3-coder-30b-a3b", displayName: "Qwen3 Coder 30B", provider: "LM Studio · local")

    static let all = [sonnet, opus, hermes405, hermes70, gpt, local]
}

nonisolated enum MockProjects {
    static let hermesIOS = ProjectContext(name: "hermes-ios", path: "demo/talaria")
    static let providerBench = ProjectContext(name: "provider-bench", path: "demo/provider-bench")
    static let docs = ProjectContext(name: "hermes-docs", path: "demo/docs")
    static let notes = ProjectContext(name: "Notes", path: "demo/notes")

    static let all = [hermesIOS, providerBench, docs, notes]
}

/// A complete, internally consistent snapshot of a simulated Hermes host.
/// Dates are relative to `now` so the data always looks current.
struct MockFixtures {
    var hosts: [Host]
    var hostStatuses: [String: HostStatus]
    var profiles: [Profile]
    var conversations: [Conversation]
    var messages: [String: [Message]]
    var runs: [Run]
    var approvals: [ApprovalRequest]
    var tasks: [HermesTask]
    var routines: [Routine]
    var memory: [MemoryEntry]
    var skills: [Skill]
    var tools: [ToolInfo]
    var mcpServers: [MCPServer]
    var integrations: [Integration]
    var logs: [LogEntry]

    static func standard(now: Date = .now) -> MockFixtures {
        let clock = MockClock(now: now)
        return MockFixtures(
            hosts: hosts,
            hostStatuses: hostStatuses(clock),
            profiles: profiles,
            conversations: conversations(clock),
            messages: messages(clock),
            runs: runs(clock).map(sequenced),
            approvals: approvals(clock),
            tasks: tasks(clock),
            routines: routines(clock),
            memory: memory(clock),
            skills: skills(clock),
            tools: tools,
            mcpServers: mcpServers(clock),
            integrations: integrations(clock),
            logs: logs(clock)
        )
    }

    // MARK: Hosts

    static let hosts: [Host] = [
        Host(id: MockID.studio, name: "Mac Studio", address: "studio.example.invalid", port: 8642, network: .tailscale, symbol: "macstudio"),
        Host(id: MockID.office, name: "Office", address: "office.example.invalid", port: 8642, network: .tailscale, symbol: "server.rack"),
    ]

    static func hostStatuses(_ clock: MockClock) -> [String: HostStatus] {
        [
            MockID.studio: HostStatus(
                hostID: MockID.studio, connection: .connected, hermesState: .running, bridgeVersion: "0.3.1", hermesVersion: "0.9.2",
                defaultModel: MockModels.sonnet, activeRunCount: 4, latencyMilliseconds: 18, lastSeen: clock.now,
                capabilities: .all,
                resources: HostResources(cpuLoad: 0.34, memoryUsed: 0.41, uptime: 9 * 86_400 + 4 * 3600)),
            MockID.office: HostStatus(
                hostID: MockID.office, connection: .bridgeOffline, hermesState: .unknown, bridgeVersion: "0.2.0", hermesVersion: "0.8.6",
                defaultModel: MockModels.hermes70, activeRunCount: 0, latencyMilliseconds: nil,
                lastSeen: clock.ago(hours: 19), capabilities: [.sessions, .runs, .stop, .cron, .memory, .skills, .tools, .logs],
                resources: nil),
        ]
    }

    // MARK: Profiles

    static let profiles: [Profile] = [
        Profile(id: Profile.defaultID, name: "Hermes", role: "Default profile",
                summary: "The default Hermes profile. Used for conversations that don't pick a specific bot.",
                tint: .slate, model: MockModels.sonnet, status: .idle, hostID: MockID.studio, isDefault: true,
                skillIDs: ["sk-plan", "sk-arxiv", "sk-github-pr"],
                toolsets: ["terminal", "file", "web", "browser", "code_execution", "memory"],
                mcpServerIDs: ["mcp-github", "mcp-filesystem"],
                memorySummary: "Shared user profile and general environment notes.", memoryEntryCount: 18,
                soulSummary: nil, configPath: "~/.hermes", currentRunID: nil),
        Profile(id: MockID.caddy, name: "Caddy", role: "Coding",
                summary: "Works in repositories on the Studio: changes, builds, tests and small refactors.",
                tint: .teal, model: MockModels.sonnet, status: .needsAttention, hostID: MockID.studio, isDefault: false,
                skillIDs: ["sk-github-pr", "sk-debugging", "sk-tdd", "sk-docker"],
                toolsets: ["terminal", "file", "code_execution", "web", "delegation"],
                mcpServerIDs: ["mcp-github", "mcp-filesystem"],
                memorySummary: "Knows the build and release steps for hermes-ios, hermes-docs and provider-bench. Remembers that pushes need explicit approval.",
                memoryEntryCount: 23,
                soulSummary: "Pragmatic senior engineer. Prefers small, reviewable diffs, runs the tests before claiming success, and never pushes or deploys without asking.",
                configPath: "~/.hermes/profiles/caddy", currentRunID: "r-ios"),
        Profile(id: MockID.researcher, name: "Researcher", role: "Research",
                summary: "Literature and benchmark work. Reads papers, runs analyses, cites sources.",
                tint: .indigo, model: MockModels.opus, status: .working, hostID: MockID.studio, isDefault: false,
                skillIDs: ["sk-arxiv", "sk-bench", "sk-plan"],
                toolsets: ["web", "browser", "code_execution", "file", "vision"],
                mcpServerIDs: ["mcp-filesystem"],
                memorySummary: "Tracks the provider benchmark methodology, preferred sources, and which providers rate-limit overnight.",
                memoryEntryCount: 41,
                soulSummary: "Careful, citation-first researcher. Separates evidence from speculation and states confidence explicitly.",
                configPath: "~/.hermes/profiles/researcher", currentRunID: "r-bench"),
        Profile(id: MockID.dex, name: "Dex", role: "General",
                summary: "Everyday assistant for notes, inbox, calendar and home.",
                tint: .amber, model: MockModels.hermes70, status: .needsAttention, hostID: MockID.studio, isDefault: false,
                skillIDs: ["sk-obsidian", "sk-morning", "sk-plan"],
                toolsets: ["file", "web", "messaging", "cronjob", "homeassistant"],
                mcpServerIDs: [],
                memorySummary: "Knows the Notes vault layout, the morning report format, and household routines.",
                memoryEntryCount: 57,
                soulSummary: "Brief, warm and proactive. Summarizes first, details on request. Asks before touching anything outside demo/notes.",
                configPath: "~/.hermes/profiles/dex", currentRunID: "r-notes"),
        Profile(id: MockID.analyst, name: "Analyst", role: "Analysis",
                summary: "Turns raw findings into summaries with numbers, caveats and next steps.",
                tint: .rose, model: MockModels.gpt, status: .working, hostID: MockID.studio, isDefault: false,
                skillIDs: ["sk-bench", "sk-plan"],
                toolsets: ["code_execution", "file", "web"],
                mcpServerIDs: [],
                memorySummary: "Keeps the digest template and the scoring rubric for paper triage.",
                memoryEntryCount: 12,
                soulSummary: nil,
                configPath: "~/.hermes/profiles/analyst", currentRunID: "r-arxiv"),
    ]

    /// Assigns ordered sequence numbers to a fixture run's events.
    static func sequenced(_ run: Run) -> Run {
        var run = run
        run.events = run.events.enumerated().map { index, event in
            var event = event
            event.sequence = index + 1
            return event
        }
        return run
    }
}

/// Relative date helper for fixtures.
nonisolated struct MockClock {
    let now: Date

    func ago(days: Double = 0, hours: Double = 0, minutes: Double = 0, seconds: TimeInterval = 0) -> Date {
        now.addingTimeInterval(-(seconds + minutes * 60 + hours * 3600 + days * 86_400))
    }

    func ahead(minutes: Double = 0, hours: Double = 0, days: Double = 0) -> Date {
        now.addingTimeInterval(minutes * 60 + hours * 3600 + days * 86_400)
    }

    /// Next occurrence of `hour:minute` on one of `weekdays` (1 = Sunday).
    func next(hour: Int, minute: Int = 0, weekdays: Set<Int>? = nil) -> Date {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        var candidate = now
        for _ in 0..<14 {
            guard let date = calendar.nextDate(after: candidate, matching: components, matchingPolicy: .nextTime) else { break }
            if let weekdays, !weekdays.contains(calendar.component(.weekday, from: date)) {
                candidate = date
                continue
            }
            return date
        }
        return ahead(days: 1)
    }
}
