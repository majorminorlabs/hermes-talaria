import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Hermes

/// Presentation helpers introduced by the Talaria design pass.
@MainActor
struct TalariaDesignTests {
    // MARK: Status language

    @Test func rawRunFailuresBecomePlainLanguageAndKeepTheCode() {
        let copy = StatusCopy.runFailure("hermes_execution_error")
        #expect(copy.title == "Run failed")
        #expect(copy.message == "Hermes could not complete this run.")
        #expect(copy.code == "hermes_execution_error")

        let sentence = StatusCopy.runFailure("OpenRouter returned 429 Too Many Requests after 3 retries.")
        #expect(sentence.title == "Run failed")
        #expect(sentence.message == "OpenRouter returned 429 Too Many Requests after 3 retries.")
        #expect(sentence.code == nil)

        let unknown = StatusCopy.runFailure("some_new_backend_reason")
        #expect(unknown.title == "Run failed")
        #expect(unknown.code == "some_new_backend_reason")
        #expect(StatusCopy.runFailure(nil, cancelled: true).title == "Run stopped")
    }

    @Test func onlySnakeCaseIdentifiersCountAsRawCodes() {
        #expect(StatusCopy.isRawCode("upstream_disconnected"))
        #expect(StatusCopy.isRawCode("bridge_unreachable"))
        #expect(!StatusCopy.isRawCode("Failed"))
        #expect(!StatusCopy.isRawCode("FLY_API_TOKEN is missing"))
        #expect(!StatusCopy.isRawCode("rm generated-cache.json"))
        #expect(StatusCopy.sentence("upstream_disconnected")?.contains("lost its connection") == true)
        #expect(StatusCopy.sentence("Already a sentence.") == "Already a sentence.")
    }

    @Test func connectionStatesNameTheHost() {
        #expect(ConnectionState.bridgeOffline.label(host: "Mac Studio") == "Mac Studio unavailable")
        #expect(ConnectionState.connected.label(host: "Mac Studio") == "Connected")
        #expect(ConnectionState.bridgeOffline.diagnosticCode == "bridge_unreachable")
        #expect(!ConnectionState.bridgeOffline.explanation.contains("hermes-mobile-bridge"))
    }

    // MARK: Transcript

