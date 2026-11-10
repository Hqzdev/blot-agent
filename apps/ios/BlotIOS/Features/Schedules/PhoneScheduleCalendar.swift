import BlotDesign
import SwiftUI

struct PhoneScheduleCalendar: View {
    @Binding var selectedDate: Date
    let calendar: Calendar
    @Environment(WorkspaceStore.self) private var store
    @ScaledMetric(relativeTo: .body) private var dayHeight: CGFloat = 72

    private var days: [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                weekButton("chevron.left", title: "Previous week", offset: -1)
                DatePicker(store.t("Date"), selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).frame(maxWidth: .infinity)
                weekButton("chevron.right", title: "Next week", offset: 1)
            }
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(days, id: \.self) { date in day(date) }
                    }.frame(minWidth: geometry.size.width)
                }.scrollIndicators(.hidden)
            }.frame(height: dayHeight)
        }
    }

    private func day(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        return Button { selectedDate = date } label: {
            VStack(spacing: 8) {
                Text(date, format: .dateTime.weekday(.narrow)).font(.caption)
                Text(date, format: .dateTime.day()).font(.body.weight(.medium))
                Circle().fill(calendar.isDateInToday(date) ? (selected ? BlotColor.onInverse : WorkspaceStyle.ink) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: dayHeight)
            .foregroundStyle(selected ? BlotColor.onInverse : WorkspaceStyle.ink)
            .background(selected ? BlotColor.inverse : PhoneSettingsStyle.row,
                        in: RoundedRectangle(cornerRadius: PhonePageLayout.radius))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month().locale(calendar.locale ?? .current)))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("workspace.schedule.day.\(calendar.component(.weekday, from: date))")
    }

    private func weekButton(_ symbol: String, title: String, offset: Int) -> some View {
        Button {
            if let date = calendar.date(byAdding: .weekOfYear, value: offset, to: selectedDate) { selectedDate = date }
        } label: { BlotIcon(symbol: symbol, size: 18).frame(width: 44, height: 44) }
            .buttonStyle(.plain).accessibilityLabel(store.t(title))
    }
}
