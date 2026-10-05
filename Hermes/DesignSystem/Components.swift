import SwiftUI
import UIKit

/// Label/value row for metadata sections. Monospace only for literal values
/// (IDs, paths, codes); long values wrap rather than truncate.
struct KeyValueRow: View {
    var label: String
    var value: String
    var monospaced = false
    var copyable = false

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(monospaced ? .footnote.monospaced() : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .contextMenu {
            if copyable || monospaced {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
            }
        }
    }
}

/// Monospaced payload block (commands, paths).
struct CommandBlock: View {
    var text: String
    var prompt: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let prompt {
                Text(prompt).foregroundStyle(.tertiary)
            }
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout.monospaced())
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Section label in Hermes Desktop's voice (`BOTS`, `SESSIONS`): small,
/// uppercase, tracked, secondary, with an optional trailing count or action.
struct SectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(.secondary)
                // Read as written, not letter-by-letter capitals.
                .accessibilityLabel(Text(title))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
                .textCase(nil)
                .font(.footnote)
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        trailing = { EmptyView() }
    }
}

// MARK: - Switches

extension View {
    /// Switches wear Talaria blue, like Hermes Desktop's. Scoped to screens with
    /// toggles: a root-level tint would also repaint destructive bordered buttons.
    func accentSwitches() -> some View { tint(.accentColor) }
}

// MARK: - Toasts

struct ToastOverlay: ViewModifier {
    @Environment(ToastCenter.self) private var toasts

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = toasts.current {
                Label(toast.message, systemImage: toast.symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(toast.isError ? Theme.failure : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(toast.id)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(duration: 0.35), value: toasts.current)
    }
}

extension View {
    func toastOverlay() -> some View { modifier(ToastOverlay()) }
}

// MARK: - Haptics

struct HapticModifier<Trigger: Equatable>: ViewModifier {
    var feedback: SensoryFeedback
    var trigger: Trigger
    @Environment(AppPreferences.self) private var preferences

    func body(content: Content) -> some View {
        content.sensoryFeedback(feedback, trigger: trigger) { _, _ in preferences.hapticsEnabled }
    }
}

extension View {
    /// Haptic feedback that respects the user's haptics preference.
    func haptic<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(HapticModifier(feedback: feedback, trigger: trigger))
    }
}
