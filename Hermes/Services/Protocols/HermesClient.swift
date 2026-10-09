import Foundation

/// The full set of services the UI talks to.
///
/// Topology: iPhone → Tailscale → `hermes-mobile-bridge` → Hermes on the host.
/// Views and stores depend only on these protocols. `HermesClient.mock(_:)`
/// wires the in-memory simulator; `BridgeHermesClient.client` supplies the
/// production services.
struct HermesClient {
    var hosts: any HostService
    var home: any HomeService
    var events: any HermesEventStream
    var conversations: any ConversationService
    var runs: any RunService
    var profiles: any ProfileService
    var tasks: any TaskService
    var schedules: any ScheduleService
    var memory: any MemoryService
    var skills: any SkillService
    var tools: any ToolService
    var integrations: any IntegrationService
    var usage: any UsageService
    var logs: any LogService
}

/// Errors any service may surface. The bridge client maps transport errors
/// into these.
nonisolated enum HermesError: LocalizedError, Equatable, Sendable {
    case bridgeUnreachable
    case hermesOffline
    case unauthorized
    case unsupported(HermesCapability)
    case notFound
    case staleAttention
    case rejected(String)
    case botModelConfirmation
    case botModelConfirmationText(String)
    case timeout
    case commandUncertain(UUID?)
    case resyncRequired(String)

    var errorDescription: String? {
        switch self {
        case .bridgeUnreachable: "Can't reach your Mac"
        case .hermesOffline: "Hermes isn't responding"
        case .unauthorized: "Pairing required"
        case .unsupported(let capability): "\(capability.label) isn't available on this host"
        case .staleAttention: "No longer pending. Refreshed."
        case .notFound: "Not found"
        case .botModelConfirmation: "Hermes requires confirmation before switching to this model."
        case .botModelConfirmationText(let message): message
        case .rejected(let reason): reason
        case .timeout: "The request timed out"
        case .resyncRequired: "Catching up with Hermes. Refreshing."
        case .commandUncertain: "Talaria couldn't confirm that this went through."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .bridgeUnreachable: "Check that the Mac Studio is awake and on your tailnet, and that the Hermes bridge is running."
        case .hermesOffline: "Your Mac is reachable, but Hermes may have stopped."
        case .unauthorized: "Pair this iPhone again in Studio › Hosts."
        case .unsupported: "Updating Hermes or its bridge on the Mac may enable this."
        case .notFound: "It may have been removed on your Mac."
        case .staleAttention, .rejected, .botModelConfirmation, .botModelConfirmationText: nil
        case .timeout: "Try again in a moment."
        case .resyncRequired: nil
        case .commandUncertain: "Don't repeat it yet. It may already be running on your Mac. Refresh first."
        }
    }

    /// Errors that mean "you're looking at cached data", as opposed to a failed action.
    var isConnectivity: Bool {
        switch self {
        case .bridgeUnreachable, .hermesOffline, .unauthorized, .timeout: true
        default: false
        }
    }
}

// MARK: - Event stream

/// Opaque position in the bridge's event log. The app stores the last cursor
/// it processed and hands it back on reconnect to replay what it missed.
nonisolated struct EventCursor: Hashable, Codable, Sendable {
    let value: String
}

nonisolated struct HermesEventEnvelope: Sendable {
    var cursor: EventCursor
    var event: HermesEvent
}

/// One multiplexed feed of everything that changes on the host.
protocol HermesEventStream: AnyObject, Sendable {
    /// Live events, preceded by a replay of everything after `cursor` when
    /// one is given and the host supports `runReplay`. If the cursor is too
    /// old to replay, the stream starts with `.resyncRequired`.
    func subscribe(after cursor: EventCursor?) -> AsyncStream<HermesEventEnvelope>
    func acknowledge(_ cursor: EventCursor) async
}

extension HermesEventStream {
    func acknowledge(_ cursor: EventCursor) async {}
}

nonisolated indirect enum HermesEvent: Sendable {
    case batch([HermesEvent])
    case checkpoint
    case hostStatus(HostStatus)
    case runUpserted(Run)
    case approvalUpserted(ApprovalRequest)
    case approvalResolved(approvalID: String, decision: ApprovalDecision?)
    case conversationUpserted(Conversation)
    case conversationRemoved(String)
    case messageUpserted(Message)
    case transcriptReplaced(conversationID: String, messages: [Message])
    case profileUpserted(Profile)
    case taskUpserted(HermesTask)
    case routineUpserted(Routine)
    case routineRemoved(String)
    case log(LogEntry)
    /// Replay isn't possible from the stored cursor; refetch everything.
    case resyncRequired
}
