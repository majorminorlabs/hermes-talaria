import Foundation

nonisolated struct AgentModelChange: Codable, Equatable {
    var previous: ModelRef
    var applied: ModelRef
    var changedAt: Date
}
@Observable final class AgentModelStore {
    let defaults: UserDefaults
    private(set) var revision = 0
    init(defaults: UserDefaults) { self.defaults = defaults }
    private func key(host: String, agent: String) -> String { "vnext.model.\(host).\(agent)" }
    func note(host: String, agent: String) -> AgentModelChange? {
        _ = revision
        guard let data = defaults.data(forKey: key(host: host,agent: agent)) else { return nil }
        return try? JSONDecoder().decode(AgentModelChange.self, from: data)
    }
    func dismiss(host: String, agent: String) { defaults.removeObject(forKey: key(host: host,agent: agent)); revision += 1 }
    func change(profile: Profile, to model: ModelRef, confirmed: Bool, environment: AppEnvironment) async throws {
        try await environment.profiles.update(profile.id, changes: ProfileChanges(model: model, confirmExpensiveModel: confirmed))
        guard let actual = environment.profiles.profile(profile.id), actual.model.id == model.id, actual.model.provider == model.provider else { throw HermesError.rejected("Studio did not confirm the selected model") }
        let note = AgentModelChange(previous: profile.model, applied: actual.model, changedAt: .now)
        defaults.set(try JSONEncoder().encode(note), forKey: key(host: environment.connection.activeHostID, agent: profile.id)); revision += 1
    }
    func revert(profile: Profile, confirmed: Bool, environment: AppEnvironment) async throws {
        await environment.profiles.loadProfile(profile.id)
        guard let current = environment.profiles.profile(profile.id),
              let note = note(host: environment.connection.activeHostID, agent: profile.id), current.model.id == note.applied.id && current.model.provider == note.applied.provider else { throw HermesError.rejected("Changed on another device. Refresh the Agent first.") }
        try await change(profile: current, to: note.previous, confirmed: confirmed, environment: environment)
        dismiss(host: environment.connection.activeHostID, agent: profile.id)
    }
}
