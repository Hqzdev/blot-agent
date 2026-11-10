import BlotDesign
import SwiftUI

struct PhoneSettingsTokenHeatmap: View {
    let dailyTokens: [Date: Int]
    @Environment(WorkspaceStore.self) private var store
    private var firstDay: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return calendar.date(byAdding: .weekOfYear, value: -51, to: start) ?? today
    }
    var body: some View {
        let start = firstDay
        let maximum = max(1, dailyTokens.values.max() ?? 1)
        PhoneSettingsGroup(title: "Token activity", detail: "Last 12 months") {
            ScrollView(.horizontal) {
                HStack(spacing: 3) {
                    ForEach(0..<52, id: \.self) { week in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { weekday in
                                let date = Calendar.current.date(byAdding: .day, value: week * 7 + weekday, to: start) ?? start
                                let count = dailyTokens[date, default: 0]
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(count > 0 ? PhoneSettingsStyle.accent.opacity(0.28 + 0.72 * Double(count) / Double(maximum)) : WorkspaceStyle.ink.opacity(0.08))
                                    .frame(width: 10, height: 10)
                                    .accessibilityLabel(date.formatted(date: .abbreviated, time: .omitted) + ": " + count.formatted() + " " + store.t("Tokens"))
                            }
                        }
                    }
                }.padding(16)
            }.defaultScrollAnchor(.trailing)
        }
    }
}
