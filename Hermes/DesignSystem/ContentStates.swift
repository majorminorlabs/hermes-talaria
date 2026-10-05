import SwiftUI

/// Full-screen state when there's nothing cached to show and the bridge is
/// unreachable.
struct OfflineContentView: View {
    var state: ConnectionState
    var host: String? = nil
    var retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(state.label(host: host), systemImage: state.symbol)
        } description: {
            Text(state.explanation)
        } actions: {
            Button("Reconnect") { Task { await retry() } }
                .buttonStyle(.bordered)
        }
    }
}

struct ErrorContentView: View {
    var error: HermesError
    var retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
        } description: {
            if let suggestion = error.recoverySuggestion { Text(suggestion) }
        } actions: {
            Button("Try Again") { Task { await retry() } }
                .buttonStyle(.bordered)
        }
    }
}

/// Placeholder rows while the first load is in flight.
struct LoadingRows: View {
    var count = 6

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Placeholder title text")
                    Text("Secondary detail line goes here").font(.subheadline)
                }
            }
            .redacted(reason: .placeholder)
        }
        .accessibilityLabel("Loading")
    }
}

/// Decides between loading, offline, error, empty and content for a
/// list-backed screen. Cached content always wins over an error so the user
/// keeps seeing last-known state.
struct LoadableContent<Content: View, Empty: View>: View {
    var phase: LoadPhase
    var isEmpty: Bool
    var hasData: Bool
    var retry: () async -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var empty: () -> Empty

    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        if hasData && !isEmpty {
            content()
        } else if phase.isLoading || (phase == .idle && connection.connection.isTransitioning) {
            List { LoadingRows() }
        } else if connection.connection.isDegraded && !hasData {
            OfflineContentView(state: connection.connection, host: connection.activeHost?.name) { await connection.reconnect() }
        } else if let error = phase.error, !hasData {
            ErrorContentView(error: error, retry: retry)
        } else if isEmpty {
            empty()
        } else {
            content()
        }
    }
}

/// Slim bar shown beneath the navigation bar whenever data isn't live.
struct ConnectionBanner: View {
    @Environment(ConnectionStore.self) private var connection
    var updatedAt: Date?
    /// Rounded card for use inside lists, rather than a full-width bar.
    var inline = false

    var body: some View {
        let state = connection.connection
        if state.isDegraded {
            HStack(spacing: 10) {
                if state.isTransitioning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state.symbol).foregroundStyle(state.tint)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.label(host: connection.activeHost?.name)).font(.subheadline.weight(.semibold))
                    Group {
                        if let updatedAt {
                            Text("Last-known state · \(Format.updated(updatedAt))")
                        } else {
                            Text("Showing last-known state")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if !state.isTransitioning {
                    Button("Retry") { Task { await connection.reconnect() } }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, inline ? 14 : 16)
            .padding(.vertical, inline ? 11 : 9)
            .background {
                if inline {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground))
                } else {
                    Rectangle().fill(.bar)
                }
            }
            .overlay(alignment: .bottom) { if !inline { Divider() } }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// The same notice as a list section, for screens with large titles where a
/// pinned bar would sit over the title.
struct ConnectionNoticeSection: View {
    var updatedAt: Date?
    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        if connection.connection.isDegraded {
            Section {
                ConnectionBanner(updatedAt: updatedAt, inline: true)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
    }
}

extension View {
    /// Adds the degraded-connection banner under the navigation bar.
    func connectionBanner(updatedAt: Date? = nil) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            ConnectionBanner(updatedAt: updatedAt)
        }
    }
}
