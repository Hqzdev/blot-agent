//
//  Surfaces.swift
//  BlotMac
//
//  Containers from agent.pen: popover cards, sheets, «Settings Group» / «Settings Row»,
//  page headers, «List Item», key–value rows, code blocks and disclosures.
//

import BlotDesign
import SwiftUI

// MARK: - Popover

extension K {
    /// Radius for menus, popovers and the command palette.
    static let rPopover: CGFloat = BlotRadius.panel
}

extension View {
    /// Floating card used by every menu and popover: panel fill and a hairline border. Elevation
    /// comes from the border only — no shadow, blur or glass.
    func kPopover(radius: CGFloat = K.rPopover) -> some View {
        blotPanel(fill: K.surface, radius: radius, border: K.borderStrong)
    }
}

// MARK: - Sheet

/// Standard modal sheet: title, optional subtitle, close button, content and a footer of actions.
/// Escape closes the sheet; the footer's primary button should use `.keyboardShortcut(.defaultAction)`.
struct KSheet<Content: View, Footer: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var subtitle: String?
    var width: CGFloat
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    init(_ title: String, subtitle: String? = nil, width: CGFloat = 520,
         @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: KSpace.md) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(KFont.sheetTitle()).foregroundStyle(K.text)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle).font(KFont.ui(13)).foregroundStyle(K.text2).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                IconButton(icon: "x", help: "Close") { dismiss() }
            }
            .padding(EdgeInsets(top: 22, leading: KSpace.xl, bottom: 18, trailing: 16))
            ViewThatFits(in: .vertical) {
                sheetContent.fixedSize(horizontal: false, vertical: true)
                ScrollView { sheetContent }
                    .scrollBounceBehavior(.basedOnSize)
            }
            HStack(spacing: KSpace.sm) {
                Spacer(minLength: 0)
                footer()
            }
            .padding(.horizontal, KSpace.xl).padding(.vertical, 14)

        }
        .frame(width: width)
        .frame(maxHeight: 640)
        .foregroundStyle(K.text)
        .onExitCommand { dismiss() }
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: KSpace.lg, content: content)
            .padding(.horizontal, KSpace.xl)
            .padding(.bottom, KSpace.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension KSheet where Footer == EmptyView {
    init(_ title: String, subtitle: String? = nil, width: CGFloat = 520,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(title, subtitle: subtitle, width: width, content: content) { EmptyView() }
    }
}

// MARK: - Settings group

/// «Settings Group»: 14 pt medium header with an optional action, then a 12 pt radius card of rows.
struct SettingsGroup<Content: View, Action: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var action: () -> Action
    @ViewBuilder var content: () -> Content

    init(title: String, detail: String? = nil, @ViewBuilder action: @escaping () -> Action,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.detail = detail
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KSpace.md) {
            HStack(alignment: .center, spacing: KSpace.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(KFont.body(.medium)).foregroundStyle(K.text)
                        .accessibilityAddTraits(.isHeader)
                    if let detail {
                        Text(detail).font(KFont.caption()).foregroundStyle(K.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                action()
            }
            .frame(minHeight: 28)
            VStack(alignment: .leading, spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: K.rLg)
        }
    }
}

extension SettingsGroup where Action == EmptyView {
    init(title: String, detail: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, detail: detail, action: { EmptyView() }, content: content)
    }
}

/// Divider between rows inside a group, inset to the row padding like agent.pen.
struct SettingsDivider: View {
    var body: some View { HDivider().padding(.horizontal, KSpace.lg) }
}

