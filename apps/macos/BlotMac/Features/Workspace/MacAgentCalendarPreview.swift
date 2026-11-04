import BlotDesign
import BlotDomain
import SwiftUI

/// Local calendar illustration built from the demo agent's actual routines.
struct MacAgentCalendarPreview: View {
    let routines: [BlotV3.Automation]
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3) { index in Circle().fill([Color.red, .orange, .green][index]).frame(width: 4, height: 4) }
                Spacer()
                Text(store.t("Calendar")).font(.system(size: 6, weight: .medium))
                Spacer()
            }.padding(.horizontal, 7).frame(height: 15).background(WorkspaceStyle.surface)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(8..<20) { hour in Text("\(hour):00").font(.system(size: 4)).frame(maxHeight: .infinity) }
                }.foregroundStyle(WorkspaceStyle.secondary).frame(width: 25)
                ForEach(1...5, id: \.self) { day in
                    VStack(spacing: 3) {
                        Text(weekday(day)).font(.system(size: 5, weight: .medium)).frame(height: 10)
                        GeometryReader { geometry in
                            ZStack(alignment: .top) {
                                VStack(spacing: 0) {
                                    ForEach(0..<12) { _ in Rectangle().fill(MacWorkspaceStyle.edge).frame(height: 0.5).frame(maxHeight: .infinity, alignment: .top) }
                                }
                                ForEach(Array(routines.enumerated()), id: \.element.metadata.id) { index, routine in
                                    if routine.weekdays.contains(day) {
                                        let hour = Int(routine.localTime.prefix(2)) ?? 8
                                        Text(store.t(routine.name)).font(.system(size: 4)).lineLimit(2)
                                            .foregroundStyle(.white).padding(2).frame(maxWidth: .infinity, minHeight: 17, alignment: .topLeading)
                                            .background(index.isMultiple(of: 2) ? Color.blue : .teal, in: RoundedRectangle(cornerRadius: 2))
                                            .opacity(routine.enabled ? 0.8 : 0.35)
                                            .offset(y: CGFloat(max(0, min(hour - 8, 11))) / 12 * geometry.size.height)
                                    }
                                }
                            }
                        }
                    }.padding(.horizontal, 1).frame(maxWidth: .infinity)
                        .overlay(alignment: .leading) { Rectangle().fill(MacWorkspaceStyle.edge).frame(width: 0.5) }
                }
            }.padding(.horizontal, 5).padding(.bottom, 6)
        }
        .background(WorkspaceStyle.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(10).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: BlotRadius.panel))
        .accessibilityElement(children: .ignore).accessibilityLabel(store.t("Demo calendar preview"))
    }

    private func weekday(_ day: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: store.language)
        return calendar.veryShortWeekdaySymbols[day % 7]
    }
}
