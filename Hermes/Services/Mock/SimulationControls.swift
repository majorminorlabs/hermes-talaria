import Foundation

/// Fan-out of one event source to many `AsyncStream` subscribers.
final class EventBroadcaster<Element: Sendable> {
    // Same Swift 6.3.3 generic-destructor optimizer workaround as Resource.
    @_optimize(none) deinit {}

    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

    /// A new subscription. `prefix` is delivered before any live element.
    func stream(prefix: [Element] = []) -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingNewest(1024))
        for element in prefix { continuation.yield(element) }
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[id] = nil }
        }
        return stream
    }

    func send(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }
}

/// Simulates the bridge's ordered, replayable event log.
final class MockEventLog {
    private var sequence = 0
    private var buffer: [HermesEventEnvelope] = []
    private let capacity = 2000
    private let broadcaster = EventBroadcaster<HermesEventEnvelope>()

    func publish(_ event: HermesEvent) {
        sequence += 1
        let envelope = HermesEventEnvelope(cursor: EventCursor(value: String(sequence)), event: event)
        buffer.append(envelope)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
        broadcaster.send(envelope)
    }

    func subscribe(after cursor: EventCursor?, replayEnabled: Bool) -> AsyncStream<HermesEventEnvelope> {
        guard let cursor, let position = Int(cursor.value) else { return broadcaster.stream() }
        let oldest = buffer.first.flatMap { Int($0.cursor.value) } ?? sequence + 1
        if !replayEnabled || position < oldest - 1 {
            let resync = HermesEventEnvelope(cursor: EventCursor(value: String(sequence)), event: .resyncRequired)
            return broadcaster.stream(prefix: [resync])
        }
        let missed = buffer.filter { (Int($0.cursor.value) ?? 0) > position }
        return broadcaster.stream(prefix: missed)
    }
}

/// Developer knobs for the simulated host, surfaced in Settings › Simulation.
/// Only exists when the app runs against `MockHermesBackend`.
@Observable
final class SimulationControls {
    var latency: SimulatedLatency = .fast
    var failRequests = false
    var emptyData = false
    var runSpeed: Double = 1
    var disabledCapabilities: Set<HermesCapability> = [] {
        didSet { onCapabilitiesChanged?() }
    }

    @ObservationIgnored var onCapabilitiesChanged: (() -> Void)?
}

enum SimulatedLatency: String, CaseIterable, Identifiable {
    case instant, fast, slow

    var id: String { rawValue }

    var seconds: Double {
        switch self {
        case .instant: 0
        case .fast: 0.25
        case .slow: 1.8
        }
    }

    var label: String {
        switch self {
        case .instant: "Instant"
        case .fast: "Fast"
        case .slow: "Slow"
        }
    }
}
