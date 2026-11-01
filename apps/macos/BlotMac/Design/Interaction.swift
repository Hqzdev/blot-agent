import AppKit
import BlotDesign
import SwiftUI

struct KIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }

    private struct IconButtonBody: View {
        @Environment(\.isEnabled) private var enabled
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.65 : 1)
        }
    }
}

private struct KFocusRing: ViewModifier {
    let radius: CGFloat
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(focused ? K.focus : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func kFocusRing(radius: CGFloat = K.rMd) -> some View {
        modifier(KFocusRing(radius: radius))
    }
}

struct InlineFeedback: View {
    enum Tone {
        case information, success, warning, error

        /// Information and success read as secondary text; problems stay in ink and medium weight.
        var color: Color {
            switch self {
            case .information, .success: K.text2
            case .warning, .error: K.text
            }
        }

        /// A different glyph for every tone, so the tone is clear without colour.
        var icon: String {
            switch self {
            case .information: "info.circle"
            case .success: "circle-check"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }

        var weight: KFont.Weight {
            switch self {
            case .information, .success: .regular
            case .warning, .error: .medium
            }
        }

        var spokenPrefix: String {
            switch self {
            case .information: ""
            case .success: "Done: "
            case .warning: "Warning: "
            case .error: "Error: "
            }
        }

        var status: BlotStatus {
            switch self {
            case .information: .info
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
        }
    }

    let text: String
    var tone: Tone = .information

    var body: some View {
        HStack(alignment: .top, spacing: KSpace.sm) {
            KIcon(tone.icon, size: 14, color: tone.color).accessibilityHidden(true)
            Text(text).font(KFont.caption(tone.weight)).foregroundStyle(tone.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tone.spokenPrefix + text)
    }
}

struct CopyButton: View {
    let text: String
    var title = "Copy"
    var kind: KButtonKind = .ghost
    @State private var copiedText: String?
    @State private var failed = false

    private var copied: Bool { copiedText == text }

    var body: some View {
        KButton(title: failed ? "Copy failed" : copied ? "Copied" : title,
                icon: failed ? "circle-alert" : copied ? "check" : "doc.on.doc", kind: kind) {
                NSPasteboard.general.clearContents()
                let success = NSPasteboard.general.setString(text, forType: .string)
                copiedText = success ? text : nil
                failed = !success
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(failed ? "Copy failed. Try again or copy manually." : copied ? "Copied to clipboard" : title)
            .help(failed ? "Could not copy. Select the text and copy it manually." : title)
        .onChange(of: text) { _, _ in copiedText = nil; failed = false }
        .task(id: copiedText) {
            guard copiedText != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            copiedText = nil
        }
    }
}
