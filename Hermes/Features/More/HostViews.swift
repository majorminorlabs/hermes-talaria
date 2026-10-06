import SwiftUI

/// Saved hosts. Definitions are local; status comes from each host's bridge.
struct HostsView: View {
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(connection.hosts) { host in
                    let status = connection.status(for: host.id)
                    let isActive = host.id == connection.activeHostID
                    HStack(spacing: 12) {
                        Button {
                            Task { await connection.switchHost(to: host.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: host.symbol)
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        StatusDot(color: status.connection.tint, size: 6)
                                        Text(statusText(status))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isActive {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        NavigationLink(value: Route.host(host.id)) { EmptyView() }
                            .frame(width: 20)
                    }
                    .swipeActions {
                        if !isActive {
                            Button("Remove", systemImage: "trash", role: .destructive) { toasts.perform { try await connection.remove(hostID: host.id) } }
                        }
                    }
                }
            } footer: {
                Text("Tap a host to make it active. Talaria reaches each Mac's Hermes bridge over your tailnet.")
            }
        }
        .navigationTitle("Hosts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Host")
            }
        }
        .sheet(isPresented: $adding) { HostEditorView(host: nil) }
        .task { await connection.refreshStatuses() }
        .refreshable { await connection.refreshStatuses() }
    }

    private func statusText(_ status: HostStatus) -> String {
        if status.connection.isConnected { return "Connected · \(status.activeRunCount) active" }
        if let seen = status.lastSeen { return "\(status.connection.label) · seen \(Format.relative(seen))" }
        return status.connection.label
    }
}

struct HostDetailView: View {
    var hostID: String

    @Environment(ToastCenter.self) private var toasts

    @Environment(ConnectionStore.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    var body: some View {
        if let host = connection.hosts.first(where: { $0.id == hostID }) {
            content(host)
        } else {
            ContentUnavailableView("Host Not Found", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
        }
    }

    private func content(_ host: Host) -> some View {
        let status = connection.status(for: host.id)
        let isActive = host.id == connection.activeHostID
        return List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: host.symbol)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(host.name).font(.title3.weight(.semibold))
                        ConnectionLabel(state: status.connection, host: host.name)
                    }
                }
                .padding(.vertical, 4)
                if status.connection.isDegraded && !status.connection.isTransitioning {
                    FailureCallout(explanation: StatusCopy.Explanation(title: status.connection.label(host: host.name),
                                                                       message: status.connection.explanation,
                                                                       code: status.connection.diagnosticCode),
                                   symbol: status.connection.symbol, tint: status.connection.tint)
                        .padding(.vertical, 2)
                }
                if isActive {
                    Button("Reconnect", systemImage: "arrow.clockwise") { Task { await connection.reconnect() } }
                        .disabled(status.connection.isTransitioning)
                } else {
                    Button("Make Active", systemImage: "checkmark.circle") { Task { await connection.switchHost(to: host.id) } }
                }
            }

            Section {
                KeyValueRow(label: "Address", value: host.displayAddress, monospaced: true)
                KeyValueRow(label: "Network", value: host.network.label)
                KeyValueRow(label: "Latency", value: status.latencyMilliseconds.map { "\($0) ms" } ?? "—")
                KeyValueRow(label: "Last seen", value: status.lastSeen.map { Format.relative($0) } ?? "Never")
            } header: {
                SectionHeader("Connection")
            }

            Section {
                KeyValueRow(label: "Hermes", value: [status.hermesState.label, status.hermesVersion].compactMap { $0 }.joined(separator: " · "))
                KeyValueRow(label: "Bridge", value: status.bridgeVersion ?? "—")
                if let model = status.defaultModel {
                    KeyValueRow(label: "Default model", value: model.detailedLabel)
                }
                KeyValueRow(label: "Active runs", value: "\(status.activeRunCount)")
                if isActive {
                    NavigationLink(value: Route.capabilities) {
                        LabeledContent("Capabilities", value: "\(status.capabilities.count)")
                    }
                }
            } header: {
                SectionHeader("Software")
            }

            if let resources = status.resources {
                Section {
                    ResourceGauge(label: "CPU", value: resources.cpuLoad)
                    ResourceGauge(label: "Memory", value: resources.memoryUsed)
                    KeyValueRow(label: "Uptime", value: Format.uptime(resources.uptime))
                } header: {
                    SectionHeader("Resources")
                }
            }

            Section {
                Button(status.connection == .authenticationRequired ? "Pair Again" : "Edit Host", systemImage: "pencil") { editing = true }
                if isActive {
                    Button("Remove Local Credential", systemImage: "lock.slash", role: .destructive) { toasts.perform { try await connection.forgetActiveCredential() } }
                    Text("Removing it here doesn't revoke the credential on your Mac. Revoke this iPhone with the bridge CLI.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Remove Host", systemImage: "trash", role: .destructive) {
                    toasts.perform { try await connection.remove(hostID: host.id); dismiss() }
                }
            }
        }
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { HostEditorView(host: host) }
    }
}

private struct ResourceGauge: View {
    var label: String
    var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text(Format.percent(value)).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: value)
                .tint(value > 0.85 ? Theme.attention : Color.accentColor)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Add or edit a saved host. Pairing with the bridge happens on connect.
struct HostEditorView: View {
    var host: Host?

    @Environment(ConnectionStore.self) private var connection
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var port = ""
    @State private var token = ""
    @State private var saving = false
    @State private var failure: String?
    @Environment(AppEnvironment.self) private var environment
    @State private var network: HostNetwork = .tailscale

    var body: some View {
        NavigationStack {
            Form {
                if host == nil {
                    Section {
                        HStack(spacing: 14) {
                            TalariaMark(size: 48)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pair Talaria with Hermes").font(.headline)
                                Text("Connect to the Hermes bridge running on your Mac.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                Section {
                    TextField("Name", text: $name).accessibilityIdentifier("host-name")
                    TextField("Bridge HTTPS URL", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("host-address")
                        .font(.body.monospaced())
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("host-port")
                        .font(.body.monospaced())
                    if environment.simulator == nil {
                        SecureField("Bridge token", text: $token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .privacySensitive().accessibilityIdentifier("bridgeToken")
                    }
                    if let failure { Label(failure, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.failure) }
                    Picker("Network", selection: $network) {
                        ForEach(HostNetwork.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("Use your Mac's Hermes bridge HTTPS URL and the pairing token from its CLI. The token is stored only in this iPhone's Keychain. Leave it empty when editing to keep the existing credential.")
                }
            }
            .navigationTitle(host == nil ? "Add Host" : "Edit Host")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Pairing…" : "Save") {
                        let record = Host(id: host?.id ?? "host-\(UUID().uuidString.lowercased())",
                            name: name, address: address, port: Int(port), network: network, symbol: host?.symbol ?? "macstudio")
                        if environment.simulator != nil { connection.save(record); dismiss(); return }
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await connection.pair(record, token: token); token = ""; dismiss() }
                            catch { failure = HermesError.from(error)?.errorDescription ?? "Pairing could not be saved securely" }
                        }
                    }
                    .disabled(name.isEmpty || address.isEmpty || saving)
                }
            }
            .onAppear {
                guard let host else { return }
                name = host.name
                address = host.address
                port = host.port.map(String.init) ?? ""
                network = host.network
            }
        }
    }
}
