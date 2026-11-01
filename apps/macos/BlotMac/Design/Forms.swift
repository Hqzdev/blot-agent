//
//  Forms.swift
//  BlotMac
//
//  Input controls from agent.pen («Text Field», «Chip» used as a picker) shared by every screen:
//  single-line fields, multi-line editors, search fields, choice menus and selectable chips.
//

import AppKit
import BlotDesign
import SwiftUI

// MARK: - Field chrome

/// Border and fill shared by every text input: canvas fill, hairline border, 2 pt ink ring on
/// focus, dashed 2 pt ink border on error (the message below names the problem).
private struct FieldChrome: ViewModifier {
    let focused: Bool
    let invalid: Bool
    var radius: CGFloat = K.rMd

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(K.bg))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(invalid || focused ? K.focus : K.borderStrong,
                                  style: StrokeStyle(lineWidth: focused || invalid ? 2 : 1, dash: invalid && !focused ? [4, 3] : []))
            )
            .kAnimation(KMotion.quick, value: focused)
    }
}

/// Label above a field, with an optional trailing link («Forgot password?»).
private struct FieldLabel: View {
    let title: String
    var required = false
    var trailing: FieldLink?

    var body: some View {
        HStack {
            Text(title + (required ? " *" : "")).font(KFont.caption(.medium)).foregroundStyle(K.text2)
            Spacer(minLength: 8)
            if let trailing { TextLink(title: trailing.title, size: 12, action: trailing.action) }
        }
    }
}

struct FieldLink {
    let title: String
    let action: () -> Void
}

// MARK: - Text field

/// «Text Field» from agent.pen. 32 pt by default, 40 pt for auth and sheet forms.
/// Shows a required-field message after the user leaves an empty required field.
struct KTextField: View {
    let label: String?
    @Binding var text: String
    var placeholder: String
    var icon: String?
    var secure: Bool
    var mono: Bool
    var large: Bool
    var required: Bool
    var error: String?
    var invalid: Bool
    var hint: String?
    var autofocus: Bool
    var contentType: NSTextContentType?
    var trailingLink: FieldLink?
    var onSubmit: () -> Void

    @FocusState private var focused: Bool
    @State private var edited = false

    init(_ label: String? = nil, text: Binding<String>, placeholder: String = "", icon: String? = nil,
         secure: Bool = false, mono: Bool = false, large: Bool = false, required: Bool = false,
         error: String? = nil, invalid: Bool = false, hint: String? = nil, autofocus: Bool = false,
         contentType: NSTextContentType? = nil, trailingLink: FieldLink? = nil,
         onSubmit: @escaping () -> Void = {}) {
        self.label = label
        _text = text
        self.placeholder = placeholder
        self.icon = icon
        self.secure = secure
        self.mono = mono
        self.large = large
        self.required = required
        self.error = error
        self.invalid = invalid
        self.hint = hint
        self.autofocus = autofocus
        self.contentType = contentType
        self.trailingLink = trailingLink
        self.onSubmit = onSubmit
    }

    private var validation: String? {
        if let error { return error }
        let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return required && edited && !focused && empty ? "\(label ?? "This field") is required." : nil
    }

