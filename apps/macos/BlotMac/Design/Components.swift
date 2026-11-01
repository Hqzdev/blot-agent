//
//  Components.swift
//  BlotMac
//
//  Reusable building blocks from agent.pen → «Components — Atoms / Rows / Blocks / Shell».
//

import BlotDesign
import SwiftUI

// MARK: - Icon

/// Hugeicons icons from agent.pen, bundled as vector template PDFs in Icons.xcassets
/// (`hugeicons-<name>`). Call sites may pass either a Hugeicons name (kebab-case key) («square-pen») or the
/// SF Symbol name used earlier («square.and.pencil»); unknown names fall back to SF Symbols.
enum HugeIcons {
    static let fromSFSymbol: [String: String] = [
        "terminal": "terminal",
        "plus": "plus",
        "minus": "minus",
        "pencil": "pencil",
        "doc.text": "file-text",
        "sidebar.left": "panel-left",
        "sidebar.right": "panel-right",
        "magnifyingglass": "search",
        "bubble.left": "message-square",
        "bubble.left.and.bubble.right": "messages-square",
        "xmark": "x",
        "square.and.pencil": "square-pen",
        "puzzlepiece.extension": "puzzle",
        "line.3.horizontal.decrease": "list-filter",
        "envelope": "mail",
        "clock": "clock",
        "checkmark.circle": "circle-check",
        "checkmark": "check",
        "arrow.triangle.pull": "git-pull-request",
        "arrow.triangle.branch": "workflow",
        "point.3.connected.trianglepath.dotted": "network",
        "waveform.path.ecg": "activity",
        "stop": "square",
        "sparkle": "sparkle",
        "smallcircle.filled.circle": "circle-dot",
        "circle": "circle",
        "play": "play",
        "pause": "pause",
        "person": "user",
        "person.2": "users",
        "person.badge.plus": "user-plus",
        "mic": "mic",
        "lock": "lock",
        "list.bullet": "list",
        "gearshape": "settings",
        "gauge.with.dots.needle.33percent": "gauge",
        "flag": "flag",
        "eye": "eye",
        "exclamationmark.shield": "shield-alert",
        "checkmark.shield": "shield-check",
        "exclamationmark.circle": "circle-alert",
        "ellipsis": "ellipsis",
        "cursorarrow.click": "mouse-pointer-click",
        "chevron.down": "chevron-down",
        "chevron.up": "chevron-up",
        "bell": "bell",
        "arrow.up.left.and.arrow.down.right": "maximize-2",
        "arrow.up": "arrow-up",
        "arrow.right": "arrow-right",
        "folder": "folder",
        "folder.fill": "folder-open",
        "square.grid.2x2": "grid-2x2",
        "server": "server",
        "desktopcomputer": "laptop",
        "display": "monitor",
        "rectangle.portrait.and.arrow.right": "log-out",
        "bolt": "zap",
        "arrow.counterclockwise": "rotate-ccw",
        "chevron.left": "chevron-left",
        "chevron.right": "chevron-right",
        "trash": "trash-2",
        "keyboard": "keyboard",
        "cpu": "cpu",
        "globe": "globe",
        "shield": "shield",
        "key": "key",
        "sun.max": "sun",
        "chart.bar": "chart-bar",
        "slider.horizontal.3": "sliders-horizontal",
        "chevron.left.forwardslash.chevron.right": "code",
        "arrow.up.right.square": "square-arrow-out-up-right",
    ]

    /// Kebab-case names bundled as `hugeicons-<name>` that have no SF Symbol alias above.
    private static let extra: Set<String> = ["git-branch", "laptop", "monitor", "log-out", "zap", "rotate-ccw",
                                             "chevron-left", "chevron-right", "trash-2", "sun", "chart-bar",
                                             "sliders-horizontal", "code", "square-arrow-out-up-right"]

    private static let bundled = Set(fromSFSymbol.values).union(extra)

    /// Asset name for a Hugeicons or SF Symbol name, or nil if there is no Hugeicons equivalent.
    static func asset(for name: String) -> String? {
        if bundled.contains(name) { return "hugeicons-" + name }
        return fromSFSymbol[name].map { "hugeicons-" + $0 }
    }
}

/// Hugeicons glyph that takes the surrounding foreground style (for buttons and chips).
struct HugeIconImage: View {
    let name: String
    var size: CGFloat = 16

    init(_ name: String, size: CGFloat = 16) {
        self.name = name
        self.size = size
    }

    var body: some View {
        if let asset = HugeIcons.asset(for: name) {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: name)
                .font(.system(size: size * 0.82))
                .frame(width: size, height: size)
        }
    }
}

struct KIcon: View {
    let name: String
    var size: CGFloat = 16
    var color: Color = K.text2
    var weight: Font.Weight = .regular

    init(_ name: String, size: CGFloat = 16, color: Color = K.text2, weight: Font.Weight = .regular) {
        self.name = name
        self.size = size
        self.color = color
        self.weight = weight
    }