/// «Settings Row»: 13 pt medium title, 12 pt description, trailing control. Wraps the control
/// below the text when the window is too narrow.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String = ""
    @ViewBuilder var control: () -> Control

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: KSpace.xl) {
                description.frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                control().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: KSpace.md) {
                description
                control()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KSpace.lg)
        .padding(.vertical, 14)
        .frame(minHeight: 56)
        .accessibilityElement(children: .contain)
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(KFont.label()).foregroundStyle(K.text)
            if !detail.isEmpty {
                Text(detail).font(KFont.caption()).foregroundStyle(K.text2)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension SettingsRow where Control == EmptyView {
    init(title: String, detail: String = "") {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

struct SettingsChoice: View {
    let title: String
    @Binding var value: String
    let options: [String]
    var body: some View {
        ChoiceMenu(selection: $value, options: options.map { ChoiceOption(id: $0, title: $0) },
                   accessibilityTitle: title)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var detail: String = ""
    @Binding var value: Bool
    var body: some View {
        SettingsRow(title: title, detail: detail) {
            KToggle(isOn: $value).accessibilityLabel(title)
        }
    }
}

/// Padded free-form content inside a settings card (forms, explanations, lists).
struct GroupContent<Content: View>: View {
    var spacing: CGFloat = KSpace.md
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing, content: content)
            .padding(KSpace.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Page header

/// Detail page header from agent.pen («12 · Automations», «13 · Skills»): optional icon tile,
/// 28 pt title with an accessory (badge), subtitle, actions on the right.
struct PageHeader<Accessory: View, Actions: View>: View {
    var icon: String?
    let title: String
    var subtitle: String?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var actions: () -> Actions

    init(icon: String? = nil, title: String, subtitle: String? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory, @ViewBuilder actions: @escaping () -> Actions) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.actions = actions
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: KSpace.lg) {
                heading
                HStack(spacing: KSpace.sm, content: actions)
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: KSpace.lg) {
                heading
                HStack(spacing: KSpace.sm, content: actions)
            }
        }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 14) {
            if let icon { IconTile(icon: icon, size: 40, iconSize: 20).padding(.top, 2) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title).font(KFont.pageTitle()).foregroundStyle(K.text)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    accessory()
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(KFont.body()).foregroundStyle(K.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension PageHeader where Accessory == EmptyView {
    init(icon: String? = nil, title: String, subtitle: String? = nil,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.init(icon: icon, title: title, subtitle: subtitle, accessory: { EmptyView() }, actions: actions)
    }
}

extension PageHeader where Accessory == EmptyView, Actions == EmptyView {
    init(icon: String? = nil, title: String, subtitle: String? = nil) {
        self.init(icon: icon, title: title, subtitle: subtitle, accessory: { EmptyView() }, actions: { EmptyView() })
    }
}

// MARK: - List item

/// «List Item» tile: rounded square with a 16 pt glyph.
struct IconTile: View {
    let icon: String
    var size: CGFloat = K.listTileSize
    var iconSize: CGFloat = 16
    var color: Color = K.text2

    var body: some View {
        KIcon(icon, size: iconSize, color: color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size >= 40 ? 10 : K.rMd, style: .continuous).fill(K.surface2))
            .overlay(RoundedRectangle(cornerRadius: size >= 40 ? 10 : K.rMd, style: .continuous).strokeBorder(K.border, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// «List Item» from agent.pen: leading tile, 13 pt title, 12 pt subtitle, trailing slot.
/// When `action` is set the text area is a button; the trailing slot stays independent (toggles, menus).
struct ListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var selected = false
    var action: (() -> Void)?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, selected: Bool = false, action: (() -> Void)? = nil,
         @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.selected = selected
        self.action = action
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: KSpace.md) {
            if let action {
                Button(action: action) { main.contentShape(Rectangle()) }
                    .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
                    .accessibilityAddTraits(selected ? .isSelected : [])
            } else {
                main
            }
            trailing()
        }
        .padding(.vertical, 10).padding(.horizontal, KSpace.md)
        .kHover(radius: 10, active: selected)
    }

    private var main: some View {
        HStack(spacing: KSpace.md) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KFont.label()).foregroundStyle(K.text).lineLimit(2)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(KFont.caption()).foregroundStyle(K.text3).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension ListRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, selected: Bool = false, action: (() -> Void)? = nil,
         @ViewBuilder leading: @escaping () -> Leading) {
        self.init(title: title, subtitle: subtitle, selected: selected, action: action, leading: leading) { EmptyView() }
    }
}

// MARK: - Key–value

/// Label / value pair for record metadata («Channel  #task-T3» in the graph inspector).
struct KeyValueRow: View {
    let label: String
    let value: String
    var mono = false
    var labelWidth: CGFloat = 112

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: KSpace.md) {
                labelView.frame(width: labelWidth, alignment: .leading)
                valueView
            }
            VStack(alignment: .leading, spacing: KSpace.xs) {
                labelView
                valueView
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var labelView: some View {
        Text(label).font(KFont.label()).foregroundStyle(K.text2)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var valueView: some View {
        Text(value.isEmpty ? "—" : value)
            .font(mono ? KFont.mono(12) : KFont.body()).foregroundStyle(K.text)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Code block

/// «Terminal Block» from agent.pen used for any monospaced payload: header with a title and copy,
/// selectable body. Long content scrolls inside `maxHeight`.
struct CodeBlock: View {
    var title: String?
    var icon = "code"
    var meta: String?
    let text: String
    var maxHeight: CGFloat? = 260
    var copyable = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || copyable {
                HStack(spacing: KSpace.sm) {
                    KIcon(icon, size: 14, color: K.text3).accessibilityHidden(true)
                    Text(title ?? "").font(KFont.mono(12)).foregroundStyle(K.text)
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let meta { Badge(text: meta) }
                    if copyable { CopyButton(text: text).fixedSize() }
                }
                .padding(.leading, 12).padding(.trailing, 4)
                .frame(minHeight: 36)
                .kBorder(.bottom)
            }
            Group {
                if let maxHeight {
                    ScrollView([.vertical, .horizontal]) { bodyText }.frame(maxHeight: maxHeight)
                } else {
                    bodyText
                }
            }
        }
        .kCard()
    }

    private var bodyText: some View {
        Text(text.isEmpty ? " " : text)
            .font(KFont.mono(12)).foregroundStyle(K.text2).lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(K.codeBackground)
    }
}

// MARK: - Disclosure

/// Collapsible section with a rotating chevron. Content fades in below the header.
struct KDisclosure<Content: View>: View {
    @Environment(\.blotReduceMotion) private var reduceMotion
    let title: String
    var subtitle: String?
    @State private var expanded: Bool
    @ViewBuilder var content: () -> Content

    init(_ title: String, subtitle: String? = nil, expanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        _expanded = State(initialValue: expanded)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KSpace.sm) {
            Button {
                withKAnimation(reduceMotion) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    KIcon("chevron-right", size: 12, color: K.text3)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(title).font(KFont.label()).foregroundStyle(K.text2)
                    if let subtitle { Text(subtitle).font(KFont.caption()).foregroundStyle(K.text3).lineLimit(1) }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 24).contentShape(Rectangle())
            }
            .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content().transition(.kAppear) }
        }
    }
}

// MARK: - More menu

/// «…» button that opens an app-styled menu of secondary actions.
struct MoreMenu: View {
    var help = "More actions"
    let items: () -> [KMenuItem]

    var body: some View {
        KMenu(alignment: .trailing, items: items) {
            KIcon("ellipsis", size: 16, color: K.text2)
                .frame(width: K.controlHeight, height: K.controlHeight)
                .kHover(radius: K.rMd)
        }
        .fixedSize()
        .accessibilityLabel(help)
        .help(help)
    }
}
