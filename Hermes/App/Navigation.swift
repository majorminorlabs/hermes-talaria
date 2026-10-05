import SwiftUI

enum AppTab: Hashable {
    case home, chat, tasks, bots, more
}

/// Every pushable destination. All tabs share one destination table so any
/// screen (Run Detail, a conversation, a profile…) can be reached from anywhere.
enum Route: Hashable {
    case run(String)
    case approval(String)
    case conversation(String)
    case newConversation(NewChatSeed)
    case task(String)
    case routine(String)
    case profile(String)
    case hosts
    case host(String)
    case usage
    case memory
    case memoryEntry(MemoryEntry)
    case skills
    case skill(Skill)
    case tools
    case mcp
    case mcpServer(MCPServer)
    case integrations
    case logs
    case settings
    case capabilities
}

struct NewChatSeed: Hashable {
    var profileID: String?
    var id = UUID()
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var homePath: [Route] = []
    var chatPath: [Route] = []
    var tasksPath: [Route] = []
    var botsPath: [Route] = []
    var morePath: [Route] = []
    /// Lets other screens deep-link into a Tasks segment.
    var tasksSegment: TasksSegment = .running

    /// Push onto the current tab's stack.
    func open(_ route: Route) {
        switch selectedTab {
        case .home: homePath.append(route)
        case .chat: chatPath.append(route)
        case .tasks: tasksPath.append(route)
        case .bots: botsPath.append(route)
        case .more: morePath.append(route)
        }
    }

    /// Jump to Chat and start a new conversation, optionally with a profile.
    func startNewChat(profileID: String? = nil) {
        selectedTab = .chat
        chatPath = [.newConversation(NewChatSeed(profileID: profileID))]
    }

    func showTasks(_ segment: TasksSegment) {
        tasksSegment = segment
        tasksPath = []
        selectedTab = .tasks
    }

    func openConversation(_ id: String) {
        selectedTab = .chat
        chatPath = [.conversation(id)]
    }

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: {
                switch tab {
                case .home: self.homePath
                case .chat: self.chatPath
                case .tasks: self.tasksPath
                case .bots: self.botsPath
                case .more: self.morePath
                }
            },
            set: { newValue in
                switch tab {
                case .home: self.homePath = newValue
                case .chat: self.chatPath = newValue
                case .tasks: self.tasksPath = newValue
                case .bots: self.botsPath = newValue
                case .more: self.morePath = newValue
                }
            }
        )
    }
}

/// Transient, non-blocking feedback ("Instruction sent", errors).
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var symbol: String
        var isError: Bool
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill") {
        present(Toast(message: message, symbol: symbol, isError: false))
    }

    func show(error: any Error) {
        guard let error = HermesError.from(error) else { return }
        present(Toast(message: error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true))
    }

    /// Runs an async action, showing `success` or the error as a toast.
    func perform(success: String? = nil, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                if let success { show(success) }
            } catch {
                show(error: error)
            }
        }
    }

    private func present(_ toast: Toast) {
        current = toast
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(toast.isError ? 4 : 2.2))
            guard !Task.isCancelled else { return }
            current = nil
        }
    }
}
