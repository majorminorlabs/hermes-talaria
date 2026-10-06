import SwiftUI

/// Local-only UI preferences. Nothing here is canonical Hermes state.
@Observable
final class AppPreferences {
    let defaults: UserDefaults

    var reviewVoiceBeforeSending: Bool {
        get { defaults.bool(forKey: "vnext.reviewVoiceBeforeSending") }
        set { defaults.set(newValue, forKey: "vnext.reviewVoiceBeforeSending") }
    }
    var recentModels: [ModelRef] { didSet { defaults.set(try? JSONEncoder().encode(recentModels), forKey: "vnext.recentModels") } }
    func rememberModel(_ model: ModelRef?) { guard let model else { return }; recentModels = [model] + recentModels.filter { $0.id != model.id || $0.provider != model.provider }.prefix(4) }
    var appearance: AppearancePreference { didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) } }
    var defaultProfileID: String? { didSet { defaults.set(defaultProfileID, forKey: Keys.defaultProfile) } }
    var defaultReasoning: ReasoningLevel { didSet { defaults.set(defaultReasoning.rawValue, forKey: Keys.reasoning) } }
    var showDeveloperDiagnostics: Bool { didSet { defaults.set(showDeveloperDiagnostics, forKey: Keys.developer) } }
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Keys.notifications) } }
    private(set) var enabledNotificationCategories: Set<NotificationCategory> {
        didSet { defaults.set(enabledNotificationCategories.map(\.rawValue), forKey: Keys.notificationCategories) }
    }
    /// Failed runs the user has dismissed from Needs Attention.
    private(set) var acknowledgedRunIDs: Set<String> {
        didSet { defaults.set(Array(acknowledgedRunIDs), forKey: Keys.acknowledged) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recentModels = defaults.data(forKey: "vnext.recentModels").flatMap { try? JSONDecoder().decode([ModelRef].self, from: $0) } ?? []
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        defaultProfileID = defaults.string(forKey: Keys.defaultProfile)
        defaultReasoning = ReasoningLevel(rawValue: defaults.string(forKey: Keys.reasoning) ?? "") ?? .medium
        showDeveloperDiagnostics = defaults.object(forKey: Keys.developer) as? Bool ?? true
        notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        if let stored = defaults.stringArray(forKey: Keys.notificationCategories) {
            enabledNotificationCategories = Set(stored.compactMap(NotificationCategory.init(rawValue:)))
        } else {
            enabledNotificationCategories = Set(NotificationCategory.allCases.filter(\.defaultEnabled))
        }
        acknowledgedRunIDs = Set(defaults.stringArray(forKey: Keys.acknowledged) ?? [])
    }

    func isEnabled(_ category: NotificationCategory) -> Bool {
        notificationsEnabled && enabledNotificationCategories.contains(category)
    }

    func setEnabled(_ enabled: Bool, for category: NotificationCategory) {
        if enabled { enabledNotificationCategories.insert(category) } else { enabledNotificationCategories.remove(category) }
    }

    func acknowledge(runID: String) { acknowledgedRunIDs.insert(runID) }

    func resetLocalState() {
        acknowledgedRunIDs = []
    }

    private enum Keys {
        static let appearance = "pref.appearance"
        static let haptics = "pref.haptics"
        static let defaultProfile = "pref.defaultProfile"
        static let reasoning = "pref.reasoning"
        static let developer = "pref.developer"
        static let notifications = "pref.notifications"
        static let notificationCategories = "pref.notificationCategories"
        static let acknowledged = "state.acknowledgedRuns"
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