    var body: some View {
        HugeIconImage(name, size: size)
            .fontWeight(weight)
            .foregroundStyle(color)
    }
}

// MARK: - Hover

struct HoverBackground: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    var radius: CGFloat = K.rMd
    var active: Bool = false
    var activeFill: Color = K.selected
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(active ? activeFill : (hovering && enabled ? K.hover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
    }
}

extension View {
    func kHover(radius: CGFloat = K.rMd, active: Bool = false, activeFill: Color = K.selected) -> some View {
        modifier(HoverBackground(radius: radius, active: active, activeFill: activeFill))
    }

    /// Card with a 1 px border, used for groups, terminal blocks and lists.
    func kCard(radius: CGFloat = K.rLg, fill: Color = K.surface, stroke: Color = K.border) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// 1 px separator on one edge.
    func kBorder(_ edge: Edge, color: Color = K.border) -> some View {
        overlay(alignment: edge.alignment) {
            Rectangle()
                .fill(color)
                .frame(
                    width: edge == .leading || edge == .trailing ? 1 : nil,
                    height: edge == .top || edge == .bottom ? 1 : nil
                )
        }
    }
}

private extension Edge {
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

// MARK: - Button

enum KButtonKind {
    case standard   // panel fill + hairline border
    case primary    // ink fill (paper in the dark theme)
    case ghost      // no fill until hover
    case danger     // destructive: bordered, semibold label; pair with a clear verb or icon
}

/// Neutral bordered buttons from BlotDesign: fill and outline show hover, press, focus and
/// disabled states; nothing is tinted.
struct KButtonStyle: ButtonStyle {
    var kind: KButtonKind = .standard
    var height: CGFloat = K.controlHeight
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        BlotButtonStyle(kind.blotKind, size: height >= K.controlHeightLarge ? .large : height < K.controlHeight ? .compact : .regular,
                        fullWidth: fullWidth)
            .makeBody(configuration: configuration)
    }
}

extension KButtonKind {
    var blotKind: BlotButtonKind {
        switch self {
        case .standard: .secondary
        case .primary: .primary
        case .ghost: .ghost
        case .danger: .destructive
        }
    }
}

/// «Button» from agent.pen: 32 pt, 13 pt medium label, optional 14 pt leading icon.
/// `loading` swaps the icon for a spinner and blocks repeated presses.
struct KButton: View {
    let title: String
    var icon: String?
    var kind: KButtonKind = .standard
    var height: CGFloat = K.controlHeight
    var loading = false
    var fullWidth = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if loading {
                    ProgressView().controlSize(.mini)
                        .tint(kind == .primary ? K.onInverse : K.text2)
                        .frame(width: 14, height: 14)
                } else if let icon {
                    HugeIconImage(icon, size: 14)
                }
                Text(title).lineLimit(1)
            }
        }
        .buttonStyle(KButtonStyle(kind: kind, height: height, fullWidth: fullWidth))
        .disabled(loading)
        .kFocusRing()
        .accessibilityLabel(loading ? "\(title), in progress" : title)
    }
}

/// «Icon Button» from agent.pen: 28 × 28, radius 6, 16 pt glyph.
struct IconButton: View {
    let icon: String
    var size: CGFloat = K.iconButtonSize
    var iconSize: CGFloat = 16
    var color: Color = K.text2
    var active = false
    var help: String?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            KIcon(icon, size: iconSize, color: active ? K.text : color)
                .frame(width: size, height: size)
        }
        .buttonStyle(BlotIconButtonStyle(size: size, selected: active))
        .kFocusRing(radius: K.rMd)
        .accessibilityLabel(help?.kSpokenTitle ?? icon)
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(help ?? "")
    }
}

/// Ink send button with an arrow from BlotDesign. Shows a spinner while a message is being sent.
struct SendButton: View {
    var enabled = true
    var sending = false
    var size: CGFloat = 28
    var action: () -> Void = {}

    var body: some View {
        BlotSendButton(phase: sending ? .sending : .ready, size: size, action: action)
            .disabled(!enabled || sending)
            .kFocusRing(radius: K.rMd)
            .help(sending ? "Отправка…" : enabled ? "Отправить · Return" : "Введите сообщение")
    }
}

// MARK: - Chip / Badge / Dot

/// «Chip» from agent.pen: 28 pt, 13 pt label, optional icon and chevron.
struct Chip: View {
    var icon: String?
    let label: String
    var chevron = true
    var color: Color = K.text2
    var bordered = false
    var mono = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon { KIcon(icon, size: 14, color: color) }
            Text(label)
                .font(mono ? KFont.mono(12) : KFont.ui(13))
                .foregroundStyle(color)
                .lineLimit(1)
            if chevron {
                KIcon("chevron-down", size: 12, color: K.text3)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .overlay {
            if bordered {
                RoundedRectangle(cornerRadius: K.rMd, style: .continuous).strokeBorder(K.border, lineWidth: 1)
            }
        }
        .kHover(radius: K.rMd)
    }
}

