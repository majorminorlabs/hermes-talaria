import SwiftUI

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppPreferences.self) private var preferences
    @Environment(ConnectionStore.self) private var connection
    @Environment(ProfileStore.self) private var profiles
    @Environment(ToastCenter.self) private var toasts
    @State private var cacheSize = 0

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Picker("Host", selection: Binding(
                    get: { connection.activeHostID },
                    set: { id in Task { await connection.switchHost(to: id) } })) {
                    ForEach(connection.hosts) { Text($0.name).tag($0.id) }
                }
                if connection.supports(.profiles) {
                    Picker("Profile for new chats", selection: $preferences.defaultProfileID) {
                        Text("Hermes (default)").tag(String?.none)
                        ForEach(profiles.bots) { Text($0.name).tag(String?.some($0.id)) }
                    }
                }
                Picker("Reasoning", selection: $preferences.defaultReasoning) {
                    ForEach(ReasoningLevel.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                SectionHeader("Defaults")
            }

            Section {
                Toggle("Simulation mode after relaunch", isOn: Binding(
                    get: { UserDefaults.standard.bool(forKey: "app.backendSimulation") },
                    set: { UserDefaults.standard.set($0, forKey: "app.backendSimulation") }))
                Text("Relaunch Talaria to switch. Simulation uses separate hosts, preferences and caches; it never changes a real Mac.").font(.footnote).foregroundStyle(.secondary)
            } header: {
                SectionHeader("Backend")
            }

            Section {
                Picker("Theme", selection: $preferences.appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Haptics", isOn: $preferences.hapticsEnabled)
            } header: {
                SectionHeader("Appearance")
            }

            Section {
                Toggle("Notifications", isOn: Binding(
                    get: { preferences.notificationsEnabled },
                    set: { enabled in
                        if enabled {
                            Task {
                                let granted = await environment.requestNotificationPermission()
                                preferences.notificationsEnabled = granted
                                if !granted { toasts.show("Allow notifications in iOS Settings", symbol: "bell.slash") }
                            }
                        } else {
                            preferences.notificationsEnabled = false
                        }
                    }))
                if preferences.notificationsEnabled {
                    ForEach(NotificationCategory.allCases) { category in
                        Toggle(category.label, isOn: Binding(
                            get: { preferences.enabledNotificationCategories.contains(category) },
                            set: { preferences.setEnabled($0, for: category) }))
                    }
                }
            } header: {
                SectionHeader("Notifications")
            } footer: {
                Text("Talaria never notifies for individual tool calls. Notifications arrive while Talaria is running; delivery while it's closed needs push support in the bridge.")
            }

            Section {
                LabeledContent("Cached snapshots", value: Format.bytes(cacheSize))
                Button("Clear Local Cache", role: .destructive) {
                    environment.clearLocalCache()
                    cacheSize = environment.cache.sizeInBytes
                    toasts.show("Cache cleared")
                }
            } header: {
                SectionHeader("Local Data")
            } footer: {
                Text("Hermes on your Mac is the source of truth. Talaria keeps only preferences, saved hosts, drafts and last-known snapshots for fast launch.")
            }

            Section {
                Toggle("Show Diagnostics", isOn: $preferences.showDeveloperDiagnostics)
                if preferences.showDeveloperDiagnostics {
                    NavigationLink(value: Route.capabilities) { Text("Capabilities") }
                    NavigationLink(value: Route.logs) { Text("Logs") }
                }
            } header: {
                SectionHeader("Developer")
            }

            if let simulator = environment.simulator, preferences.showDeveloperDiagnostics {
                SimulationSection(simulator: simulator)
            }

            Section {
                HStack(spacing: 14) {
                    TalariaMark(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Talaria").font(.headline)
                        Text("The iPhone companion for Hermes on your Mac.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                LabeledContent("Connects through", value: environment.simulator == nil ? "Hermes bridge" : "Simulation")
            } header: {
                SectionHeader("About")
            }
        }
        .navigationTitle("Settings")
        .accentSwitches()
        .onAppear { cacheSize = environment.cache.sizeInBytes }
    }
}

/// Controls for the in-memory simulator, so every state can be exercised
/// without the Studio.
private struct SimulationSection: View {
    var simulator: MockHermesBackend

    @Environment(AppEnvironment.self) private var environment
    @State private var connectionChoice: SimulatedConnection = .live

    enum SimulatedConnection: String, CaseIterable, Identifiable {
        case live, reconnecting, bridgeOffline, hermesOffline, authRequired
        var id: String { rawValue }
        var label: String {
            switch self {
            case .live: "Connected"
            case .reconnecting: "Reconnecting"
            case .bridgeOffline: "Bridge offline"
            case .hermesOffline: "Hermes offline"
            case .authRequired: "Sign-in required"
            }
        }
        var state: ConnectionState? {
            switch self {
            case .live: nil
            case .reconnecting: .reconnecting(attempt: 1)
            case .bridgeOffline: .bridgeOffline
            case .hermesOffline: .hermesOffline
            case .authRequired: .authenticationRequired
            }
        }
    }

    var body: some View {
        @Bindable var controls = simulator.simulation
        Section {
            Picker("Connection", selection: $connectionChoice) {
                ForEach(SimulatedConnection.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: connectionChoice) { _, choice in
                simulator.simulateConnection(choice.state)
            }
            Picker("Latency", selection: $controls.latency) {
                ForEach(SimulatedLatency.allCases) { Text($0.label).tag($0) }
            }
            Picker("Run speed", selection: $controls.runSpeed) {
                Text("1×").tag(1.0)
                Text("3×").tag(3.0)
                Text("10×").tag(10.0)
            }
            Toggle("Fail requests", isOn: $controls.failRequests)
            Toggle("Empty account", isOn: $controls.emptyData)
                .onChange(of: controls.emptyData) {
                    Task { await environment.refreshAll() }
                }
            NavigationLink {
                CapabilityOverridesView(controls: controls)
            } label: {
                LabeledContent("Disabled capabilities", value: "\(controls.disabledCapabilities.count)")
            }
        } header: {
            SectionHeader("Simulation")
        } footer: {
            Text("Only present with the mock backend. Use these to preview offline, error, empty and reduced-capability states.")
        }
    }
}

private struct CapabilityOverridesView: View {
    @Bindable var controls: SimulationControls

    var body: some View {
        List {
            Section {
                ForEach(HermesCapability.allCases) { capability in
                    Toggle(isOn: Binding(
                        get: { !controls.disabledCapabilities.contains(capability) },
                        set: { enabled in
                            if enabled { controls.disabledCapabilities.remove(capability) } else { controls.disabledCapabilities.insert(capability) }
                        })) {
                        Label(capability.label, systemImage: capability.symbol)
                    }
                }
            } footer: {
                Text("Turning a capability off simulates a Mac that doesn't offer it.")
            }
        }
        .navigationTitle("Simulated Capabilities")
        .accentSwitches()
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What the connected host supports.
struct CapabilitiesView: View {
    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        List {
            Section {
                ForEach(HermesCapability.allCases) { capability in
                    let supported = connection.supports(capability)
                    HStack {
                        Label(capability.label, systemImage: capability.symbol)
                            .foregroundStyle(supported ? .primary : .secondary)
                        Spacer()
                        Image(systemName: supported ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(supported ? Theme.success : Color(uiColor: .tertiaryLabel))
                            .accessibilityLabel(supported ? "Supported" : "Not supported")
                    }
                }
            } header: {
                SectionHeader(connection.activeHost?.name ?? "Host")
            } footer: {
                Text(connection.connection.isConnected
                     ? "Reported by the Hermes bridge on your Mac. Unsupported features are hidden or disabled throughout Talaria."
                     : "Last known capabilities. The list refreshes when Talaria reconnects.")
            }
        }
        .navigationTitle("Capabilities")
    }
}
