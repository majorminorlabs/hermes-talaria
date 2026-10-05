import Foundation

/// Request lifecycle for a store or screen. Data is held separately so a
/// failed refresh can keep showing last-known values.
enum LoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(HermesError)

    var isLoading: Bool { self == .loading }

    var error: HermesError? {
        if case .failed(let error) = self { return error }
        return nil
    }
}

extension HermesError {
    /// Normalizes any thrown error. Returns nil for cancellation.
    static func from(_ error: any Error) -> HermesError? {
        if error is CancellationError { return nil }
        if let error = error as? HermesError { return error }
        return .rejected(error.localizedDescription)
    }
}

/// A single fetched value with load state, for screens that don't need a
/// dedicated store (memory, skills, usage, …).
@Observable
final class Resource<Value> {
    private(set) var value: Value?
    private(set) var phase: LoadPhase = .idle
    private(set) var updatedAt: Date?

    init(_ value: Value? = nil) {
        self.value = value
    }

    // Swift 6.3.3 crashes in EarlyPerfInliner for this generic observable
    // destructor under -O. Keep the workaround scoped to destruction only.
    @_optimize(none) deinit {}

    func load(_ fetch: () async throws -> Value) async {
        phase = .loading
        do {
            value = try await fetch()
            updatedAt = .now
            phase = .loaded
        } catch {
            if let error = HermesError.from(error) { phase = .failed(error) } else { phase = value == nil ? .idle : .loaded }
        }
    }

    /// Local optimistic edit after a successful mutation.
    func update(_ transform: (inout Value) -> Void) {
        guard var value else { return }
        transform(&value)
        self.value = value
    }
}
