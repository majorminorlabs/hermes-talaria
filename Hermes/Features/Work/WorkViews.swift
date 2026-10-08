import SwiftUI

struct ConnectionChip: View {
    var body: some View {
        NavigationLink(value: Route.studio) {
            Image("TalariaMark").resizable().scaledToFit().frame(width: 26, height: 26)
                .frame(width: 44, height: 44)
        }.accessibilityLabel("Talaria settings and Studio").accessibilityIdentifier("talaria-settings")
    }
}
struct WorkItemRow: View {
    var item: WorkItem
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var risk: RiskAction?
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            if item.isUnread { Circle().fill(.tint).frame(width: 8, height: 8).accessibilityLabel("Unread") }
            ProfileAvatar(profile: environment.profiles.identity(item.agentID), size: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.body.weight(.semibold)).lineLimit(2)
                Text(stateLine).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(2)
                Text("\(environment.profiles.name(item.agentID)) · \(item.source)")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            RelativeTimeText(date: item.lastActivity).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(environment.profiles.name(item.agentID)). \(stateLine). \(item.isUnread ? "Unread" : "Read")")
        .accessibilityAction(named: item.isUnread ? "Mark read" : "Mark unread") { environment.seen.mark(item.id, at: item.isUnread ? .now : .distantPast, host: environment.connection.activeHostID) }
        .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin") { if item.kind == .conversation { environment.toasts.perform { try await environment.conversations.setPinned(!item.isPinned, item.id) } } }
        .accessibilityAction(named: "Archive") { if item.canArchive { environment.toasts.perform { try await environment.conversations.setArchived(!item.isArchived, item.id) } } }
        .accessibilityAction(named: "Stop") { if let run = item.runs.first(where: { $0.canStop }), environment.connection.connection.isConnected { risk = RiskAction(verb: "Stop", effect: "Stops all of this work. Work already done stays.", target: item.title) { try await environment.activity.stop(run.id) } } }
        .sheet(item: $risk) { RiskConfirmSheet(action: $0) }
    }
    private var stateLine: String {
        switch item.state {
        case .needsYou: environment.needsYou.all.first { $0.workItemID == item.id }?.request ?? "Needs you"
        case .working: item.runs.first.map { "\($0.displayState(isLive: environment.connection.connection.isConnected).label) · \($0.currentAction ?? "Working")" } ?? "Working"
        case .failed: "Failed: \(item.latestResultSnippet)"
        case .unknown: "? Outcome unknown"
        case .done: "✓ \(item.latestResultSnippet)"
        case .idle: item.latestResultSnippet
        }
    }
}
struct NowView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var expanded = false
    @State private var risk: RiskAction?
    var body: some View {
        ScrollViewReader { proxy in
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            List {
                if !environment.connection.connection.isConnected || !status.isEmpty {
                    Section {
                        if environment.connection.connection.isConnected {
                            Text(status).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        } else {
                            ConnectionNoticeSection()
                            Button("Retry") { Task { await environment.connection.reconnect(); await environment.refreshAll() } }
                        }
                    }
                }
                if environment.connection.activeHost == nil { Section { UnpairedWelcome() } }
                if environment.outbox.hasPending(host: environment.connection.activeHostID) {
                    Section { NavigationLink(value: Route.outbox) { Label(environment.outbox.summary(host: environment.connection.activeHostID), systemImage: "tray") } } header: { SectionHeader("Outbox") }
                }
                if environment.needsYou.visible.isEmpty {
                    Label(working.isEmpty && done.isEmpty ? "Nothing needs you. Hermes is idle." : "Nothing needs you", systemImage: "checkmark")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Section {
                        ForEach(Array(environment.needsYou.groups.prefix(expanded ? .max : 3)), id: \.first!.id) { group in NeedsYouGroupCard(items: group).id(group.first!.id) }
                        if !expanded && environment.needsYou.groups.count > 3 { Button("\(environment.needsYou.groups.count - 3) more") { expanded = true } }
                    } header: { SectionHeader("Needs You") }
                }
                if !environment.needsYou.snoozed.isEmpty {
                    NavigationLink(laterLabel, value: Route.snoozed)
                }
                if !working.isEmpty {
                    Section { ForEach(working.prefix(5)) { row($0) }; if working.count > 5 { Button("All working") { environment.router.selectedTab = .threads } } } header: { SectionHeader("Working") }
                }
                if !done.isEmpty || !savedCaptures.isEmpty {
                    Section { ForEach(done.prefix(5)) { row($0) }; ForEach(savedCaptures.prefix(5)) { capture in NavigationLink { CaptureDetailView(capture: capture) } label: { Label("Captured: " + String(capture.text.prefix(100)), systemImage: "checkmark") } }; Button("Earlier") { environment.router.selectedTab = .threads } } header: { SectionHeader("Done") }
                }
                if !upcoming.isEmpty {
                    Section {
                        ForEach(upcoming.prefix(3)) { routine in NavigationLink(value: Route.routine(routine.id)) { RoutineRow(routine: routine) } }
                        NavigationLink("All", value: Route.scheduled)
                    } header: { SectionHeader("Next Up") }
                }
            }.listStyle(.plain).listSectionSpacing(.compact)
        }
        .onChange(of: environment.router.needsFocusID) { _, _ in focusNeeds(using: proxy) }
        .onChange(of: environment.needsYou.visible.map(\.id)) { _, _ in focusNeeds(using: proxy) }
        .onAppear { focusNeeds(using: proxy) }
        }
        .sheet(item: $risk) { RiskConfirmSheet(action: $0) }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ConnectionChip() }
            ToolbarItem(placement: .topBarTrailing) { AskToolbarButton() }
        }
        .refreshable { await environment.refreshAll() }
    }
    private func focusNeeds(using proxy: ScrollViewProxy) {
        guard let id = environment.router.needsFocusID, let group = environment.needsYou.groups.first(where: { $0.contains(where: { $0.id == id }) }) else { return }
        expanded = true
        Task { try? await Task.sleep(for: .milliseconds(200)); proxy.scrollTo(group.first!.id, anchor: .center); environment.router.needsFocusID = nil }
    }
    private var working: [WorkItem] { environment.work.items.filter { !$0.isArchived && ($0.state == .working || $0.state == .needsYou && $0.runs.contains(where: \.state.isActive)) } }
    private var done: [WorkItem] { environment.work.items.filter { !$0.isArchived && $0.state == .done && $0.lastActivity > .now.addingTimeInterval(-86400) }.sorted { $0.isUnread && !$1.isUnread } }
    private var laterLabel: String {
        let parked = environment.snoozes.values(host: environment.connection.activeHostID)
        let deskCount = environment.needsYou.snoozed.filter { if case .atDesk = parked[$0.id] { true } else { false } }.count
        return "Later (\(environment.needsYou.snoozed.count))" + (deskCount == 0 ? "" : " · \(deskCount) at your desk")
    }
    private var savedCaptures: [CaptureRecord] { environment.outbox.captures.filter { $0.hostID == environment.connection.activeHostID && $0.state == .confirmed && $0.context["thread_id"] != nil && $0.createdAt > .now.addingTimeInterval(-86400) } }
    private var upcoming: [Routine] { environment.routines.sorted.filter { $0.isEnabled && ($0.nextRunAt ?? .distantFuture) < .now.addingTimeInterval(86400) } }
    /// Counts only; the empty Needs You row already says "Nothing needs you".
    private var status: String {
        let count = environment.needsYou.actionableCount
        return [count == 0 ? nil : "\(count) need you", working.isEmpty ? nil : "\(working.count) working"].compactMap { $0 }.joined(separator: " · ")
    }
    private func row(_ item: WorkItem) -> some View { NavigationLink(value: item.route) { WorkItemRow(item: item) }.swipeActions {
        if let run = item.runs.first(where: { $0.canStop }), environment.connection.connection.isConnected {
            Button("Stop", role: .destructive) { risk = RiskAction(verb: "Stop", effect: "Stops all of this work. Work already done stays.", target: item.title) { try await environment.activity.stop(run.id) } }
        }
    } }
}
struct ThreadsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var query = ""
    @State private var scope = "All"
    @State private var archived = false
    @State private var agents: Set<String> = []
    @State private var sources: Set<String> = []
    @State private var bridgeMatches: [Conversation] = []
    @State private var searchError: String?
    var body: some View {
        List {
            ConnectionNoticeSection()
            if filtered.isEmpty { ContentUnavailableView("No threads yet", systemImage: "bubble.left.and.text.bubble.right", description: Text("Ask Hermes something. Work you start here, on your Mac or from routines shows up in this list.")) }
            if !query.isEmpty {
                Section("On Hermes") {
                    ForEach(bridgeMatches.filter { c in !filtered.contains(where: { $0.id == c.id }) }) { c in NavigationLink(c.title, value: Route.thread(c.id)) }
                    if let searchError { Text(searchError).font(.footnote).foregroundStyle(Theme.secondaryText) }
                }
            }
            ForEach(sections, id: \.0) { title, items in
                Section(title) {
                    ForEach(items) { item in
                        NavigationLink(value: item.route) { WorkItemRow(item: item) }
                        .swipeActions(edge: .leading) {
                            Button(item.isUnread ? "Mark read" : "Mark unread") { environment.seen.mark(item.id, at: item.isUnread ? .now : .distantPast, host: environment.connection.activeHostID) }
                            if item.kind == .conversation { Button(item.isPinned ? "Unpin" : "Pin") { environment.toasts.perform { try await environment.conversations.setPinned(!item.isPinned, item.id) } }.tint(.gray) }
                        }
                        .swipeActions {
                            if item.canArchive { Button(item.isArchived ? "Unarchive" : "Archive") { environment.toasts.perform { try await environment.conversations.setArchived(!item.isArchived, item.id) } }.tint(.gray) }
                        }
                    }
                }
            }
        }.listStyle(.plain)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search threads")
        .task(id: query) {
            guard !query.isEmpty, environment.connection.connection.isConnected else { bridgeMatches = []; return }
            do { try await Task.sleep(for: .milliseconds(350)); let matches = try await environment.client.conversations.searchConversations(query); guard !Task.isCancelled else { return }; bridgeMatches = matches; searchError = nil }
            catch { if !Task.isCancelled { searchError = "Couldn't search Hermes. Local matches remain available." } }
        }
        .searchScopes($scope) { ForEach(["All", "Active", "Needs You", "Unread"], id: \.self) { Text($0).tag($0) } }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ConnectionChip() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Show Archived", isOn: $archived)
                    Menu("Agent") { ForEach(environment.profiles.sorted) { p in Button { toggle(p.id, in: &agents) } label: { Label(p.name, systemImage: agents.contains(p.id) ? "checkmark" : "person") } } }
                    Menu("Source") { ForEach(Array(Set(environment.work.items.map(\.source))).sorted(), id: \.self) { source in Button { toggle(source, in: &sources) } label: { Label(source, systemImage: sources.contains(source) ? "checkmark" : "circle") } } }
                    if environment.connection.supports(.kanban) { NavigationLink("Board", value: Route.board) }
                } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44) }
            }
        }.refreshable { await environment.refreshAll() }
    }
    private func toggle(_ id: String, in set: inout Set<String>) { if !set.insert(id).inserted { set.remove(id) } }
    private var filtered: [WorkItem] { environment.work.items.filter { item in
        (archived || !item.isArchived) && (agents.isEmpty || agents.contains(item.agentID ?? "default")) && (sources.isEmpty || sources.contains(item.source)) &&
        (query.isEmpty || item.title.localizedCaseInsensitiveContains(query) || item.latestResultSnippet.localizedCaseInsensitiveContains(query)) &&
        (scope == "All" || scope == "Unread" && item.isUnread || scope == "Needs You" && item.state == .needsYou || scope == "Active" && [.working,.needsYou].contains(item.state))
    } }
    private var sections: [(String,[WorkItem])] {
        if !query.isEmpty { return [("Matches",filtered)] }
        var remaining = filtered
        var groups: [(String,[WorkItem])] = []
        let buckets: [(String,(WorkItem)->Bool)] = [("Pinned", { $0.isPinned }), ("Active", { [.needsYou,.working].contains($0.state) }), ("Today", { Calendar.current.isDateInToday($0.lastActivity) }), ("Yesterday", { Calendar.current.isDateInYesterday($0.lastActivity) }), ("This Week", { $0.lastActivity > .now.addingTimeInterval(-604800) }), ("Earlier", { _ in true })]
        for (title, predicate) in buckets { let items = remaining.filter(predicate); remaining.removeAll(where: predicate); if !items.isEmpty { groups.append((title,items)) } }
        return groups
    }
}
struct SnoozedView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View { List(environment.needsYou.snoozed) { item in
        NeedsYouCard(item: item).swipeActions { Button("Unsnooze") { environment.snoozes.set(nil, id: item.id, host: environment.connection.activeHostID) }; Button("Done at desk") { environment.snoozes.dismiss(item.id, host: environment.connection.activeHostID) } }
    }.navigationTitle("Later") }
}