    @Test func toolHistoryRowsCollapseIntoOneGroupMergedByCallID() {
        func toolRow(_ id: String, _ call: ToolCall) -> Message {
            Message(id: id, conversationID: "c", role: .assistant, parts: [.tools([call])])
        }
        let messages = [
            Message(id: "u", conversationID: "c", role: .user, parts: [.markdown("Search for Hermes")]),
            toolRow("m1", ToolCall(id: "call-1", kind: .skills, name: "skill_view", summary: "Skill View", input: #"{"name":"research-terminal"}"#, status: .completed)),
            toolRow("m2", ToolCall(id: "call-1", kind: .skills, name: "skill_view", summary: "Skill View", output: "loaded", status: .completed)),
            toolRow("m3", ToolCall(id: "call-2", kind: .terminal, name: "terminal", summary: "Terminal", input: #"{"command":"rt search Hermes"}"#, status: .completed)),
            toolRow("m4", ToolCall(id: "call-2", kind: .terminal, name: "terminal", summary: "Terminal", output: "exit 1", status: .failed)),
            Message(id: "a", conversationID: "c", role: .assistant, parts: [.markdown("Done")]),
        ]
        let items = TranscriptItem.build(messages)
        #expect(items.count == 3)
        guard case .tools(_, let calls) = items[1] else { Issue.record("expected one tool group"); return }
        #expect(calls.map(\.id) == ["call-1", "call-2"])
        #expect(calls[0].input?.contains("research-terminal") == true)
        #expect(calls[0].output == "loaded")
        #expect(calls[1].status == .failed)
        #expect(calls[0].preview == "research-terminal")
        #expect(calls[1].preview == "rt search Hermes")
    }

    @Test func messagesWithTextAreNeverFoldedIntoToolGroups() {
        let live = Message(id: "live", conversationID: "c", role: .assistant,
                           parts: [.tools([ToolCall(kind: .web, name: "web", summary: "Searched")]), .markdown("")])
        #expect(!live.isToolOnly)
        #expect(TranscriptItem.build([live]).count == 1)

        // A run's in-flight bubble may have tool activity and no text yet; it
        // stays a message so its live block and approval controls render.
        let inFlight = Message(id: "run-msg", conversationID: "c", role: .assistant,
                               parts: [.tools([ToolCall(kind: .terminal, name: "terminal", summary: "Ran make", status: .running)])],
                               runID: "r-live")
        #expect(inFlight.isToolOnly)
        guard case .message = TranscriptItem.build([inFlight]).first else {
            Issue.record("a run's live message must not fold into a tool group"); return
        }
    }

    // MARK: Identity

    @Test func identityHueMatchesHermesDesktop() {
        // Desktop profileColor(): hash = hash * 31 + charCode (uint32), hue = hash % 360.
        func desktopHue(_ key: String) -> Double {
            var hash: UInt32 = 0
            for unit in key.utf16 { hash = hash &* 31 &+ UInt32(unit) }
            return Double(hash % 360) / 360
        }
        for key in ["research-orchestrator", "research-worker", "atlas", "Ünïcode-bot"] {
            #expect(IdentityColor.hue(for: key) == desktopHue(key))
        }
        #expect(IdentityColor.hue(for: "research-orchestrator") != IdentityColor.hue(for: "research-worker"))
    }

    @Test func versionsShortenCommitHashesOnly() {
        #expect(Format.version("4bb9e57bfde8a0affb5553eff13ed6e1f14147f1") == "4bb9e57")
        #expect(Format.version("0.21.5+6627.g4bb9e57") == "0.21.5+6627.g4bb9e57")
        #expect(Format.lastActive(Date.now.addingTimeInterval(-3_221)) == "Active 53m ago")
    }

    // MARK: Rendering safety

    @Test func bridgeRetryControlOverridesRunStateDefaults() {
        for state in ["complete", "running", "failed", "cancelled"] {
            for allowed in [true, false] {
                let run = BridgeMapping.run(.object([
                    "id": .string("retry-fixture"), "state": .string(state),
                    "controls": .object(["retry": .bool(allowed)])
                ]), hostID: "fixture")
                #expect(run.canRetry == allowed)
            }
        }
    }

    @Test func adaptiveStatusColorsResolveOffTheMainThread() async {
        // SwiftUI resolves dynamic colors on its render thread; the provider
        // must not assert MainActor isolation there.
        let color = Theme.adaptiveUIColor(light: 0xCF2D56, dark: 0xE75E78)
        let (dark, light) = await Task.detached {
            (color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
             color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        }.value
        var darkRed: CGFloat = 0, lightRed: CGFloat = 0
        dark.getRed(&darkRed, green: nil, blue: nil, alpha: nil)
        light.getRed(&lightRed, green: nil, blue: nil, alpha: nil)
        #expect(abs(darkRed - 0xE7 / 255.0) < 0.01)
        #expect(abs(lightRed - 0xCF / 255.0) < 0.01)
    }
    @Test func secondaryTextContrastOnPanelsAndAttentionWash() {
        func components(_ color: UIColor, style: UIUserInterfaceStyle) -> (Double,Double,Double,Double) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b), Double(a))
        }
        func luminance(_ rgb: [Double]) -> Double { let c = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }; return c[0]*0.2126 + c[1]*0.7152 + c[2]*0.0722 }
        for style in [UIUserInterfaceStyle.light,.dark] {
            let text = components(Theme.adaptiveUIColor(light: 0x55545E,dark: 0xB9B7C2), style: style)
            let panel = components(.secondarySystemBackground, style: style)
            let wash = components(Theme.adaptiveUIColor(light: 0xB9530C,dark: 0xF5A04A),style:style)
            let alpha = style == .dark ? 0.12 : 0.07
            for background in [[panel.0,panel.1,panel.2], [wash.0*alpha + panel.0*(1-alpha),wash.1*alpha + panel.1*(1-alpha),wash.2*alpha + panel.2*(1-alpha)]] {
                let a = luminance([text.0,text.1,text.2]), b = luminance(background)
                #expect((max(a,b)+0.05)/(min(a,b)+0.05) >= 4.5)
            }
        }
    }

}
