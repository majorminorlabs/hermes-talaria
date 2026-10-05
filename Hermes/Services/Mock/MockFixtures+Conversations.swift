import Foundation

extension MockFixtures {
    static func conversations(_ clock: MockClock) -> [Conversation] {
        [
            Conversation(id: "c-researcher", title: "Researcher", profileID: MockID.researcher, hostID: MockID.studio,
                         source: .app, createdAt: clock.ago(days: 12), lastActivity: clock.ago(minutes: 4),
                         preview: "Break down the p95 tail by hour and check if it correlates with prompt length.",
                         project: MockProjects.providerBench, model: MockModels.opus, activeRunID: "r-bench",
                         isPinned: true, messageCount: 48),
            Conversation(id: "c-caddy", title: "Caddy", profileID: MockID.caddy, hostID: MockID.studio,
                         source: .app, createdAt: clock.ago(days: 30), lastActivity: clock.ago(minutes: 11),
                         preview: "Pulled 12 changed files and regenerated the client.",
                         project: MockProjects.hermesIOS, model: MockModels.sonnet, activeRunID: "r-ios",
                         isPinned: true, messageCount: 132),
            Conversation(id: "c-dex", title: "Dex", profileID: MockID.dex, hostID: MockID.studio,
                         source: .app, createdAt: clock.ago(days: 40), lastActivity: clock.ago(minutes: 22),
                         preview: "Waiting on your approval to update Index.md.",
                         project: MockProjects.notes, model: MockModels.hermes70, activeRunID: "r-notes",
                         isPinned: false, messageCount: 210),
            Conversation(id: "c-cleanup", title: "Clean up stale build scripts", profileID: MockID.caddy, hostID: MockID.studio,
                         source: .app, createdAt: clock.ago(minutes: 56), lastActivity: clock.ago(minutes: 48),
                         preview: "Removed 4 unreferenced scripts. Build passes.",
                         project: MockProjects.docs, model: MockModels.sonnet, activeRunID: nil, isPinned: false, messageCount: 2),
            Conversation(id: "c-telegram", title: "Server alerts digest", profileID: MockID.dex, hostID: MockID.studio,
                         source: .telegram, createdAt: clock.ago(hours: 2), lastActivity: clock.ago(hours: 2),
                         preview: "Two things worth a look: demo-worker dropped off Tailscale at 03:12…",
                         project: nil, model: MockModels.hermes70, activeRunID: nil, isPinned: false, messageCount: 2),
            Conversation(id: "c-morning", title: "Morning report", profileID: MockID.dex, hostID: MockID.studio,
                         source: .routine, createdAt: clock.ago(hours: 3.3), lastActivity: clock.ago(hours: 3.2),
                         preview: "3 events today, 2 PRs waiting on review, clear and 18°C.",
                         project: nil, model: MockModels.hermes70, activeRunID: nil, isPinned: false, messageCount: 2),
            Conversation(id: "c-nightly", title: "Nightly research sweep", profileID: MockID.researcher, hostID: MockID.studio,
                         source: .routine, createdAt: clock.ago(hours: 9), lastActivity: clock.ago(hours: 8.9),
                         preview: "Run failed: OpenRouter returned 429 Too Many Requests.",
                         project: nil, model: MockModels.opus, activeRunID: nil, isPinned: false, messageCount: 2),
            Conversation(id: "c-papers", title: "This week in agent research", profileID: Profile.defaultID, hostID: MockID.studio,
                         source: .app, createdAt: clock.ago(days: 1.1), lastActivity: clock.ago(days: 1),
                         preview: "Five papers worth reading, starting with the tool-use credit assignment one.",
                         project: nil, model: MockModels.sonnet, activeRunID: nil, isPinned: false, messageCount: 4),
            Conversation(id: "c-kv", title: "Explain KV cache quantization", profileID: Profile.defaultID, hostID: MockID.studio,
                         source: .cli, createdAt: clock.ago(days: 2.2), lastActivity: clock.ago(days: 2.1),
                         preview: "KV cache quantization stores attention keys and values at lower precision…",
                         project: nil, model: MockModels.local, activeRunID: nil, isPinned: false, messageCount: 2),
            Conversation(id: "c-analyst", title: "Analyst", profileID: MockID.analyst, hostID: MockID.studio,
                         source: .app, createdAt: clock.ago(days: 9), lastActivity: clock.ago(minutes: 6),
                         preview: "Pull today's arXiv submissions and flag anything on KV compression.",
                         project: nil, model: MockModels.gpt, activeRunID: "r-arxiv", isPinned: false, messageCount: 16),
        ]
    }

