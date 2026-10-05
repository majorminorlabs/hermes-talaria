import SwiftUI

// MARK: - Tools

struct ToolsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var tools = Resource<[ToolInfo]>()
    @State private var query = ""

    var body: some View {
        CapabilityGate(capability: .tools) {
            List {
                if let list = tools.value {
                    let filtered = list.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.toolset.localizedCaseInsensitiveContains(query) }
                    let attention = filtered.filter { !$0.availability.isAvailable }
                    let available = filtered.filter(\.availability.isAvailable)
                    if !attention.isEmpty {
                        Section {
                            ForEach(attention) { tool in ToolRow(tool: tool) }
                        } header: {
                            SectionHeader("Needs Attention")
                        }
                    }
                    Section {
                        ForEach(available.sorted { ($0.toolset, $0.name) < ($1.toolset, $1.name) }) { tool in ToolRow(tool: tool) }
                    } header: {
                        SectionHeader(title: "Available") {
                            Text("\(list.filter(\.availability.isAvailable).count) of \(list.count)").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Read-only. Tools are configured per profile on your Mac.")
                    }
                } else if let error = tools.phase.error {
                    ErrorContentView(error: error) { await load() }.listRowBackground(Color.clear)
                } else {
                    LoadingRows(count: 8)
                }
            }
            .searchable(text: $query, prompt: "Search tools")
        }
        .navigationTitle("Tools")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await tools.load { try await environment.client.tools.listTools() }
    }

}

private struct ToolRow: View {
    var tool: ToolInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(tool.name).font(.body.monospaced())
                Spacer()
                if tool.availability.isAvailable {
                    Text(tool.toolset).font(.caption.monospaced()).foregroundStyle(.tertiary)
                } else {
                    StatusPill(text: tool.availability.label, color: color)
                }
            }
            Text(tool.summary).font(.subheadline).foregroundStyle(.secondary)
            if let reason = tool.availability.reason {
                Text(reason).font(.caption).foregroundStyle(color)
            }
        }
        .padding(.vertical, 1)
    }

    private var color: Color {
        switch tool.availability {
        case .available: Theme.success
        case .needsSetup: Theme.attention
        case .unavailable: .secondary
        }
    }
}

// MARK: - MCP

struct MCPView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var servers = Resource<[MCPServer]>()

    var body: some View {
        CapabilityGate(capability: .mcp) {
            List {
                if let list = servers.value {
                    if list.isEmpty {
                        ContentUnavailableView("No MCP Servers", systemImage: "point.3.connected.trianglepath.dotted",
                                               description: Text("Configure MCP servers in Hermes on your Mac."))
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        ForEach(list) { server in
                            NavigationLink(value: Route.mcpServer(server)) { MCPServerRow(server: server) }
                        }
                    } footer: {
                        if !list.isEmpty { Text("Status as reported by the host. Configuration is read-only here.") }
                    }
                } else if let error = servers.phase.error {
                    ErrorContentView(error: error) { await load() }.listRowBackground(Color.clear)
                } else {
                    LoadingRows(count: 4)
                }
            }
        }
        .navigationTitle("MCP Servers")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await servers.load { try await environment.client.tools.listMCPServers() }
    }
}

private struct MCPServerRow: View {
    var server: MCPServer

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(server.name).font(.body.weight(.semibold))
                Spacer()
                StatusPill(text: server.status.label, color: server.status.tint)
            }
            Text("\(server.transport.label) · \(server.toolCount) tools")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let error = server.errorMessage {
                Text(error).font(.caption).foregroundStyle(Theme.failure).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct MCPServerDetailView: View {
    var server: MCPServer

    var body: some View {
        List {
            Section {
                LabeledContent("Status") { StatusPill(text: server.status.label, color: server.status.tint) }
                if let error = server.errorMessage {
                    Text(error).foregroundStyle(Theme.failure)
                }
                KeyValueRow(label: "Transport", value: server.transport.label)
                KeyValueRow(label: "Endpoint", value: server.endpoint, monospaced: true)
                if let connected = server.lastConnectedAt {
                    KeyValueRow(label: "Last connected", value: Format.relative(connected))
                }
            }
            Section {
                if server.toolNames.isEmpty {
                    Text("No tools available while disconnected.").foregroundStyle(.secondary)
                }
                ForEach(server.toolNames, id: \.self) { name in
                    Text(name).font(.callout.monospaced())
                }
            } header: {
                SectionHeader("Tools (\(server.toolCount))")
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Integrations

struct IntegrationsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var integrations = Resource<[Integration]>()

    var body: some View {
        CapabilityGate(capability: .integrations) {
            List {
                if let list = integrations.value {
                    let configured = list.filter { $0.status != .notConfigured }
                    let unconfigured = list.filter { $0.status == .notConfigured }
                    if !configured.isEmpty {
                        Section {
                            ForEach(configured) { IntegrationRow(integration: $0) }
                        } header: {
                            SectionHeader("Messaging & Services")
                        }
                    }
                    if !unconfigured.isEmpty {
                        Section {
                            ForEach(unconfigured) { IntegrationRow(integration: $0) }
                        } header: {
                            SectionHeader("Not Configured")
                        } footer: {
                            Text("Set up integrations with the Hermes gateway on your Mac.")
                        }
                    }
                } else if let error = integrations.phase.error {
                    ErrorContentView(error: error) { await load() }.listRowBackground(Color.clear)
                } else {
                    LoadingRows(count: 5)
                }
            }
        }
        .navigationTitle("Integrations")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await integrations.load { try await environment.client.integrations.listIntegrations() }
    }
}

private struct IntegrationRow: View {
    var integration: Integration

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: integration.platform.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(integration.platform.label)
                    Spacer()
                    StatusPill(text: integration.status.label, color: integration.status.tint)
                }
                if let detail = integration.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                if let last = integration.lastActivity {
                    Text("Active \(Format.relative(last))").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
