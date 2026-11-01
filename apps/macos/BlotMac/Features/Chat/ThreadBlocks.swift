//
//  ThreadBlocks.swift
//  BlotMac
//
//  Message blocks used by both chats: agent text, user bubble, tool steps, terminal output,
//  plan, approval request, changed files and inline notes.
//

import BlotDesign
import SwiftUI

/// Callbacks a block may need. Blocks without buttons ignore them.
struct ThreadActions {
    var deny: () -> Void = {}
    var alwaysAllow: () -> Void = {}
    var runOnce: () -> Void = {}
    var review: () -> Void = {}
}

struct ThreadBlockView: View {
    let block: ThreadBlock
    var actions = ThreadActions()

    var body: some View {
        switch block {
        case .user(let text):
            UserBubble(text: text)
        case .agent(let text):
            AgentText(text: text)
        case .steps(let rows):
            StepsList(rows: rows)
        case let .terminal(command, exit, lines):
            TerminalBlock(command: command, exit: exit, lines: lines)
        case let .plan(title, items):
            PlanCard(title: title, items: items)
        case .approval(let request):
            ApprovalCard(request: request, actions: actions)
        case .changes(let files):
            ChangesCard(files: files, onReview: actions.review)
        case let .note(icon, text):
            NoteChip(icon: icon, text: text)
        }
    }
}

// MARK: - Text

struct AgentText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(KFont.body())
            .foregroundStyle(K.text)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 120)
            Text(text)
                .font(KFont.body())
                .foregroundStyle(K.text)
                .lineSpacing(4)
                .padding(.horizontal, KSpace.lg)
                .padding(.vertical, KSpace.md)
                .background(RoundedRectangle(cornerRadius: K.rMd, style: .continuous).fill(K.userMessage))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Tool steps

struct StepsList: View {
    let rows: [StepRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    KIcon(row.icon, size: 14, color: K.text3)
                    Text(row.verb)
                        .font(KFont.body())
                        .foregroundStyle(K.text2)
                    Text(row.target)
                        .font(KFont.mono(12))
                        .foregroundStyle(K.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(row.meta)
                        .font(row.meta.hasPrefix("+") ? KFont.mono(12) : KFont.body())
                        .foregroundStyle(row.metaColor)
                }
                .frame(height: 26)
            }
        }
    }
}