    static func messages(_ clock: MockClock) -> [String: [Message]] {
        var result: [String: [Message]] = [:]

        // MARK: Researcher — benchmark (active run)
        result["c-researcher"] = [
            user("c-researcher", "Run the latency benchmark against OpenRouter, Nous Portal and the local LM Studio endpoint. 50 requests each, 1k-token prompts.", at: clock.ago(days: 1, hours: 0.4)),
            assistant("c-researcher", profile: MockID.researcher, at: clock.ago(days: 1, hours: 0.3), run: "r-bench-1", tools: [
                ToolCall(kind: .files, name: "read_file", summary: "Read bench.py", targets: ["bench.py"]),
                ToolCall(kind: .terminal, name: "terminal", summary: "Ran uv run bench.py",
                         input: "uv run bench.py --providers openrouter,nous,local --n 50 --prompt-tokens 1000",
                         output: "openrouter  50/50  ok\nnous        50/50  ok\nlocal       50/50  ok\nwrote results/2026-09-30.csv", duration: 412),
            ], """
            Benchmark finished. Raw results are in `results/2026-09-30.csv`.

            | Provider | p50 TTFT | p95 TTFT | Tokens/s |
            |:--|--:|--:|--:|
            | OpenRouter | 412 ms | 1.18 s | 86 |
            | Nous Portal | 368 ms | 0.94 s | 91 |
            | LM Studio (local) | 95 ms | 140 ms | 38 |

            Local wins on time-to-first-token by a wide margin, but throughput is under half. The OpenRouter p95 is noisy — **11 of 50** requests took longer than a second.

            Want me to dig into the p95 tail?
            """, extra: [.file(FileAttachment(id: "f-results", name: "2026-09-30.csv", byteCount: 18_432, fileExtension: "csv", path: "demo/provider-bench/results/2026-09-30.csv"))]),
            user("c-researcher", "Yes — break down the p95 tail by hour and check if it correlates with prompt length. Plot it.", at: clock.ago(seconds: 230)),
            Message(id: "m-bench-live", conversationID: "c-researcher", role: .assistant, createdAt: clock.ago(seconds: 222), parts: [.tools([
                        ToolCall(kind: .files, name: "read_file", summary: "Read AGENTS.md", targets: ["AGENTS.md"]),
                        ToolCall(kind: .files, name: "search_files", summary: "Searched repository", input: "p95|ttft", output: "14 matches in 5 files"),
                        ToolCall(kind: .files, name: "read_file", summary: "Opened benchmark results", targets: ["results/2026-09-30.csv"]),
                    ])], runID: "r-bench", status: .streaming),
        ]

        // MARK: Caddy — repo update waiting for approval
        result["c-caddy"] = [
            user("c-caddy", "What changed in the gateway reconnect fix?", at: clock.ago(days: 3)),
            assistant("c-caddy", profile: MockID.caddy, at: clock.ago(days: 3), run: "r-gateway", tools: [
                ToolCall(kind: .terminal, name: "terminal", summary: "Ran git log", input: "git log --oneline -5 -- gateway/", output: "a91c2e4 gateway: back off reconnects exponentially\n2f0d7b1 gateway: drop stale websocket on resume"),
            ], """
            Two commits:

            1. `a91c2e4` — reconnects now back off exponentially (250 ms → 8 s, with jitter) instead of retrying every 500 ms.
            2. `2f0d7b1` — on resume, the stale websocket is closed before a new one opens, which was the source of the duplicate deliveries.

            ```swift
            let delay = min(maxDelay, baseDelay * pow(2, Double(attempt)))
            try await Task.sleep(for: .seconds(delay * .random(in: 0.8...1.2)))
            ```
            """),
            user("c-caddy", "Pull latest, regenerate the API client from the new schema, and clear out the generated cache before rebuilding.", at: clock.ago(minutes: 12.2)),
            Message(id: "m-ios-live", conversationID: "c-caddy", role: .assistant, createdAt: clock.ago(minutes: 12), parts: [
                        .tools([
                            ToolCall(kind: .terminal, name: "terminal", summary: "Ran git pull --rebase", input: "git pull --rebase",
                                     output: "Updating 3f2a1c0..9be41d2\nFast-forward\n 12 files changed, 348 insertions(+), 97 deletions(-)", duration: 3.1),
                            ToolCall(kind: .files, name: "read_file", summary: "Read 3 files", targets: ["openapi.yaml", "Package.swift", "Makefile"]),
                            ToolCall(kind: .terminal, name: "terminal", summary: "Ran make generate", input: "make generate",
                                     output: "swift-openapi-generator: generated 41 files in Sources/HermesAPI", duration: 18.4),
                        ]),
                        .markdown("Pulled 12 changed files and regenerated the client (41 files in `Sources/HermesAPI`). Next I'll clear the stale generated cache so the rebuild doesn't pick up old types."),
                    ], runID: "r-ios", status: .streaming),
        ]

        // MARK: Dex — notes with file approval
        result["c-dex"] = [
            user("c-dex", "Remind me what's in the weekly template.", at: clock.ago(days: 2)),
            assistant("c-dex", profile: MockID.dex, at: clock.ago(days: 2), run: nil, tools: [
                ToolCall(kind: .files, name: "read_file", summary: "Read Templates/Weekly.md", targets: ["Templates/Weekly.md"]),
            ], """
            The weekly template has four sections:

            - **Highlights** — 3 bullets max
            - **Decisions** — with links to the meeting note
            - **Open loops** — anything waiting on someone
            - **Next week** — top priorities
            """),
            user("c-dex", "Consolidate this week's meeting notes into Weekly/2026-W40.md and update the index.", at: clock.ago(minutes: 25)),
            Message(id: "m-notes-live", conversationID: "c-dex", role: .assistant, createdAt: clock.ago(minutes: 24.8), parts: [
                        .tools([
                            ToolCall(kind: .files, name: "search_files", summary: "Found 9 meeting notes", input: "Meetings/2026-09-29…2026-10-03"),
                            ToolCall(kind: .files, name: "read_file", summary: "Read 9 files", targets: ["Meetings/2026-09-29 Infra sync.md", "Meetings/2026-09-30 Hermes roadmap.md", "Meetings/2026-10-01 Bench review.md"]),
                            ToolCall(kind: .files, name: "write_file", summary: "Created Weekly/2026-W40.md", targets: ["Weekly/2026-W40.md"]),
                        ]),
                        .markdown("Drafted `Weekly/2026-W40.md` from 9 meeting notes. Updating `Index.md` needs your approval because it also archives three meeting links."),
                    ], runID: "r-notes", status: .streaming),
        ]

        // MARK: Completed one-off coding run
        result["c-cleanup"] = [
            user("c-cleanup", "Find build scripts nobody calls anymore and remove them. Show me what you removed.", at: clock.ago(minutes: 56)),
            assistant("c-cleanup", profile: MockID.caddy, at: clock.ago(minutes: 48), run: "r-cleanup", tools: [
                ToolCall(kind: .files, name: "search_files", summary: "Searched 214 files", input: "scripts/", output: "4 scripts with no references"),
                ToolCall(kind: .terminal, name: "terminal", summary: "Ran git rm on 4 files", input: "git rm scripts/deploy-legacy.sh scripts/gen-sitemap.py scripts/sync-assets.sh scripts/old-lint.js"),
                ToolCall(kind: .files, name: "patch", summary: "Edited package.json", targets: ["package.json"]),
                ToolCall(kind: .terminal, name: "terminal", summary: "Ran npm run build", input: "npm run build", output: "✓ Completed in 14.2s", duration: 14.2),
            ], """
            Removed 4 unreferenced scripts:

            - `scripts/deploy-legacy.sh`
            - `scripts/gen-sitemap.py` — replaced by the Astro sitemap integration
            - `scripts/sync-assets.sh`
            - `scripts/old-lint.js`

            ```diff
            -    "prebuild": "sh scripts/sync-assets.sh",
            +    "prebuild": "astro check",
            ```

            The build passes. I committed on `chore/remove-stale-scripts` but didn't push.
            """),
        ]

        // MARK: Telegram-originated
        result["c-telegram"] = [
            user("c-telegram", "anything weird in the server alerts overnight?", at: clock.ago(hours: 2.05)),
            assistant("c-telegram", profile: MockID.dex, at: clock.ago(hours: 2), run: "r-alerts", tools: [
                ToolCall(kind: .terminal, name: "terminal", summary: "Ran journalctl on demo-worker", input: "ssh demo-worker journalctl -p warning --since -12h", status: .failed),
                ToolCall(kind: .terminal, name: "terminal", summary: "Read hermes-gateway logs", input: "tail -n 400 ~/.hermes/logs/gateway.log"),
            ], """
            Two things worth a look:

            1. **demo-worker** dropped off Tailscale at 03:12 and hasn't come back — I couldn't reach it to read its journal.
            2. `hermes-gateway` restarted twice (04:40 and 04:52), both out-of-memory while transcribing a voice note.

            Everything else was routine.
            """),
        ]

        // MARK: Routine output
        result["c-morning"] = [
            Message(conversationID: "c-morning", role: .system, createdAt: clock.ago(hours: 3.3), parts: [.event(SystemEvent(symbol: "calendar.badge.clock", text: "Started by routine “Morning report”"))]),
            assistant("c-morning", profile: MockID.dex, at: clock.ago(hours: 3.2), run: "r-morning", tools: [
                ToolCall(kind: .web, name: "web_search", summary: "Checked weather"),
                ToolCall(kind: .mcp, name: "github.list_pull_requests", summary: "Listed open pull requests"),
                ToolCall(kind: .messaging, name: "send_message", summary: "Sent to Telegram · Home"),
            ], """
            **Good morning.**

            - **Calendar:** Infra sync 10:00, dentist 13:30, Bench review 16:00
            - **Reviews:** 2 PRs waiting — `hermes-ios#41`, `hermes-docs#118`
            - **Weather:** clear, 18°C, light wind
            """),
        ]

        result["c-nightly"] = [
            Message(conversationID: "c-nightly", role: .system, createdAt: clock.ago(hours: 9), parts: [.event(SystemEvent(symbol: "calendar.badge.clock", text: "Started by routine “Nightly research sweep”"))]),
            Message(conversationID: "c-nightly", role: .assistant, createdAt: clock.ago(hours: 8.95), parts: [
                .tools([
                    ToolCall(kind: .web, name: "web_search", summary: "Searched 6 sources"),
                    ToolCall(kind: .web, name: "web_extract", summary: "Fetch failed", output: "HTTP 429 Too Many Requests (retry 3/3)", status: .failed),
                ]),
                .error(MessageError(title: "Run failed", detail: "OpenRouter returned 429 Too Many Requests after 3 retries. The sweep stopped before summarizing.", isRetryable: true)),
            ], runID: "r-nightly"),
        ]

        // MARK: Default profile
        result["c-papers"] = [
            user("c-papers", "Summarize this week's most interesting agent research. Keep it skimmable.", at: clock.ago(days: 1.1)),
            assistant("c-papers", profile: nil, at: clock.ago(days: 1.08), run: "r-papers", tools: [
                ToolCall(kind: .web, name: "web_search", summary: "Searched arXiv and Semantic Scholar", input: "LLM agents tool use since:7d"),
                ToolCall(kind: .browser, name: "browser_navigate", summary: "Visited 2 pages", targets: ["arxiv.org/list/cs.AI/recent", "huggingface.co/papers"]),
            ], """
            ## This week in agent research

            Five papers worth reading, in order:

            1. **Credit assignment for tool use** — rewards each tool call by its marginal effect on the final answer. Big gains on multi-step web tasks.
            2. **Memory that forgets on purpose** — learned eviction for long-running agents; beats summarization on 30-day tasks.
            3. **Skills as code** — agents that write and reuse their own procedures, similar to Hermes skills.
            4. **Small models, big plans** — a 3B planner paired with a large executor matches a single large model.
            5. **Evaluating steerability** — measures how well running agents accept mid-task corrections.

            > The common thread: agents are getting better at *managing their own context* rather than just using bigger windows.

            Want full citations or a deeper read on any of these?
            """),
            user("c-papers", "Chart how often each topic appeared.", at: clock.ago(days: 1.05)),
            assistant("c-papers", profile: nil, at: clock.ago(days: 1), run: nil, tools: [
                ToolCall(kind: .code, name: "execute_code", summary: "Ran plotting script", input: "python plot_topics.py"),
            ], "Memory and tool use dominate this week's submissions.", extra: [
                .image(ImageAttachment(id: "img-topics", name: "topics.png", source: .asset("MockChartTopics"), aspectRatio: 1.6, caption: "Agent paper topics, last 7 days")),
            ]),
        ]

        result["c-kv"] = [
            user("c-kv", "Explain KV cache quantization briefly, with a code example.", at: clock.ago(days: 2.2)),
            assistant("c-kv", profile: nil, at: clock.ago(days: 2.1), run: "r-kv", """
            KV cache quantization stores attention **keys and values** at lower precision so long contexts fit in memory.

            | Format | Bytes / value | Quality impact |
            |:--|--:|:--|
            | FP16 | 2 | Baseline |
            | INT8 | 1 | Negligible |
            | INT4 | 0.5 | Small, grows with context |

            ```python
            def quantize(x, bits=8):
                scale = x.abs().amax(dim=-1, keepdim=True) / (2 ** (bits - 1) - 1)
                q = torch.round(x / scale).to(torch.int8)
                return q, scale  # dequantize with q * scale
            ```

            Per-channel scales for keys and per-token scales for values tend to work best.
            """),
        ]

        result["c-analyst"] = [
            user("c-analyst", "What's the scoring rubric for paper triage?", at: clock.ago(days: 4.1)),
            assistant("c-analyst", profile: MockID.analyst, at: clock.ago(days: 4), run: nil, """
            | Criterion | Weight |
            |:--|--:|
            | Reproducibility | 0.4 |
            | Novelty | 0.3 |
            | Relevance to our stack | 0.3 |
            """),
            user("c-analyst", "Pull today's arXiv submissions and flag anything on KV compression.", at: clock.ago(minutes: 6.2)),
            Message(id: "m-arxiv-live", conversationID: "c-analyst", role: .assistant,
                    createdAt: clock.ago(minutes: 6), parts: [.tools([
                        ToolCall(kind: .web, name: "web_search", summary: "Searched arXiv (cs.CL, cs.LG)", input: "submitted:today"),
                        ToolCall(kind: .web, name: "web_extract", summary: "Fetched 38 submissions"),
                    ])], runID: "r-arxiv", status: .streaming),
        ]

        return result
    }

    // MARK: Message builders

    static func user(_ conversationID: String, _ text: String, at date: Date) -> Message {
        Message(conversationID: conversationID, role: .user, createdAt: date, parts: [.markdown(text)])
    }

    static func assistant(_ conversationID: String, profile: String?, at date: Date, run: String?, tools: [ToolCall] = [],
                          _ text: String, extra: [MessagePart] = []) -> Message {
        var parts: [MessagePart] = []
        if !tools.isEmpty { parts.append(.tools(tools)) }
        parts.append(.markdown(text))
        parts.append(contentsOf: extra)
        return Message(conversationID: conversationID, role: .assistant, createdAt: date, parts: parts, runID: run)
    }
}
