import BlotDesign
import SwiftUI

struct ProfileStatisticsView: View {
    let statistics: ProfileStatistics?

    var body: some View {
        HStack(spacing: 0) {
            metric("Lifetime tokens", value: tokens(statistics?.lifetimeTokens))
            separator
            metric("Peak tokens", value: tokens(statistics?.peakTokens))
            separator
            metric("Longest task", value: duration(statistics?.longestTaskSeconds))
            separator
            metric("Longest streak", value: days(statistics?.longestStreakDays))
            separator
            metric("Current streak", value: days(statistics?.currentStreakDays))
        }
        .padding(.vertical, 12)
        .overlay(RoundedRectangle(cornerRadius: K.rLg, style: .continuous).strokeBorder(K.border, lineWidth: 1))
    }

    private var separator: some View { VDivider().frame(height: 36) }

    private func metric(_ title: String, value: String?) -> some View {
        VStack(spacing: 5) {
            Text(value ?? "—").font(KFont.body()).foregroundStyle(K.text).monospacedDigit()
            Text(title).font(KFont.caption()).foregroundStyle(K.text2)
        }.frame(maxWidth: .infinity).padding(.horizontal, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): \(value ?? "Not available")")
            .help(value == nil ? "Account statistics are not available yet." : title)
    }

    private func tokens(_ value: Int64?) -> String? {
        guard let value else { return nil }
        return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }
    private func duration(_ seconds: Int?) -> String? {
        guard let seconds else { return nil }
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    private func days(_ value: Int?) -> String? {
        value.map { "\($0) \($0 == 1 ? "day" : "days")" }
    }
}
