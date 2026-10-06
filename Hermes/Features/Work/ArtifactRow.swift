import SwiftUI
struct ArtifactRow: View {
    let file: FileAttachment
    let download: () -> Void
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        Button(action: download) { FileAttachmentView(file: file) }.buttonStyle(.plain)
            .accessibilityHint("Downloads and previews the file")
            .contextMenu {
                Button("Open", action: download)
                Button("Capture reference") { environment.router.captureSeed = CaptureSeed(text: "Artifact: \(file.name)\nID: \(file.id)") }
                Button("Ask another agent…") { environment.router.askSeed = AskSeed(text: "About artifact \(file.name) (\(file.id)): ") }
            }
    }
}
