import SwiftUI

/// An approval request with its decision controls.
///
/// Approve/Deny appear only when the request is actionable from the phone.
/// Otherwise the card explains why and offers details (and Stop, which the
/// bridge can always perform cooperatively).
struct ApprovalCard: View {
    var approval: ApprovalRequest
    var style: Style = .card
    var showsDetailsLink = true

    enum Style { case card, plain }

    @Environment(ActivityStore.self) private var activity
    @Environment(ConnectionStore.self) private var connection
    @Environment(ToastCenter.self) private var toasts
    @Environment(AppRouter.self) private var router
    @State private var pendingDecision: ApprovalDecision?
    @State private var resolvedCount = 0

    var body: some View {
        let availability = approval.effectiveAvailability(remoteApprovalsSupported: connection.supports(.approvals))
        let tint = availability == .expired ? Color.secondary : Theme.attention

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: availability == .expired ? "clock.badge.xmark" : "hand.raised.fill")
                    .foregroundStyle(tint)
                Text(approval.isClarification ? "Hermes needs an answer" : availability.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let risk = approval.risk, risk != .low {
                    Text(risk.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(risk == .high ? Theme.failure : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(approval.isClarification ? "Question:" : "\(approval.headline):")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                CommandBlock(text: approval.clarificationQuestion ?? approval.payload, prompt: approval.kind == .command ? "$" : nil)
            }

            if let directory = approval.workingDirectory {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Working directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(directory)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let explanation = availability.explanation {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let timeout = approval.timeoutExplanation {
                Text(timeout).font(.footnote).foregroundStyle(.secondary)
            }
            controls(availability)
        }
        .padding(style == .card ? 14 : 0)
        .background {
            if style == .card {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel)
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.07)) }
            }
        }
        .haptic(.warning, trigger: approval.id)
        .haptic(.success, trigger: resolvedCount)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func controls(_ availability: ApprovalAvailability) -> some View {
        if approval.isClarification {
            if availability.isActionable, let id = approval.conversationID {
                Button("Reply in Conversation", systemImage: "bubble.left") { router.open(.conversation(id)) }
            }
            if let run = activity.run(approval.runID), run.canStop, connection.supports(.stop) {
                Button("Stop Run", systemImage: "stop.circle", role: .destructive) { toasts.perform { try await activity.stop(run.id) } }
            }
        } else if availability.isActionable {
            ApprovalChoiceButtons(approval: approval, pending: pendingDecision != nil || !connection.connection.isConnected, decide: decide)
            if showsDetailsLink && (approval.diff != nil || approval.reason != nil) {
                detailsButton
            }
        } else {
            HStack(spacing: 10) {
                if showsDetailsLink { detailsButton }
                if let run = activity.run(approval.runID), run.canStop, connection.supports(.stop),
                   availability != .expired {
                    Button("Stop Run", systemImage: "stop.fill", role: .destructive) {
                        toasts.perform(success: "Stopping run") { try await activity.stop(run.id) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var detailsButton: some View {
        Button("View Details") { router.open(.approval(approval.id)) }
            .font(.subheadline.weight(.medium))
            .buttonStyle(.borderless)
    }

    private func decide(_ decision: ApprovalDecision) {
        guard pendingDecision == nil else { return }
        pendingDecision = decision
        Task {
            do {
                try await activity.resolve(approval.id, decision: decision)
                resolvedCount += 1
                toasts.show(decision.isApproval ? "Approved" : "Denied", symbol: decision.isApproval ? "checkmark.circle.fill" : "xmark.circle.fill")
            } catch {
                toasts.show(error: error)
            }
            pendingDecision = nil
        }
    }
}

#Preview {
    let fixtures = MockFixtures.standard()
    ScrollView {
        VStack(spacing: 16) {
            ApprovalCard(approval: fixtures.approvals[0])
            ApprovalCard(approval: fixtures.approvals[1])
        }
        .padding()
    }
    .previewEnvironment()
}

/// The same offered choices and resolve path on Now and Run Detail.
struct ApprovalChoiceButtons: View {
    var approval: ApprovalRequest
    var pending: Bool
    var decide: (ApprovalDecision) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(approval.offeredDecisions, id: \.self) { decision in
                Button(decision.title, role: decision == .deny ? .destructive : nil) { decide(decision) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("approval-\(approval.id)-\(decision.choice)")
                    .frame(minHeight: 44)
            }
        }.disabled(pending)
    }
}