/// Chip that opens an app-styled menu (`KMenu`).
struct MenuChip: View {
    var icon: String?
    let label: String
    var bordered = false
    var color: Color = K.text2
    let items: () -> [KMenuItem]

    var body: some View {
        KMenu(items: items) {
            Chip(icon: icon, label: label, color: color, bordered: bordered)
        }
        .fixedSize()
    }
}

/// Tag: mono label on the tag fill with square corners.
struct Badge: View {
    let text: String
    var fg: Color = K.text
    var bg: Color = BlotColor.tag

    var body: some View {
        Text(text)
            .font(KFont.mono(11, .medium))
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Rectangle().fill(bg))
            .lineLimit(1)
            .fixedSize()
    }
}

struct StatusDot: View {
    var color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

// MARK: - Toggle

/// Native switch preserves keyboard, accessibility and appearance behavior.
struct KToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Enabled", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(K.inverse)
    }
}

// MARK: - Segmented control

struct KSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    var label: (Option) -> String
    var title = "View"

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Sidebar rows

/// «Sidebar Item» from agent.pen: 29 pt row, 16 pt icon, 14 pt label, 12 pt meta, radius 6.
/// `indented` rows (tasks under a project) align with the parent's label and use secondary text.
struct SidebarItem: View {
    var icon: String?
    let label: String
    var meta: String?
    var metaColor: Color = K.text3
    var dot: Color?
    var active = false
    var indented = false
    var labelColor: Color?
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    KIcon(icon, size: 16, color: active ? K.text : K.text2)
                }
                Text(label)
                    .font(KFont.label(active ? .medium : .regular))
                    .foregroundStyle(labelColor ?? (active || !indented ? K.text : K.text2))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let dot {
                    StatusDot(color: dot, size: 6).accessibilityHidden(true)
                } else if let meta {
                    Text(meta).font(KFont.caption()).foregroundStyle(metaColor).lineLimit(1)
                }
            }
            .padding(.leading, indented ? 34 : 10)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(minHeight: K.sidebarRowHeight)
            .contentShape(Rectangle())
            .kHover(radius: K.rMd, active: active)
        }
        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rMd)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// «Section Label» from agent.pen: 12 pt medium, tertiary, optional trailing action.
struct SectionLabel: View {
    let title: String
    var actionIcon: String?
    var actionHelp: String?
    var action: () -> Void = {}

    var body: some View {
        HStack {
            Text(title)
                .font(KFont.caption(.medium))
                .foregroundStyle(K.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let actionIcon {
                IconButton(icon: actionIcon, size: 20, iconSize: 14, color: K.text3, help: actionHelp ?? title, action: action)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 10, bottom: 6, trailing: 6))
    }
}

/// Collapsible «Section Label» (Pinned, Archived).
struct SectionDisclosure: View {
    let title: String
    @Binding var expanded: Bool
    var help: String?

    var body: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 4) {
                Text(title).font(KFont.caption(.medium)).foregroundStyle(K.text3)
                KIcon("chevron-down", size: 10, color: K.text3)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                Spacer(minLength: 0)
            }
            .padding(EdgeInsets(top: 16, leading: 10, bottom: 6, trailing: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
        .kAnimation(KMotion.quick, value: expanded)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .help(help ?? "")
    }
}

// MARK: - Avatars and brand

/// Role avatar from agent.pen («Face 34 / …»): the role's Blot in a circle, no motion.
struct FaceAvatar: View {
    let role: AgentRole
    var size: CGFloat = 32

    var body: some View {
        BlotDrawing(role: role.blotRole, framing: .avatar)
            .frame(width: size, height: size)
            .accessibilityLabel(role.title)
    }
}

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 24
    var fill: Color = K.surface2
    var foreground: Color = K.text2
    var bordered = true
    var weight: KFont.Weight = .semibold

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: weight.system))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(bordered ? K.border : .clear, lineWidth: 1))
    }
}

// MARK: - Misc

struct HDivider: View {
    var color: Color = K.border
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

struct VDivider: View {
    var color: Color = K.border
    var body: some View { Rectangle().fill(color).frame(width: 1) }
}

extension String {
    /// Tooltip text without its shortcut suffix («Hide sidebar · ⌃⌘S» → «Hide sidebar»), for
    /// accessibility labels. The shortcut stays in the tooltip and the menu bar.
    var kSpokenTitle: String {
        guard let range = range(of: " · ") else { return self }
        return String(self[..<range.lowerBound])
    }
}

/// Text with `seconds` formatted like «1m 12s».
func formatDuration(_ seconds: Int) -> String {
    let m = seconds / 60
    let s = seconds % 60
    return m > 0 ? "\(m)m \(s)s" : "\(s)s"
}
