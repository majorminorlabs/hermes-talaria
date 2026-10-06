import SwiftUI
struct AgentModelPicker: View {
    var profile: Profile
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var models: [ModelRef] = []
    @State private var query = ""
    @State private var selected: ModelRef?
    @State private var nextAsk = false
    @State private var risk: RiskAction?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(Theme.failure) }
                if !environment.preferences.recentModels.isEmpty { Section("Recent") { ForEach(environment.preferences.recentModels.filter { models.contains($0) }) { model in Button(model.detailedLabel) { selected = model } } } }
                ForEach(Array(Set(models.map(\.provider))).sorted(), id: \.self) { provider in
                    Section(provider) {
                        ForEach(models.filter { $0.provider == provider && (query.isEmpty || $0.detailedLabel.localizedCaseInsensitiveContains(query)) }) { model in
                            Button { selected = model } label: { HStack { Text(model.displayName); Spacer(); if selected == model || selected == nil && profile.model.id == model.id { Image(systemName: "checkmark") } } }
                        }
                    }
                }
                if let selected {
                    Section("Use \(selected.displayName) for…") {
                        Button { nextAsk = false } label: { Label("\(profile.name)'s default", systemImage: nextAsk ? "circle" : "largecircle.fill.circle") }.accessibilityIdentifier("scope-agent-default")
                        Text("New work and its chat use it from the next turn. Hermes Desktop sees the change.").font(.footnote).foregroundStyle(.secondary)
                        if environment.connection.supports(.botThreads) || profile.isBotMode != true {
                            Button { nextAsk = true } label: { Label("My next ask only", systemImage: nextAsk ? "largecircle.fill.circle" : "circle") }.accessibilityIdentifier("scope-next-ask")
                        }
                        Button("Apply") {
                            if nextAsk { environment.router.askSeed = AskSeed(agentID: profile.id, model: selected); dismiss() }
                            else { risk = RiskAction(verb: "Change Default", effect: "New work uses \(selected.displayName) from the next turn. Hermes Desktop sees the change.", target: profile.name) { try await apply(selected, confirmed: false) } }
                        }.disabled(!environment.connection.connection.isConnected)
                    }
                }
            }.navigationTitle("Model").searchable(text: $query)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.presentationDetents([.large])
        .sheet(item: $risk) { RiskConfirmSheet(action: $0) }
        .task {
            do { models = try await environment.client.profiles.botInventory(profileID: profile.id).providers.flatMap(\.models) }
            catch { models = environment.connection.runOptions.models; if models.isEmpty { self.error = "Couldn't load models from Studio." } }
        }
    }
    private func apply(_ model: ModelRef, confirmed: Bool) async throws {
        environment.preferences.rememberModel(model)
        do { try await environment.agentModels.change(profile: profile, to: model, confirmed: confirmed, environment: environment); environment.toasts.show("\(profile.name) now uses \(model.displayName)"); dismiss() }
        catch HermesError.botModelConfirmationText(let message) { requireHold(model, message: message) }
        catch HermesError.botModelConfirmation { requireHold(model, message: "Hermes requires confirmation before switching to this model.") }
    }
    private func requireHold(_ model: ModelRef, message: String) {
            risk = nil
            Task { try? await Task.sleep(for: .milliseconds(300)); risk = RiskAction(verb: "Use \(model.displayName)", effect: message, target: profile.name, high: true) { try await apply(model, confirmed: true) } }
    }
}
