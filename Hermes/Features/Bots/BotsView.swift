import SwiftUI

/// The Studio's bots (Hermes Desktop Bot Mode), discovered live. New bots
/// appear on refresh; each opens its own canonical chat.
struct BotsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection

    @State private var creatingBot = false

    var body: some View {
        LoadableContent(phase: profiles.phase, isEmpty: profiles.profiles.isEmpty, hasData: !profiles.profiles.isEmpty,
                        retry: { await profiles.refresh() }) {
            List {
                ConnectionNoticeSection()
                if connection.supports(.profiles) {
                    Section {
                        if profiles.sorted.isEmpty {
                            Text("No agents on this Mac yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(profiles.sorted) { profile in
                            NavigationLink(value: Route.profile(profile.id)) {
                                BotRow(profile: profile)
                            }
                        }
                    } header: {
                        SectionHeader(title: "On \(connection.activeHost?.name ?? "your Mac")") {
                            if !profiles.bots.isEmpty {
                                Text("\(profiles.bots.count)").monospacedDigit().foregroundStyle(Theme.secondaryText)
                            }
                        }
                    } footer: {
                        if connection.supports(.botMode) {
                            Text("Hidden agents are managed in Hermes Desktop.")
                        }
                    }
                }


            }
            .listSectionSpacing(.compact)
            .refreshable { await profiles.refresh() }
        } empty: {
            ContentUnavailableView("No Agents", systemImage: "person.2",
                                   description: Text("Agents created in Hermes appear here."))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { ConnectionChip() }
            ToolbarItem(placement: .topBarTrailing) {
                if connection.supports(.botCreate) {
                    Button { creatingBot = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .accessibilityLabel("Create Agent")
                }
            }
        }
        .sheet(isPresented: $creatingBot) { BotEditorView(profile: nil) }
        .task {
            while !Task.isCancelled {
                await profiles.refresh()
                await profiles.loadMissingAvatars()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}

/// One bot: face, name, what it's doing (or last did), and its model.
struct BotRow: View {
    var profile: Profile

    @Environment(ActivityStore.self) private var activity
    @Environment(ConnectionStore.self) private var connection
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let run = activity.run(profile.currentRunID).flatMap { $0.state.isActive ? $0 : nil }
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
            ProfileAvatarWithStatus(profile: profile, size: typeSize.isAccessibilitySize ? 36 : 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(profile.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    if profile.isDefault { Tag("Default") }
                    Spacer(minLength: 6)
                    if run == nil, let last = profile.lastActiveAt {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            Text(Format.relative(last, now: context.date))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                activityLine(run)
                    .font(.subheadline)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                if let model = modelLine {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func activityLine(_ run: Run?) -> some View {
        if let run {
            HStack(spacing: 5) {
                StatusDot(color: run.displayState(isLive: connection.connection.isConnected).tint, pulsing: connection.connection.isConnected, size: 6)
                Text("\(run.displayState(isLive: connection.connection.isConnected).label) · \(run.title)").foregroundStyle(run.displayState(isLive: connection.connection.isConnected).tint)
            }
        } else if profile.status == .needsAttention {
            Text("Needs you").foregroundStyle(Theme.attention)
        } else if let activity = profile.activitySummary, !activity.isEmpty {
            Text(activity).foregroundStyle(.secondary)
        } else if !profile.role.isEmpty {
            Text(profile.role).foregroundStyle(.secondary)
        } else if !profile.summary.isEmpty {
            Text(profile.summary).foregroundStyle(.secondary)
        } else {
            Text(profile.status == .idle ? "Idle" : "No recent activity").foregroundStyle(.secondary)
        }
    }

    private var modelLine: String? {
        guard profile.modelAvailable != false else { return nil }
        let provider = profile.model.provider
        return provider.isEmpty || provider == "Hermes" ? profile.model.displayName : "\(profile.model.displayName) · \(provider)"
    }
}

#Preview {
    NavigationStack { BotsView().routeDestinations() }
        .previewEnvironment()
}
