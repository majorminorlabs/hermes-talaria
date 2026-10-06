import SwiftUI
import UIKit

/// Semantic colors. Talaria blue (the accent) marks interaction and selection;
/// state colors are the only other saturated hues. Status hues are Hermes
/// Desktop's `--ui-green/red` family, deepened where needed so small text
/// clears 4.5:1 on light backgrounds and lifted for dark mode.
enum Theme {
    static let secondaryText = adaptive(light: 0x55545E, dark: 0xB9B7C2)
    static let running = Color.accentColor
    static let attention = adaptive(light: 0xB9530C, dark: 0xF5A04A)
    static let failure = adaptive(light: 0xCF2D56, dark: 0xE75E78)
    static let success = adaptive(light: 0x1A7F5C, dark: 0x55A583)
    static let attentionWash = Color(uiColor: UIColor { traits in
        Theme.adaptiveUIColor(light: 0xB9530C, dark: 0xF5A04A).resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.12 : 0.07)
    })
    static let steering = Color.indigo
    static let idle = Color.secondary

    /// Fill for inline panels (Desktop's widget shell): soft, no stroke.
    static let panel = Color(uiColor: .secondarySystemBackground)
    static let codeBackground = Color(uiColor: .secondarySystemBackground)
    static let groupedRow = Color(uiColor: .secondarySystemGroupedBackground)
    static let hairline = Color(uiColor: .separator)
    /// User messages wear Desktop's faint accent-tinted bubble.
    static let userBubble = Color.accentColor.opacity(0.11)

    /// SwiftUI resolves dynamic colors on its render thread, so the provider
    /// must not inherit the module's default MainActor isolation.
    nonisolated static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: adaptiveUIColor(light: light, dark: dark))
    }

    nonisolated static func adaptiveUIColor(light: UInt32, dark: UInt32) -> UIColor {
        let provider: @Sendable (UITraitCollection) -> UIColor = { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        }
        return UIColor(dynamicProvider: provider)
    }
}

extension UIColor {
    nonisolated convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension RunState {
    var tint: Color {
        switch self {
        case .queued: .secondary
        case .running: Theme.running
        case .waitingForApproval, .waitingForInput: Theme.attention
        case .steeringPending: Theme.steering
        case .stopping: .secondary
        case .completed: Theme.success
        case .failed: Theme.failure
        case .cancelled: .secondary
        case .disconnected, .unknown: .secondary
        }
    }
}

extension RunOutcome {
    var tint: Color {
        switch self {
        case .succeeded: Theme.success
        case .failed: Theme.failure
        case .cancelled: .secondary
        }
    }
}

extension ConnectionState {
    var tint: Color {
        switch self {
        case .connected: Theme.success
        case .connecting, .reconnecting: Theme.attention
        case .bridgeOffline: .secondary
        case .hermesOffline: Theme.attention
        case .authenticationRequired: Theme.failure
        }
    }
}

extension ProfileStatus {
    var tint: Color {
        switch self {
        case .working: Theme.running
        case .idle: .secondary
        case .needsAttention: Theme.attention
        case .unavailable, .unknown: .secondary
        }
    }
}

extension ProfileTint {
    /// Mid-tone identity colors that read in both light and dark mode.
    var color: Color {
        switch self {
        case .slate: Color(red: 0.45, green: 0.50, blue: 0.56)
        case .teal: Color(red: 0.20, green: 0.58, blue: 0.58)
        case .indigo: Color(red: 0.38, green: 0.40, blue: 0.80)
        case .amber: Color(red: 0.78, green: 0.55, blue: 0.18)
        case .rose: Color(red: 0.76, green: 0.36, blue: 0.46)
        case .olive: Color(red: 0.48, green: 0.55, blue: 0.28)
        }
    }
}

extension TaskStatus {
    var tint: Color {
        switch self {
        case .triage, .todo, .scheduled, .archived: .secondary
        case .review: Theme.attention
        case .ready: .secondary
        case .inProgress: Theme.running
        case .blocked: Theme.attention
        case .completed: Theme.success
        case .failed: Theme.failure
        case .cancelled: .secondary
        }
    }
}

extension AttentionKind {
    var tint: Color {
        switch self {
        case .approval, .blockedTask: Theme.attention
        case .failedRun, .authentication: Theme.failure
        case .hostIssue: .secondary
        }
    }
}

extension LogLevel {
    var tint: Color {
        switch self {
        case .debug: .secondary
        case .info: .accentColor
        case .warning: Theme.attention
        case .error: Theme.failure
        }
    }
}

extension MCPStatus {
    var tint: Color {
        switch self {
        case .connected: Theme.success
        case .connecting: Theme.attention
        case .disconnected: .secondary
        case .error: Theme.failure
        }
    }
}

extension IntegrationStatus {
    var tint: Color {
        switch self {
        case .connected: Theme.success
        case .disconnected: .secondary
        case .error: Theme.failure
        case .notConfigured: Color(uiColor: .tertiaryLabel)
        }
    }
}
