import SwiftUI

extension View {
    /// Registers the shared destination table on a navigation stack.
    func routeDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            RouteDestination(route: route)
        }
    }

    /// A bar pinned under the navigation bar, using the system scroll-edge
    /// treatment where available.
    @ViewBuilder
    func pinnedTopBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top) { content() }
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                content().background(.bar)
            }
        }
    }
}

struct RouteDestination: View {
    var route: Route

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        switch route {
        case .run(let id):
            RunThreadDestination(runID: id)
        case .board: KanbanView()
        case .scheduled: ScheduledView()
        case .studio: MoreView()
        case .outbox: OutboxView()
        case .snoozed: SnoozedView()
        case .approval(let id):
            ApprovalDetailView(approvalID: id)
        case .thread(let id), .conversation(let id):
            if id.hasPrefix("task:") { TaskDetailView(taskID: String(id.dropFirst(5))) }
            else { ConversationView(model: environment.makeConversationModel(conversationID: id, profileID: nil)) }
        case .newConversation(let seed):
            ConversationView(model: environment.makeConversationModel(conversationID: nil, profileID: seed.profileID))
                .id(seed.id)
        case .task(let id):
            TaskDetailView(taskID: id)
        case .routine(let id):
            RoutineDetailView(routineID: id)
        case .agent(let id), .profile(let id):
            ProfileDetailView(profileID: id)
        case .hosts:
            HostsView()
        case .host(let id):
            HostDetailView(hostID: id)
        case .usage:
            UsageView()
        case .skills:
            SkillsView()
        case .skill(let skill):
            SkillDetailView(skill: skill)
        case .tools:
            ToolsView()
        case .mcp:
            MCPView()
        case .mcpServer(let server):
            MCPServerDetailView(server: server)
        case .settings:
            SettingsView()
        case .capabilities:
            CapabilitiesView()
        }
    }
}