struct NoteChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            KIcon(icon, size: 13, color: K.text3)
            Text(text)
                .font(KFont.body())
                .foregroundStyle(K.text2)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .overlay(RoundedRectangle(cornerRadius: K.rSm, style: .continuous).strokeBorder(K.border, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Terminal

struct TerminalBlock: View {
    let command: String
    let exit: Int
    let lines: [TerminalLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                KIcon("terminal", size: 14, color: K.text3)
                Text(command)
                    .font(KFont.mono(12))
                    .foregroundStyle(K.text)
                    .lineLimit(1).truncationMode(.middle).help(command)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CopyButton(text: command).fixedSize().accessibilityHint("Copies the terminal command")
                Badge(
                    text: "exit \(exit)",
                    fg: exit == 0 ? K.success : K.danger,
                    bg: exit == 0 ? K.successBg : K.dangerBg
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .kBorder(.bottom)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines) { line in
                    lineView(line)
                }
            }
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .kCard()
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: TerminalLine) -> some View {
        switch line.tone {
        case .fail:
            // «FAIL  path» — the whole line is red in the design.
            Text(line.text).font(KFont.mono(12)).foregroundStyle(K.danger)
        case .dim:
            Text(line.text).font(KFont.mono(12)).foregroundStyle(K.text3)
        case .normal:
            Text(line.text).font(KFont.mono(12)).foregroundStyle(K.text2)
        }
    }
}

// MARK: - Plan

struct PlanCard: View {
    @Environment(\.blotReduceMotion) private var reducedMotion
    let title: String
    let items: [PlanEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(KFont.body())
                .foregroundStyle(K.text3)
                .padding(.bottom, 2)
            ForEach(items) { item in
                HStack(spacing: 10) {
                    icon(for: item.state)
                    Text(item.text)
                        .font(KFont.body())
                        .foregroundStyle(color(for: item.state))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .kCard(fill: .clear)
    }

    @ViewBuilder
    private func icon(for state: PlanState) -> some View {
        switch state {
        case .done:
            KIcon("checkmark.circle", size: 16, color: K.success)
        case .active:
            KIcon("smallcircle.filled.circle", size: 16, color: K.text)
                .symbolEffect(.pulse, options: .repeating, isActive: !reducedMotion)
        case .todo:
            KIcon("circle", size: 16, color: K.text3)
        }
    }

    private func color(for state: PlanState) -> Color {
        switch state {
        case .done: K.text2
        case .active: K.text
        case .todo: K.text3
        }
    }
}

// MARK: - Approval

struct ApprovalCard: View {
    let request: ApprovalRequest
    let actions: ThreadActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                KIcon("exclamationmark.shield", size: 16, color: K.warning)
                Text(request.title)
                    .font(KFont.body(.medium))
                    .foregroundStyle(K.text)
            }

            Text(request.command)
                .font(KFont.mono(12))
                .foregroundStyle(K.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(radius: K.rMd, fill: K.bg)
                .textSelection(.enabled)

            if let reason = request.reason {
                Text(reason)
                    .font(KFont.body())
                    .foregroundStyle(K.text2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: KSpace.sm) {
                    Spacer(minLength: 0)
                    approvalButtons
                }
                VStack(alignment: .leading, spacing: KSpace.sm) { approvalButtons }
            }
        }
        .padding(14)
        .kCard(stroke: K.borderStrong)
    }

    @ViewBuilder private var approvalButtons: some View {
        KButton(title: "Deny", icon: "xmark", action: actions.deny)
        KButton(title: request.alwaysLabel, icon: "checkmark", action: actions.alwaysAllow)
        KButton(title: "Run once", icon: "play", kind: .primary, action: actions.runOnce)
    }
}

// MARK: - Changes

struct ChangesCard: View {
    let files: [ChangedFile]
    var onReview: () -> Void = {}

    private var added: Int { files.reduce(0) { $0 + $1.added } }
    private var removed: Int { files.reduce(0) { $0 + $1.removed } }

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                header(compact: false)
                header(compact: true)
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 8))
            .kBorder(.bottom)

            VStack(spacing: 0) {
                ForEach(files) { file in
                    HStack(spacing: 8) {
                        KIcon("doc.text", size: 14, color: K.text3)
                        Text(file.path)
                            .font(KFont.mono(12))
                            .foregroundStyle(K.text)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("+\(file.added)").font(KFont.mono(12)).foregroundStyle(K.success)
                        Text("−\(file.removed)").font(KFont.mono(12)).foregroundStyle(K.danger)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .kHover(radius: K.rSm)
                }
            }
            .padding(4)
        }
        .kCard()
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: 8) {
            KIcon("arrow.triangle.pull", size: 14, color: K.text3)
            Text(compact ? "\(files.count) files" : "\(files.count) files changed")
                .font(KFont.body(.medium)).foregroundStyle(K.text).fixedSize()
            Text("+\(added) −\(removed)")
                .font(KFont.mono(12)).foregroundStyle(K.text3).fixedSize()
            Spacer(minLength: 0)
            KButton(title: "Review", icon: "eye", action: onReview).fixedSize()
        }
    }
}

// MARK: - Typing indicator

struct TypingDots: View {
    @Environment(\.blotReduceMotion) private var reducedMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.35, paused: reducedMotion)) { context in
            let phase = reducedMotion ? -1 : Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(K.text3)
                        .frame(width: 4, height: 4)
                        .opacity(reducedMotion || index == phase ? 1 : 0.35)
                }
            }
        }
        .accessibilityLabel("Waiting for a response")
    }
}