    private var font: Font { mono ? KFont.mono(12) : large ? KFont.body() : KFont.ui(13) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label { FieldLabel(title: label, required: required, trailing: trailingLink) }
            HStack(spacing: 8) {
                if let icon { KIcon(icon, size: 14, color: K.text3).accessibilityHidden(true) }
                Group {
                    if secure {
                        SecureField("", text: $text, prompt: prompt)
                    } else {
                        TextField("", text: $text, prompt: prompt)
                    }
                }
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(K.text)
                .textContentType(contentType)
                .focused($focused)
                .onSubmit(onSubmit)
                .accessibilityLabel(label ?? placeholder)
                .accessibilityHint(validation ?? hint ?? (invalid ? "Check this field" : required ? "Required" : ""))
            }
            .padding(.horizontal, large ? 12 : 10)
            .padding(.vertical, 4)
            .frame(minHeight: large ? K.controlHeightLarge : K.controlHeight)
            .modifier(FieldChrome(focused: focused, invalid: invalid || validation != nil))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            if let validation {
                InlineFeedback(text: validation, tone: .error).transition(.kAppear)
            } else if let hint {
                Text(hint).font(KFont.caption()).foregroundStyle(K.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .kAnimation(KMotion.quick, value: validation)
        .onChange(of: focused) { _, value in if value { edited = true } }
        .onAppear { if autofocus { focused = true } }
    }

    private var prompt: Text { Text(placeholder).foregroundColor(K.disabled) }
}

// MARK: - Text area

/// Multi-line editor with the same chrome as `KTextField` and a placeholder.
struct KTextArea: View {
    let label: String?
    @Binding var text: String
    var placeholder = ""
    var mono = false
    var minHeight: CGFloat = 120
    var maxHeight: CGFloat?
    var error: String?
    var hint: String?
    @FocusState private var focused: Bool

    init(_ label: String? = nil, text: Binding<String>, placeholder: String = "", mono: Bool = false,
         minHeight: CGFloat = 120, maxHeight: CGFloat? = nil, error: String? = nil, hint: String? = nil) {
        self.label = label
        _text = text
        self.placeholder = placeholder
        self.mono = mono
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.error = error
        self.hint = hint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label { FieldLabel(title: label) }
            TextEditor(text: $text)
                .font(mono ? KFont.mono(12) : KFont.ui(13))
                .foregroundStyle(K.text)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(mono ? KFont.mono(12) : KFont.ui(13)).foregroundStyle(K.text3)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .frame(minHeight: minHeight, maxHeight: maxHeight)
                .modifier(FieldChrome(focused: focused, invalid: error != nil))
                .accessibilityLabel(label ?? placeholder)
            if let error {
                InlineFeedback(text: error, tone: .error)
            } else if let hint {
                Text(hint).font(KFont.caption()).foregroundStyle(K.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Search field

/// Sidebar and page search: 32 pt, search glyph, clear button once there is text.
struct KSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            KIcon("search", size: 14, color: K.text3).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(K.text3))
                .textFieldStyle(.plain).font(KFont.ui(13)).foregroundStyle(K.text)
                .focused($focused)
                .onSubmit(onSubmit)
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                IconButton(icon: "x", size: 20, iconSize: 12, color: K.text3, help: "Clear search") { text = "" }
                    .transition(.opacity)
            }
        }
        .padding(.leading, 10).padding(.trailing, 6)
        .padding(.vertical, 4)
        .frame(minHeight: K.controlHeight)
        .background(RoundedRectangle(cornerRadius: K.rMd, style: .continuous).fill(K.surface2))
        .overlay(RoundedRectangle(cornerRadius: K.rMd, style: .continuous)
            .strokeBorder(focused ? K.focus : K.border, lineWidth: focused ? 2 : 1))
        .kAnimation(KMotion.quick, value: text.isEmpty)
    }
}

// MARK: - Choice menu

struct ChoiceOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
}

/// Single choice shown as a bordered «Chip» that opens an app-styled menu.
struct ChoiceMenu<ID: Hashable>: View {
    @Binding var selection: ID
    let options: [ChoiceOption<ID>]
    var placeholder = "Choose"
    var accessibilityTitle: String?

    private var current: String? { options.first { $0.id == selection }?.title }

    var body: some View {
        Picker(accessibilityTitle ?? placeholder, selection: $selection) {
            if current == nil {
                Text(placeholder).tag(selection).disabled(true)
            }
            ForEach(options) { option in
                Text(option.title).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityValue(current ?? "None")
    }
}

// MARK: - Toggle chip

/// Multi-select pill (weekdays, roles). Shows a check and a filled background when on.
struct KToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.blotReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withKAnimation(reduceMotion, KMotion.quick) { isOn.toggle() }
        } label: {
            HStack(spacing: 5) {
                if isOn { KIcon("check", size: 12, color: K.text) }
                Text(title).font(KFont.ui(13, isOn ? .medium : .regular)).foregroundStyle(isOn ? K.text : K.text2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: K.rMd, style: .continuous).fill(isOn ? K.selected : .clear))
            .overlay(RoundedRectangle(cornerRadius: K.rMd, style: .continuous)
                .strokeBorder(isOn ? K.borderStrong : K.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rMd)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Text link

/// Inline text button that underlines on hover (auth screens, field labels).
struct TextLink: View {
    let title: String
    var color: Color = K.text2
    var weight: KFont.Weight = .regular
    var size: CGFloat = 13
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KFont.ui(size, weight))
                .foregroundStyle(color)
                .underline(hovering)
        }
        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
        .onHover { hovering = $0 }
    }
}
