import SwiftUI
import UIKit

/// Diagnostics: errors, warnings, connection events and run failures.
struct LogsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(ToastCenter.self) private var toasts
    @State private var logs = Resource<[LogEntry]>()
    @State private var minimumLevel: LogLevel = .info
    @State private var category: LogCategory?
    @State private var query = ""

    var body: some View {
        CapabilityGate(capability: .logs) {
            List {
                Section {
                    Picker("Level", selection: $minimumLevel) {
                        Text("All").tag(LogLevel.debug)
                        Text("Info+").tag(LogLevel.info)
                        Text("Warnings+").tag(LogLevel.warning)
                        Text("Errors").tag(LogLevel.error)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                if let list = logs.value {
                    let filtered = filter(list)
                    if filtered.isEmpty {
                        ContentUnavailableView("No Matching Entries", systemImage: "doc.text.magnifyingglass")
                            .listRowBackground(Color.clear)
                    }
                    ForEach(filtered) { entry in LogRow(entry: entry) }
                } else if let error = logs.phase.error {
                    ErrorContentView(error: error) { await load() }.listRowBackground(Color.clear)
                } else {
                    LoadingRows(count: 8)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search logs")
        }
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Category", selection: $category) {
                        Text("All Categories").tag(LogCategory?.none)
                        ForEach(LogCategory.allCases) { Text($0.label).tag(LogCategory?.some($0)) }
                    }
                } label: {
                    Image(systemName: category == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter by category")

                Menu {
                    Button("Copy Visible Entries", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = exportText
                        toasts.show("Copied \(filter(logs.value ?? []).count) entries")
                    }
                    ShareLink(item: exportText, preview: SharePreview("Hermes logs")) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export logs")
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await logs.load { try await environment.client.logs.recentLogs(limit: 500) }
    }

    private func filter(_ entries: [LogEntry]) -> [LogEntry] {
        entries.filter { entry in
            entry.level >= minimumLevel
                && (category == nil || entry.category == category)
                && (query.isEmpty || entry.message.localizedCaseInsensitiveContains(query)
                    || (entry.detail?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }

    private var exportText: String {
        filter(logs.value ?? []).map(\.exportLine).joined(separator: "\n")
    }
}

private struct LogRow: View {
    var entry: LogEntry
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: entry.level.symbol)
                    .font(.caption)
                    .foregroundStyle(entry.level.tint)
                    .frame(width: 16)
                Text(entry.message)
                    .font(.subheadline)
                    .lineLimit(expanded ? nil : 2)
            }
            HStack(spacing: 6) {
                Text(entry.category.label)
                Text("·")
                Text(Calendar.current.isDateInToday(entry.timestamp)
                     ? entry.timestamp.formatted(date: .omitted, time: .standard)
                     : entry.timestamp.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .monospacedDigit()
                if entry.runID != nil {
                    Text("·")
                    Image(systemName: "play.circle")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 24)

            if expanded, let detail = entry.detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.leading, 24)
            }
            if expanded, let runID = entry.runID {
                NavigationLink(value: Route.run(runID)) {
                    Text("Open run").font(.caption.weight(.medium))
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = entry.exportLine }
        }
    }
}
