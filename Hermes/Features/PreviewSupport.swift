import SwiftUI

/// Wraps a preview in a fully wired mock environment using throwaway storage.
struct PreviewEnvironment: ViewModifier {
    @State private var environment = AppEnvironment.mock(storage: .ephemeral)

    func body(content: Content) -> some View {
        content
            .environment(environment)
            .injectStores(from: environment)
            .toastOverlay()
            .task { await environment.start() }
    }
}

extension View {
    func previewEnvironment() -> some View { modifier(PreviewEnvironment()) }
}
