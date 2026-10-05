import Foundation

/// Scripted behaviour for simulated runs.
nonisolated enum MockScripts {
    // MARK: Fixture continuations

    static let benchContinuation: [ScriptStep] = [
        .finishActive(call: ToolCall(kind: .code, name: "execute_code", summary: "Ran analysis.py",
                                     input: "uv run analysis.py --group-by hour --correlate prompt_tokens",
                                     output: "grouped 150 requests into 24 hourly buckets\npearson r(prompt_tokens, ttft) = 0.21 (p = 0.011)\nwrote results/p95_by_hour.csv",
                                     duration: 74), after: 70),
        .tool(active: "Plotting p95 by hour",
              call: ToolCall(kind: .code, name: "execute_code", summary: "Plotted p95 by hour",
                             input: "uv run plot.py results/p95_by_hour.csv", output: "saved results/plots/p95_by_hour.png"),
              seconds: 26),
        .respond("""
        The OpenRouter p95 tail is mostly **time of day**, not prompt length.

        | Window (UTC) | Requests | p95 TTFT |
        |:--|--:|--:|
        | 00:00–06:00 | 38 | 0.71 s |
        | 06:00–12:00 | 41 | 0.83 s |
        | 12:00–18:00 | 36 | 0.96 s |
        | 18:00–22:00 | 35 | **1.64 s** |

        - Correlation with prompt length is weak: *r* = 0.21 (p = 0.011).
        - 9 of the 11 slow requests landed between 18:00 and 22:00 UTC, the US daytime peak.

        I'd schedule latency-sensitive routines outside that window or route them to Nous Portal. The plot is saved at `results/plots/p95_by_hour.png`.
        """),
        .attach(.image(ImageAttachment(id: "img-p95", name: "p95_by_hour.png", source: .asset("MockChartLatency"),
                                       aspectRatio: 1.6, caption: "OpenRouter p95 TTFT by hour (UTC)"))),
        .complete(summary: "p95 tail concentrated 18:00–22:00 UTC; weak correlation with prompt length."),
    ]

    static let arxivContinuation: [ScriptStep] = [
        .finishActive(call: ToolCall(kind: .browser, name: "web_extract", summary: "Read 38 abstracts"), after: 45),
        .tool(active: "Flag KV-compression papers",
              call: ToolCall(kind: .code, name: "execute_code", summary: "Scored 38 papers with the triage rubric",
                             output: "4 papers ≥ 0.7 · 3 mention KV compression"),
              seconds: 18),
        .respond("""
        Scored today's **38** submissions. Three touch KV compression:

        1. **Learned KV eviction for long-horizon agents** — 0.82. Evicts by predicted future attention; 4× smaller cache at equal accuracy on 128k tasks.
        2. **Mixed-precision KV with per-head budgets** — 0.76. INT4 for most heads, FP8 for retrieval heads.
        3. **Cross-layer KV sharing revisited** — 0.71. Solid ablations, modest gains.

        #1 is worth a closer read for the on-device work — it's the only one evaluated at batch size 1.
        """),
        .complete(summary: "3 KV-compression papers flagged out of 38."),
    ]

    static let iosApproved: [ScriptStep] = [
        .tool(active: "Removing generated-cache.json",
              call: ToolCall(kind: .terminal, name: "terminal", summary: "Ran rm generated-cache.json", input: "rm generated-cache.json"),
              seconds: 1.5),
        .tool(active: "Rebuild with swift build",
              call: ToolCall(kind: .terminal, name: "terminal", summary: "Ran swift build", input: "swift build",
                             output: "Building for debugging...\n[412/412] Compiling HermesAPI\nBuild complete! (24.81s)", duration: 24.8),
              seconds: 20),
        .respond("""
        Done. The cache is cleared and the package builds cleanly against the regenerated client.

        **What changed in the schema**
        - 3 new models: `RunEvent.sequence`, `ApprovalState`, `ProfileSummary`
        - 1 renamed operation: `cancelRun` → `stopRun`
        - `HostStatus.capabilities` is now a set instead of a bitmask

        ```text
        Build complete! (24.81s)
        ```

        Nothing is committed yet. Want me to open a PR?
        """),
        .complete(summary: "Cache cleared; build passes against the regenerated client."),
    ]

    static let iosDenied: [ScriptStep] = [
        .tool(active: "Rebuild with swift build",
              call: ToolCall(kind: .terminal, name: "terminal", summary: "Ran swift build", input: "swift build",
                             output: "warning: stale types loaded from generated-cache.json\nBuild complete! (31.02s)"),
              seconds: 18),
        .respond("Skipped deleting `generated-cache.json`. The build still passes, but it warned about stale types from the cache — autocomplete may be odd until it's cleared.\n\nRun `rm generated-cache.json` yourself when convenient."),
        .complete(summary: "Built without clearing the cache (stale-type warning)."),
    ]

    static let notesApproved: [ScriptStep] = [
        .tool(active: "Updating Index.md",
              call: ToolCall(kind: .files, name: "patch", summary: "Updated Index.md", targets: ["Index.md"]), seconds: 1.5),
        .tool(active: "Archive meeting links",
              call: ToolCall(kind: .files, name: "patch", summary: "Archived 3 meeting links"), seconds: 2),
        .respond("""
        All set. `Weekly/2026-W40.md` is linked from the index and this week's meeting links point to it.

        **Highlights this week**
        - Bench review: local inference wins TTFT, loses throughput
        - Hermes roadmap: mobile bridge before notifications
        - Infra sync: demo-worker needs a new NIC
        """),
        .complete(summary: "Weekly note linked; 3 meeting links archived."),
    ]

    static let notesDenied: [ScriptStep] = [
        .respond("Left `Index.md` unchanged. The weekly note is at `Weekly/2026-W40.md` if you want to link it yourself."),
        .complete(summary: "Weekly note created; index unchanged."),
    ]

    // MARK: New runs

    static func reply(to prompt: String, profileID: String?) -> [ScriptStep] {
        let lower = prompt.lowercased()
        let topic = self.topic(prompt)
        if ["delete", "remove", "clean", "rm ", "wipe", "purge"].contains(where: lower.contains) {
            return cleanup
        }
        if profileID == MockID.caddy || ["code", "repo", "build", "test", "fix", "bug", "swift", "git", "refactor", "compile"].contains(where: lower.contains) {
            return coding
        }
        if profileID == MockID.researcher || profileID == MockID.analyst
            || ["research", "paper", "compare", "benchmark", "survey", "latest", "news"].contains(where: lower.contains) {
            return research(topic)
        }
        return general(topic)
    }

    static let coding: [ScriptStep] = [
        .plan(["Inspect repository", "Make the change", "Run tests", "Preparing response"]),
        .pause(1.2),
        .tool(active: "Inspect repository",
              call: ToolCall(kind: .files, name: "read_file", summary: "Read AGENTS.md and 3 files",
                             targets: ["AGENTS.md", "Package.swift", "Sources/App/ConnectionModel.swift", "Tests/AppTests/ConnectionTests.swift"]),
              seconds: 3),
        .tool(active: "Make the change",
              call: ToolCall(kind: .files, name: "patch", summary: "Edited 2 files",
                             targets: ["Sources/App/ConnectionModel.swift", "Tests/AppTests/ConnectionTests.swift"]),
              seconds: 5),
        .tool(active: "Run tests",
              call: ToolCall(kind: .terminal, name: "terminal", summary: "Ran swift test", input: "swift test",
                             output: "Test Suite 'All tests' passed.\nExecuted 48 tests, with 0 failures (0 unexpected) in 3.112 seconds"),
              seconds: 6),
        .respond("""
        Done. Here's the core of the change:

        ```swift
        func reconnect() async {
            guard !isReconnecting else { return }
            isReconnecting = true
            defer { isReconnecting = false }
            try? await client.connect(resumingFrom: lastCursor)
        }
        ```

        - Overlapping reconnects are now ignored
        - Resumes from the last processed cursor instead of refetching everything

        All **48 tests** pass. Nothing is committed yet.
        """),
        .complete(summary: "Edited 2 files; 48 tests pass."),
    ]

    static func research(_ topic: String) -> [ScriptStep] {
        [
            .plan(["Search sources", "Read top results", "Preparing response"]),
            .pause(1),
            .tool(active: "Search sources",
                  call: ToolCall(kind: .web, name: "web_search", summary: "Searched the web", input: topic, output: "18 results"),
                  seconds: 3),
            .tool(active: "Read top results",
                  call: ToolCall(kind: .browser, name: "browser_navigate", summary: "Visited 3 pages",
                                 targets: ["arxiv.org", "huggingface.co/blog", "github.com"]),
                  seconds: 6),
            .respond("""
            Here's a quick read on **\(topic)**:

            | Source | Takeaway | Confidence |
            |:--|:--|:--|
            | Recent paper | Promising results at small scale | Medium |
            | Vendor blog | Claims a 2× speedup, no ablations | Low |
            | GitHub thread | Users report regressions on long inputs | Medium |

            Evidence is thin beyond the paper. If it matters, I'd reproduce the headline number on the Studio before relying on it.
            """),
            .complete(summary: "Summarized 3 sources."),
        ]
    }

    static func general(_ topic: String) -> [ScriptStep] {
        [
            .plan(["Preparing response"]),
            .tool(active: "Checking memory", call: ToolCall(kind: .memory, name: "memory", summary: "Recalled 2 memories"), seconds: 1.5),
            .respond("""
            Sure. A few thoughts on “\(topic)”:

            1. Start with the smallest version that's useful today.
            2. Write down what *done* looks like before starting.
            3. Schedule a check-in so it doesn't drift.

            Want me to turn this into a task or a routine?
            """),
            .complete(summary: "Answered."),
        ]
    }

    static let cleanup: [ScriptStep] = [
        .plan(["Find candidates", "Remove files", "Preparing response"]),
        .tool(active: "Find candidates",
              call: ToolCall(kind: .terminal, name: "terminal", summary: "Ran du -sh .build/cache", input: "du -sh .build/cache", output: "1.4G\t.build/cache"),
              seconds: 2.5),
        .approval(ApprovalTemplate(kind: .command, summary: "Remove the local build cache (1.4 GB)", command: "rm -rf .build/cache",
                                   workingDirectory: "demo/talaria", paths: [".build/cache"],
                                   reason: "Matches a dangerous-command pattern: recursive delete (rm -rf).",
                                   risk: .high, expiresIn: 300),
                  approved: [
                    .tool(active: "Remove files",
                          call: ToolCall(kind: .terminal, name: "terminal", summary: "Ran rm -rf .build/cache", input: "rm -rf .build/cache"),
                          seconds: 2),
                    .respond("Removed `.build/cache` and freed **1.4 GB**. The next build will be a full one (about 3 minutes)."),
                    .complete(summary: "Freed 1.4 GB."),
                  ],
                  denied: [
                    .respond("Okay — left `.build/cache` in place. `swift package clean` is a gentler alternative if you want it later."),
                    .complete(summary: "No files removed."),
                  ]),
    ]

    static func routine(_ routine: Routine) -> [ScriptStep] {
        var steps: [ScriptStep] = [
            .plan(["Gather inputs", "Write summary"] + (routine.delivery == nil ? [] : ["Deliver"])),
            .tool(active: "Gather inputs", call: ToolCall(kind: .web, name: "web_search", summary: "Checked 4 sources"), seconds: 4),
        ]
        let body = switch routine.id {
        case "rt-morning": "**Good morning.**\n\n- **Calendar:** Bench review 16:00\n- **Reviews:** 1 PR waiting — `hermes-ios#42`\n- **Weather:** overcast, 15°C"
        case "rt-nightly": "Top items from the sweep:\n\n1. Provider changelog: Nous Portal raised rate limits for Hermes 4\n2. *Learned KV eviction for long-horizon agents* (arXiv)\n3. HN discussion on agent sandboxes"
        default: "**\(routine.name)** finished.\n\n- Checked 4 sources\n- Nothing urgent"
        }
        steps.append(.respond(body))
        if let delivery = routine.delivery {
            steps.append(.tool(active: "Deliver", call: ToolCall(kind: .messaging, name: "send_message", summary: "Sent to \(delivery)"), seconds: 1.5))
        }
        steps.append(.complete(summary: "\(routine.name) delivered."))
        return steps
    }

    // MARK: Text helpers

    static func topic(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return firstLine.count > 60 ? String(firstLine.prefix(57)) + "…" : firstLine
    }

    /// Conversation titles, like Hermes' automatic session titling.
    static func title(for text: String) -> String {
        let topic = topic(text).trimmingCharacters(in: CharacterSet(charactersIn: ".?!"))
        guard !topic.isEmpty else { return "New conversation" }
        let short = topic.count > 40 ? String(topic.prefix(38)) + "…" : topic
        return short.prefix(1).uppercased() + short.dropFirst()
    }

    static func runTitle(for text: String) -> String {
        title(for: text)
    }

    /// Splits text into small streaming chunks (two words at a time).
    static func chunks(_ text: String) -> [String] {
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var result: [String] = []
        var index = 0
        while index < words.count {
            let slice = words[index..<min(index + 2, words.count)].joined(separator: " ")
            index += 2
            result.append(index < words.count ? slice + " " : slice)
        }
        return result
    }
}
