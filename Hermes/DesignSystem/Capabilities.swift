import SwiftUI

/// Shown in place of a feature the connected host doesn't offer.
struct CapabilityUnavailableView: View {
    var capability: HermesCapability

    var body: some View {
        ContentUnavailableView {
            Label("\(capability.label) Unavailable", systemImage: capability.symbol)
        } description: {
            Text("Your Mac doesn't offer this yet. Updating Hermes or its bridge may enable it.")
        }
    }
}

/// Renders `content` only when the host supports `capability`. While the
/// app has never heard from the host, it shows progress instead of claiming
/// the feature is unsupported.
struct CapabilityGate<Content: View>: View {
    var capability: HermesCapability
    @ViewBuilder var content: () -> Content

    @Environment(ConnectionStore.self) private var connection

    var body: some View {
        if connection.supports(capability) {
            content()
        } else if connection.capabilities.isEmpty && connection.status.lastSeen == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            CapabilityUnavailableView(capability: capability)
        }
    }
}
