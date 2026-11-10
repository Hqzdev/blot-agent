//
//  BlotStates.swift
//  BlotDesign
//
//  Status and data states that read without colour: each tone has its own symbol and the
//  text says what happened. Errors and warnings also use a heavier weight.
//

import SwiftUI

nonisolated public enum BlotStatus: Sendable, Equatable, CaseIterable {
    case neutral, info, progress, success, warning, error

    /// Distinct glyph per tone (outline circle, i, half circle, check, triangle, cross).
    public var symbol: String {
        switch self {
        case .neutral: "circle"
        case .info: "info.circle"
        case .progress: "circle.lefthalf.filled"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    /// Spoken before the message so VoiceOver users hear the tone.
    public var spokenPrefix: String {
        switch self {
        case .neutral, .info: ""
        case .progress: "In progress: "
        case .success: "Done: "
        case .warning: "Warning: "
        case .error: "Error: "
        }
    }

    public var weight: Font.Weight {
        switch self {
        case .warning, .error: .medium
        default: .regular
        }
    }

    /// Body text is ink for things that need attention, secondary otherwise.
    public var foreground: Color {
        switch self {
        case .warning, .error: BlotColor.text
        default: BlotColor.textSecondary
        }
    }

    /// Background used by banners and pills; stronger veil for problems.
    public var background: Color {
        switch self {
        case .warning, .error: BlotColor.pressed
        case .success, .progress: BlotColor.hover
        case .neutral, .info: BlotColor.fill
        }
    }
}

/// Icon + text line for inline feedback, toasts and banners.
public struct BlotStatusLabel: View {
    private let text: String
    private let status: BlotStatus
    private let role: BlotTextRole

    public init(_ text: String, status: BlotStatus, role: BlotTextRole = .caption) {
        self.text = text
        self.status = status
        self.role = role
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: BlotSpace.element) {
            BlotIcon(symbol: status.symbol, size: role.size)
                .font(BlotFont.role(role, weight: .semibold))
                .accessibilityHidden(true)
            Text(text)
                .blotFont(role, weight: status.weight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(status.foreground)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.spokenPrefix + text)
    }
}

/// Square-cornered pill with icon and label, e.g. run and task status.
public struct BlotStatusPill: View {
    private let text: String
    private let status: BlotStatus

    public init(_ text: String, status: BlotStatus) {
        self.text = text
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 4) {
            BlotIcon(symbol: status.symbol, size: 11).font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
            Text(text).font(BlotFont.role(.meta, weight: status.weight == .regular ? .medium : .semibold)).lineLimit(1)
        }
        .foregroundStyle(status == .neutral ? BlotColor.textSecondary : BlotColor.text)
        .padding(.horizontal, BlotSpace.element)
        .padding(.vertical, 3)
        .background(Rectangle().fill(status.background))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(text)")
    }
}

/// Centered empty state with an optional action.
public struct BlotEmptyState: View {
    private let symbol: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(symbol: String, title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: BlotSpace.s10) {
            BlotIcon(symbol: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(BlotColor.textSecondary)
                .frame(width: 44, height: 44)
                .blotPanel(fill: BlotColor.fill)
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title)).blotFont(.body, weight: .semibold).foregroundStyle(BlotColor.text)
                .multilineTextAlignment(.center)
            Text(LocalizedStringKey(message)).blotFont(.caption).foregroundStyle(BlotColor.textSecondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(BlotButtonStyle()).padding(.top, BlotSpace.element)
            }
        }
        .padding(.vertical, 40).padding(.horizontal, BlotSpace.section)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Spinner with a label.
public struct BlotLoadingState: View {
    private let label: String

    public init(_ label: String = "Loading…") { self.label = label }

    public var body: some View {
        HStack(spacing: BlotSpace.s8) {
            ProgressView().controlSize(.small)
            Text(label).blotFont(.caption).foregroundStyle(BlotColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BlotSpace.panel)
        .accessibilityElement(children: .combine)
    }
}

/// Error message with a retry action.
public struct BlotErrorState: View {
    private let message: String
    private let retryTitle: String
    private let retry: (() -> Void)?

    public init(_ message: String, retryTitle: String = "Try again", retry: (() -> Void)? = nil) {
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BlotSpace.s10) {
            BlotStatusLabel(message, status: .error)
                .textSelection(.enabled)
            if let retry {
                Button(retryTitle, action: retry).buttonStyle(BlotButtonStyle(size: .compact))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BlotSpace.panel)
        .blotPanel(fill: BlotColor.fill, border: BlotColor.hairlineStrong)
    }
}
