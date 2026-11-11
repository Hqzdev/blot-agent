import BlotDesign
import SwiftUI

/// Compact date and time entry uses the same choices and calendar surface as the pane.
struct WorkspacePanelDateField: View {
    let title: String
    @Binding var date: Date
    var calendarOnly = false
    @State private var expanded = false
    @State private var month = Date()
    @Environment(\.workspacePanelNavigation) private var panel
    @Environment(\.calendar) private var sourceCalendar
    @Environment(WorkspaceStore.self) private var store
    private var ru: Bool { store.language == "ru" }
    private var calendar: Calendar { var value = sourceCalendar; value.locale = Locale(identifier: store.language); return value }
    var body: some View {
        if panel == nil { DatePicker(title, selection: $date, displayedComponents: calendarOnly ? .date : .hourAndMinute) }
        else if calendarOnly {
            Button { month = date; expanded = true } label: {
                HStack { Text(title); Spacer(); Text(date, format: .dateTime.day().month().year()); Image(systemName: "calendar") }
                    .padding(12).frame(maxWidth: .infinity).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).popover(isPresented: $expanded, arrowEdge: .bottom) { calendarPage }
        } else {
            HStack(alignment: .top, spacing: 10) {
                WorkspaceChoice(title: title, selection: component(.hour), options: (0..<24).map { .init($0, String(format: "%02d", $0)) })
                WorkspaceChoice(title: ru ? "Минуты" : "Minutes", selection: component(.minute), options: (0..<60).map { .init($0, String(format: "%02d", $0)) })
            }
        }
    }
    private func component(_ unit: Calendar.Component) -> Binding<Int> {
        Binding(get: { calendar.component(unit, from: date) }, set: { if let value = calendar.date(bySetting: unit, value: $0, of: date) { date = value } })
    }
    private var calendarPage: some View {
        VStack(spacing: 16) {
            HStack {
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel(ru ? "Предыдущий месяц" : "Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: store.language)))).font(.headline)
                Spacer()
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel(ru ? "Следующий месяц" : "Next month")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7]).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button { select(day) } label: {
                            Text(calendar.component(.day, from: day).formatted()).monospacedDigit().frame(width: 30, height: 30)
                                .foregroundStyle(calendar.isDate(day, inSameDayAs: date) ? BlotColor.onInverse : WorkspaceStyle.ink)
                                .background(calendar.isDate(day, inSameDayAs: date) ? BlotColor.inverse : .clear, in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: store.language))))
                    } else { Color.clear.frame(width: 30, height: 30) }
                }
            }
        }.padding(16).frame(width: 280).background(WorkspaceStyle.canvas).workspacePanelControls().presentationCompactAdaptation(.popover)
    }
    private var days: [Date?] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start, let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: offset) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: start) }
    }
    private func moveMonth(_ amount: Int) { if let next = calendar.date(byAdding: .month, value: amount, to: month) { month = next } }
    private func select(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        if let next = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) { date = next; expanded = false }
    }
}
