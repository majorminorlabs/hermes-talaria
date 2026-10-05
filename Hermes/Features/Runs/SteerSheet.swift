import SwiftUI

/// Sends an instruction to a run that's already executing.
struct SteerSheet: View {
    var run: Run

    @Environment(ActivityStore.self) private var activity
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    private let suggestions = ["Wrap up and summarize", "Skip the tests", "Show me before writing files", "Focus on the main question"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(run.title).font(.headline)
                    if let action = run.currentAction {
                        Label(action, systemImage: "circle.dotted")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Tell Hermes what to change…", text: $instruction, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($focused)
                    .padding(12)
                    .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { instruction = suggestion }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                        }
                    }
                }

                Text("Hermes picks up the instruction at its next step. The run keeps going; nothing restarts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Send Instruction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        sending = true
        Task {
            do {
                try await activity.steer(run.id, instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines))
                toasts.show("Instruction sent", symbol: "arrow.turn.down.right")
                dismiss()
            } catch {
                toasts.show(error: error)
            }
            sending = false
        }
    }
}
