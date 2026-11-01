//
//  States.swift
//  BlotMac
//
//  Shared views for data states: status badges for backend records, empty / loading / error
//  states, top-of-window banners and short-lived toasts. Status is never shown by colour alone:
//  every badge pairs a dot with a text label.
//

import Observation
import BlotDesign
import SwiftUI

// MARK: - Status

enum StatusTone: Equatable {
    case neutral, active, success, attention, failure

    /// Monochrome: problems are ink, everything else secondary. The icon and label carry meaning.
    var color: Color {
        switch self {
        case .neutral, .active, .success: K.text2
        case .attention, .failure: K.text
        }
    }

    var background: Color {
        switch self {
        case .neutral: K.surface2
        case .active, .success: K.hover
        case .attention, .failure: K.pressed
        }
    }

    /// Distinct glyph per tone.
    var icon: String {
        switch self {
        case .neutral: "circle"
        case .active: "circle.lefthalf.filled"
        case .success: "checkmark.circle"
        case .attention: "exclamationmark.triangle"
        case .failure: "xmark.octagon"
        }
    }
}

/// Human-readable label and tone for status strings stored by the backend
/// (runs, tasks, agent sessions, tool operations, generations, prepared actions).
struct BackendStatus: Equatable {
    let raw: String

    init(_ raw: String) { self.raw = raw.uppercased() }

    var label: String {
        switch raw {
        case "": "Unknown"
        case "AWAITING_PLAN": "Plan ready"
        case "READY_FOR_ACCEPTANCE": "Ready to accept"
        case "PREPARED": "Needs approval"
        case "EXECUTING": "Executing"
        case "QUEUED": "Queued"
        case "UNKNOWN": "Outcome unknown"
        default:
            raw.replacingOccurrences(of: "_", with: " ").lowercased().capitalizedFirst
        }
    }

    var tone: StatusTone {
        switch raw {
        case "RUNNING", "PLANNING", "EXECUTING", "QUEUED", "REVIEWING", "WRITING": .active
        case "COMPLETED", "DONE", "ACCEPTED", "APPROVED", "PASSED", "MERGED", "SUCCEEDED": .success
        case "AWAITING_PLAN", "READY_FOR_ACCEPTANCE", "PREPARED", "WAITING", "PAUSED", "BLOCKED",
             "UNKNOWN", "CHANGES_REQUESTED", "NEEDS_CHANGES": .attention
        case "FAILED", "REJECTED", "DENIED", "ERROR": .failure
        default: .neutral
        }
    }

    var isTerminal: Bool { ["COMPLETED", "CANCELLED", "FAILED"].contains(raw) }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Icon + label tag with square corners. Active statuses pulse unless Reduce Motion is on.
struct StatusBadge: View {
    @Environment(\.blotReduceMotion) private var reduceMotion
    let label: String
    var tone: StatusTone = .neutral
    @State private var pulse = false

    init(_ label: String, tone: StatusTone = .neutral) {
        self.label = label
        self.tone = tone
    }

    init(status: String) {
        let status = BackendStatus(status)
        self.init(status.label, tone: status.tone)
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: tone.icon).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tone.color)
                .opacity(tone == .active && pulse ? 0.35 : 1)
            Text(label).font(KFont.caption(tone == .attention || tone == .failure ? .semibold : .medium))
                .foregroundStyle(tone.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3).frame(minHeight: 22)
        .background(Rectangle().fill(tone.background))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(label)")
        .onAppear { startPulse() }
        .onChange(of: tone) { _, _ in startPulse() }
        .onChange(of: reduceMotion) { _, _ in startPulse() }
    }

    private func startPulse() {
        guard tone == .active, !reduceMotion else { pulse = false; return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
    }
}

// MARK: - Empty / loading

/// Centered empty state with an optional call to action. Used for empty lists, missing records
/// and first-run screens.
struct EmptyState: View {
    var icon: String = "search"
    let title: String
    let detail: String
    var actionTitle: String?
    var actionIcon: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: KSpace.md) {
            IconTile(icon: icon, size: 44, iconSize: 20, color: K.text3)
            VStack(spacing: 6) {
                Text(title).font(KFont.ui(15, .medium)).foregroundStyle(K.text)
                Text(detail).font(KFont.ui(13)).foregroundStyle(K.text2).lineSpacing(3)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                KButton(title: actionTitle, icon: actionIcon, action: action).padding(.top, 4)
            }
        }
        .padding(.vertical, 48).padding(.horizontal, KSpace.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Spinner with a short label, for waiting on the backend inside a page or card.
struct LoadingState: View {
    var label = "Loading…"
    var body: some View {
        HStack(spacing: KSpace.sm) {
            ProgressView().controlSize(.small)
            Text(label).font(KFont.ui(13)).foregroundStyle(K.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(KSpace.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Banner

/// Full-width notice under the toolbar (connection lost, commands awaiting confirmation).
struct Banner<Actions: View>: View {
    let text: String
    var tone: InlineFeedback.Tone = .warning
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: KSpace.md) {
            KIcon(tone.icon, size: 16, color: tone.color).accessibilityHidden(true)
            Text(text).font(KFont.ui(13)).foregroundStyle(K.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: KSpace.sm, content: actions)
        }
        .padding(.horizontal, KSpace.lg).padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(tone == .warning || tone == .error ? K.pressed : K.surface2)
        .kBorder(.bottom)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Toasts

/// Short confirmations after an action finishes («Plan approved», «Copied»). Success notes leave
/// on their own; errors stay until the user dismisses them or a newer message replaces them, so
/// the explanation can be read in full. Don't confirm changes the screen already shows.
@MainActor
@Observable
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let tone: InlineFeedback.Tone
    }

    private(set) var current: Toast?

    func show(_ text: String, tone: InlineFeedback.Tone = .success) {
        let toast = Toast(text: text, tone: tone)
        current = toast
        AccessibilityNotification.Announcement(text).post()
        guard tone != .error && tone != .warning else { return }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if current?.id == toast.id { current = nil }
        }
    }

    func dismiss() { current = nil }
}

struct ToastHost: View {
    let center: ToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let toast = center.current {
                HStack(spacing: KSpace.sm) {
                    KIcon(toast.tone.icon, size: 16, color: toast.tone.color)
                    Text(toast.text).font(KFont.ui(13, .medium)).foregroundStyle(K.text)
                        .lineLimit(toast.tone == .error ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    IconButton(icon: "x", size: 20, iconSize: 12, color: K.text3, help: "Dismiss") { center.dismiss() }
                }
                .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 4).frame(minHeight: 40)
                .kPopover(radius: 12)
                .padding(.horizontal, 48)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isStaticText)
                .id(toast.id)
            }
        }
        .frame(maxWidth: .infinity)
        .kAnimation(KMotion.notice, value: center.current)
    }
}
