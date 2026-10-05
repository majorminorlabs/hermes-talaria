import Foundation

/// Plain-language copy for raw backend reasons (`hermes_execution_error`,
/// `upstream_disconnected`, …). Primary UI leads with `title`/`message`; the
/// raw `code` stays available under Details for diagnosis.
nonisolated enum StatusCopy {
    struct Explanation: Hashable, Sendable {
        var title: String
        var message: String?
        /// The raw backend value, when the text shown is a translation of it.
        var code: String?
    }

    /// `snake_case` identifiers are machine reasons, not sentences.
    static func isRawCode(_ text: String) -> Bool {
        text.range(of: #"^[a-z][a-z0-9]*(_[a-z0-9]+)+$"#, options: .regularExpression) != nil
    }

    /// Explains why a run ended without completing.
    static func runFailure(_ reason: String?, cancelled: Bool = false) -> Explanation {
        let fallbackTitle = cancelled ? "Run stopped" : "Run failed"
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else {
            return Explanation(title: fallbackTitle, message: cancelled ? nil : "Hermes didn't report a reason.")
        }
        guard isRawCode(reason) else {
            // Hermes already wrote a sentence; show it as-is.
            return Explanation(title: fallbackTitle, message: reason)
        }
        if let known = known[reason] { return Explanation(title: known.0, message: known.1, code: reason) }
        return Explanation(title: fallbackTitle, message: "Hermes reported an error it didn't describe.", code: reason)
    }

    /// A sentence for secondary text: translated when it's a raw code, else unchanged.
    static func sentence(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        guard isRawCode(text) else { return text }
        return known[text]?.1 ?? known[text]?.0 ?? "Hermes reported an error it didn't describe."
    }

    private static let known: [String: (String, String)] = [
        "hermes_execution_error": ("Run failed", "Hermes could not complete this run."),
        "upstream_disconnected": ("Lost contact with Hermes", "Talaria lost its connection to Hermes while this run was active. It may have finished on your Mac."),
        "upstream_handle_missing": ("Run no longer tracked", "Hermes restarted or stopped tracking this run. Check the result on your Mac."),
        "completion_not_observed": ("Outcome unknown", "Talaria didn't see this run finish. It may have completed on your Mac."),
        "upstream_unavailable": ("Hermes unavailable", "Hermes wasn't reachable on your Mac when this run started."),
        "upstream_uncertain": ("Outcome uncertain", "Hermes may still be working. Don't repeat the request until it reports back."),
        "upstream_error": ("Hermes error", "Hermes returned an error."),
        "upstream_fifo_without_exact_target": ("Approve on your Mac", "Hermes can't safely target this approval from the phone."),
        "local_terminal_buffer_required": ("Answer in the terminal", "This input can only be typed in the terminal on your Mac."),
        "local_only_secret_input": ("Enter on your Mac", "This asks for a secret, which can only be entered on your Mac."),
        "bridge_unreachable": ("Mac Studio unavailable", "Talaria can't reach your Mac. It may be asleep, offline or off your tailnet."),
        "hermes_offline": ("Hermes not responding", "Your Mac is reachable, but Hermes isn't responding."),
        "unauthorized": ("Pairing required", "Your Mac no longer recognizes this iPhone."),
        "conversation_busy": ("Hermes is busy", "This conversation already has a run in progress."),
        "conversation_deleted": ("Conversation deleted", "This conversation was removed on your Mac."),
        "control_unavailable": ("Control unavailable", "Hermes can't accept that control for this run right now."),
        "retry_unavailable": ("Can't retry", "Hermes can't retry this run."),
        "stale_attention": ("No longer pending", "This request was already handled or expired."),
        "resync_required": ("Catching up", "Talaria is refreshing its view of Hermes."),
        "command_uncertain": ("Outcome uncertain", "Talaria couldn't confirm the command. Refresh before trying again."),
        "bot_chat_read_only": ("Read-only bot chat", "This bot's chat can only be read from the phone."),
        "bot_mode_unavailable": ("Bots unavailable", "Bot Mode isn't enabled for this Hermes."),
        "cancelled": ("Run stopped", "The run was stopped before it finished."),
    ]
}
