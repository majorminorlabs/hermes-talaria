import SwiftUI

/// Full context for an approval: payload, reason, diff, and the decision.
struct ApprovalDetailView: View {
    var approvalID: String

    @Environment(ActivityStore.self) private var activity
    @Environment(ProfileStore.self) private var profiles
    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        Group {
            if let approval = activity.approval(approvalID) {
                content(approval)
            } else {
                resolvedState
            }
        }
        .navigationTitle("Approval")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var resolvedState: some View {
        if let decision = activity.resolvedApprovals[approvalID] {
            ContentUnavailableView {
                Label(decision.map { $0.isApproval ? "Approved" : "Denied" } ?? "Expired",
                      systemImage: decision?.isApproval == true ? "checkmark.shield" : "xmark.shield")
            } description: {
                Text("This request is no longer pending.")
            }
        } else {
            ContentUnavailableView("No Longer Pending", systemImage: "hand.raised.slash",
                                   description: Text("This approval was resolved or expired on your Mac."))
        }
    }

    private func content(_ approval: ApprovalRequest) -> some View {
        List {
            Section {
                ApprovalCard(approval: approval, style: .plain, showsDetailsLink: false)
                    .padding(.vertical, 6)
            }

            if let reason = approval.reason {
                Section {
                    Text(reason)
                } header: {
                    SectionHeader("Why Hermes Is Asking")
                }
            }

            if let diff = approval.diff {
                Section {
                    DiffView(diff: diff)
                        .listRowInsets(EdgeInsets())
                } header: {
                    SectionHeader("Proposed Change")
                }
            } else if approval.paths.count > 1 || (approval.command != nil && !approval.paths.isEmpty) {
                Section {
                    ForEach(approval.paths, id: \.self) { path in
                        Text(path).font(.callout.monospaced())
                    }
                } header: {
                    SectionHeader("Affected Paths")
                }
            }

            Section {
                KeyValueRow(label: "Type", value: approval.kind.label)
                KeyValueRow(label: "Risk", value: approval.risk.label)
                KeyValueRow(label: "Requested by", value: profiles.name(approval.profileID))
                KeyValueRow(label: "Requested", value: Format.timestamp(approval.requestedAt))
                if let expires = approval.expiresAt {
                    LabeledContent("Expires") {
                        Text(expires, style: .relative).foregroundStyle(.secondary)
                    }
                }
                NavigationLink(value: Route.run(approval.runID)) {
                    LabeledContent("Run", value: activity.run(approval.runID)?.title ?? approval.runID)
                }
            } header: {
                SectionHeader("Request")
            }
        }
    }
}

/// Unified diff with added/removed line highlighting.
struct DiffView: View {
    var diff: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diff.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .font(.caption.monospaced())
                        .foregroundStyle(color(for: line))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(for: line))
                }
            }
            .padding(.vertical, 8)
        }
        .textSelection(.enabled)
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("@@") { return .secondary }
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .secondary }
        if line.hasPrefix("+") { return Theme.success }
        if line.hasPrefix("-") { return Theme.failure }
        return .primary
    }

    private func background(for line: String) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") { return .clear }
        if line.hasPrefix("+") { return Theme.success.opacity(0.1) }
        if line.hasPrefix("-") { return Theme.failure.opacity(0.1) }
        return .clear
    }
}

#Preview {
    NavigationStack { ApprovalDetailView(approvalID: "a-index") }.previewEnvironment()
}
