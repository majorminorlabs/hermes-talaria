import SwiftUI

enum AppTab: Hashable { case now, threads, agents }
struct AskSeed: Identifiable, Hashable {
    var id = UUID()
    var agentID: String? = nil
    var text = ""
    var model: ModelRef? = nil
    var voice = false
}
struct CaptureSeed: Identifiable, Hashable {
    var id = UUID()
    var text = ""
    var voice = false
}

/// Every pushable destination. All tabs share one destination table so any
/// screen (Run Detail, a conversation, a profile…) can be reached from anywhere.
enum Route: Hashable {
    case run(String)
    case thread(String)
    case agent(String)
    case board, scheduled, studio, outbox, snoozed
    case approval(String)
    case conversation(String)
    case newConversation(NewChatSeed)
    case task(String)
    case routine(String)
    case profile(String)
    case hosts
    case host(String)
    case usage
    case skills
    case skill(Skill)
    case tools
    case mcp
    case mcpServer(MCPServer)
    case settings
    case capabilities
}

struct NewChatSeed: Hashable {
    var profileID: String?
    var id = UUID()
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .now
    var nowPath: [Route] = []
    var threadsPath: [Route] = []
    var agentsPath: [Route] = []
    var askSeed: AskSeed?
    var captureSeed: CaptureSeed?
    var heldVoiceAsk: AskSeed?
    var heldVoiceCapture = false
    /// Window frame of the button being held, so the voice card grows out of it.
    var heldVoiceAnchor: CGRect?
    var needsFocusID: String?
    var stepsRunID: String?
    func open(_ route: Route) {
        switch selectedTab {
        case .now: nowPath.append(route)
        case .threads: threadsPath.append(route)
        case .agents: agentsPath.append(route)
        }
    }
    func openConversation(_ id: String) { open(.thread(id)) }
    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: {
            switch tab { case .now: self.nowPath; case .threads: self.threadsPath; case .agents: self.agentsPath }
        }, set: { value in
            switch tab { case .now: self.nowPath = value; case .threads: self.threadsPath = value; case .agents: self.agentsPath = value }
        })
    }
    func handle(_ url: URL) {
        guard url.scheme == "talaria" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
        switch url.host {
        case "threads": selectedTab = .threads; threadsPath = []
        case "now": selectedTab = .now; nowPath = []
        case "thread":
            if let id = parts.first { selectedTab = .now; nowPath = [.thread(id)]; if parts.last == "steps" { stepsRunID = value("run") } }
        case "agent": if let id = parts.first { selectedTab = .agents; agentsPath = [.agent(id)] }
        case "ask": askSeed = AskSeed(agentID: value("agent"), text: value("text") ?? "", voice: parts.first == "voice")
        case "capture": captureSeed = CaptureSeed(text: value("text") ?? "", voice: parts.first == "voice")
        case "studio": open(.studio)
        case "needs": selectedTab = .now; nowPath = []; needsFocusID = parts.first
        default: break
        }
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
        var actionTitle: String? = nil
    }

    private(set) var current: Toast?
    private(set) var action: (() -> Void)?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill", actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.action = action
        present(Toast(message: message, symbol: symbol, isError: false, actionTitle: actionTitle))
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
            try? await Task.sleep(for: .seconds(toast.isError || toast.actionTitle != nil ? 4 : 2.2))
            guard !Task.isCancelled else { return }
            current = nil
        }
    }
}
