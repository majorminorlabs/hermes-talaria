import SwiftUI

/// Lower-frequency administration and diagnostics. What the connected Mac
/// offers is listed; what it doesn't is summarized once, not shown as dead rows.
struct MoreView: View {
    @Environment(ConnectionStore.self) private var connection

    private let hermesDestinations: [(Route, String, String, HermesCapability)] = [
        (.usage, "Usage", "chart.bar", .usage),
        (.skills, "Skills", "book.closed", .skills),
        (.tools, "Tools", "wrench.and.screwdriver", .tools),
        (.mcp, "MCP Servers", "point.3.connected.trianglepath.dotted", .mcp),
        (.memory, "Memory", "brain", .memory),
        (.integrations, "Integrations", "app.connected.to.app.below.fill", .integrations),
    ]

    var body: some View {
        let available = hermesDestinations.filter { connection.supports($0.3) }
        let unavailable = hermesDestinations.filter { !connection.supports($0.3) }.map(\.1)
            + (connection.supports(.logs) ? [] : ["Logs"])

        List {
            Section {
                if let host = connection.activeHost {
                    NavigationLink(value: Route.host(host.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: host.symbol)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(host.name).font(.body.weight(.semibold))
                                Text(host.displayAddress)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 8)
                            ConnectionLabel(state: connection.connection)
                        }
                    }
                }
                NavigationLink(value: Route.hosts) {
                    LabeledContent {
                        Text("\(connection.hosts.count)").monospacedDigit()
                    } label: {
                        row("Saved Hosts", "server.rack")
                    }
                }
            } header: {
                SectionHeader("Host")
            }

            if !available.isEmpty {
                Section {
                    ForEach(available, id: \.1) { route, title, symbol, _ in
                        NavigationLink(value: route) { row(title, symbol) }
                    }
                } header: {
                    SectionHeader("Hermes")
                }
            }

            Section {
                if connection.supports(.logs) {
                    NavigationLink(value: Route.logs) { row("Logs", "doc.text.magnifyingglass") }
                }
                NavigationLink(value: Route.capabilities) {
                    LabeledContent {
                        Text("\(connection.capabilities.count) of \(HermesCapability.allCases.count)").monospacedDigit()
                    } label: {
                        row("Capabilities", "checklist.checked")
                    }
                }
            } header: {
                SectionHeader("Diagnostics")
            } footer: {
                if !unavailable.isEmpty {
                    Text("Not offered by \(connection.activeHost?.name ?? "this Mac"): \(ListFormatter.localizedString(byJoining: unavailable)).")
                }
            }

            Section {
                NavigationLink(value: Route.settings) { row("Settings", "gearshape") }
            }

            Section {
                identity
                    .listRowBackground(Color.clear)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("More")
    }

    private func row(_ title: String, _ symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }

    /// Talaria's quiet identity line: the mark, the version, and what it's connected to.
    private var identity: some View {
        VStack(spacing: 8) {
            TalariaMark(size: 40)
            VStack(spacing: 2) {
                Text("Talaria \(appVersion)")
                    .font(.footnote.weight(.semibold))
                Text(connectedLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let versions = versionsLine {
                    Text(versions)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var connectedLine: String {
        guard let host = connection.activeHost?.name else { return "Not paired with a Mac" }
        return connection.connection.isConnected ? "Connected to Hermes on \(host)" : "Hermes on \(host)"
    }

    private var versionsLine: String? {
        var parts: [String] = []
        if let hermes = connection.status.hermesVersion { parts.append("Hermes \(Format.version(hermes))") }
        if let bridge = connection.status.bridgeVersion { parts.append("bridge \(bridge)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack { MoreView().routeDestinations() }
        .previewEnvironment()
}
