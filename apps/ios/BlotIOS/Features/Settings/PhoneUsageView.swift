import BlotDesign
import Foundation
import SwiftUI

struct PhoneUsageView: View {
    private enum Period: String, CaseIterable, Identifiable {
        case today = "Today", month = "This month", all = "All time"
        var id: String { rawValue }
    }
    @Environment(WorkspaceStore.self) private var store
    @State private var period = Period.month

    private var records: [PhoneTokenUsage] {
        let calendar = Calendar.current
        return store.tokenUsage.filter { record in
            switch period {
            case .today: calendar.isDateInToday(record.date)
            case .month: calendar.isDate(record.date, equalTo: Date(), toGranularity: .month)
            case .all: true
            }
        }
    }

    var body: some View {
        let visibleRecords = self.records
        ScrollView {
            VStack(spacing: 28) {
                Picker(store.t("Period"), selection: $period) {
                    ForEach(Period.allCases) { item in Text(store.t(item.rawValue)).tag(item) }
                }.pickerStyle(.segmented)
                PhoneSettingsGroup(title: "Provider usage") {
                    HStack(spacing: 12) {
                        total("Input tokens", value: visibleRecords.reduce(0) { $0 + $1.inputTokens })
                        total("Output tokens", value: visibleRecords.reduce(0) { $0 + $1.outputTokens })
                        total("Total tokens", value: visibleRecords.reduce(0) { $0 + $1.totalTokens })
                    }.padding(18)
                }
                if visibleRecords.isEmpty {
                    Text(store.t("Completed requests with provider usage appear here."))
                        .font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    PhoneSettingsGroup(title: "By model") {
                        ForEach(Array(Set(visibleRecords.map(\.modelID))).sorted(), id: \.self) { model in
                            HStack {
                                BlotIcon(.chip)
                                Text(model == "gigachat" ? "GigaChat" : model).font(.body)
                                Spacer()
                                Text(visibleRecords.filter { $0.modelID == model }.reduce(0) { $0 + $1.totalTokens }, format: .number)
                                    .monospacedDigit()
                            }.padding(18)
                        }
                    }
                    PhoneSettingsGroup(title: "Recent requests") {
                        ForEach(Array(visibleRecords.sorted { $0.date > $1.date }.prefix(20).enumerated()), id: \.element.id) { index, record in
                            if index > 0 { PhoneSettingsDivider() }
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.agentName).font(.body)
                                    Text(record.date, format: .dateTime.day().month().hour().minute())
                                        .font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 5) {
                                    Text(record.totalTokens, format: .number).font(.body.monospacedDigit())
                                    Text("↑ \(record.inputTokens) · ↓ \(record.outputTokens)")
                                        .font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                                }
                            }.padding(18)
                        }
                    }
                }
                if store.unknownUsageCount > 0 {
                    Text("Расход не определён: \(store.unknownUsageCount) запросов")
                        .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                }
                Text(store.t("Only usage returned by the provider is counted. Requests without usage remain unknown."))
                    .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(20)
        }.background(PhoneSettingsStyle.canvas.ignoresSafeArea())
    }

    private func total(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t(title)).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
            Text(value, format: .number).font(.title3.weight(.semibold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
