import BlotDesign
import SwiftUI

struct MacTeamRoutineEditor: View {
    let routineID: String?
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.dismiss) private var dismiss
    @State private var routine = MacDemoRoutine(id: UUID().uuidString, title: "", agentID: "chief", instructions: "")
    @State private var confirmDelete = false
    private var valid: Bool {
        !routine.title.isEmpty && !routine.instructions.isEmpty && MacDemoScheduler().validTime(routine.time)
            && (routine.frequency != "По будням" || !routine.weekdays.isEmpty)
    }
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: routineID == nil ? "Новое расписание" : "Расписание")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Название задачи", text: $routine.title).font(.system(size: 20, weight: .medium))
                    MacTeamSelect(
                        title: "Агент", selection: $routine.agentID,
                        options: presentation.agents.map { .init($0.name, $0.id) })
                    Text("Что нужно делать").fontWeight(.medium)
                    TextEditor(text: $routine.instructions).font(.system(size: 13)).frame(height: 125)
                        .scrollContentBackground(.hidden)
                        .padding(10).background(MacTeamStyle.field, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Когда запускать").fontWeight(.medium)
                        MacTeamSelect(
                            title: "Повтор", selection: $routine.frequency,
                            values: ["По будням", "Каждый день", "Каждый час", "По пятницам"])
                        HStack {
                            Text("Время")
                            Spacer()
                            TextField("09:00", text: $routine.time).frame(width: 90).accessibilityLabel("Время запуска")
                        }
                        if routine.frequency == "По будням" {
                            HStack(spacing: 6) {
                                ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { day in
                                    Button {
                                        if routine.weekdays.contains(day) {
                                            routine.weekdays.removeAll { $0 == day }
                                        } else {
                                            routine.weekdays.append(day)
                                        }
                                    } label: {
                                        Text(day).font(.system(size: 11)).frame(width: 34, height: 30)
                                            .foregroundStyle(
                                                routine.weekdays.contains(day)
                                                    ? BlotColor.onInverse : WorkspaceStyle.secondary
                                            )
                                            .background(
                                                routine.weekdays.contains(day) ? BlotColor.inverse : MacTeamStyle.field,
                                                in: RoundedRectangle(cornerRadius: 9))
                                    }.buttonStyle(BlotPlainButtonStyle()).accessibilityAddTraits(
                                        routine.weekdays.contains(day) ? [.isSelected] : [])
                                }
                            }
                        }
                        Text("Часовой пояс · " + TimeZone.current.identifier).font(.system(size: 10)).foregroundStyle(
                            .secondary)
                        if let next = MacDemoScheduler().nextRun(routine, after: Date()) {
                            Text("Следующий запуск: " + presentation.dateLabel(next)).font(
                                .system(size: 11)
                            ).foregroundStyle(.secondary)
                        }
                    }.teamCard()
                        .kAnimation(KMotion.standard, value: routine.frequency)
                        .kAnimation(KMotion.quick, value: routine.weekdays)
                    Toggle("Не уведомлять, если новостей нет", isOn: $routine.quiet)
                    Toggle("Согласовывать подготовленные действия", isOn: $routine.requiresApproval)
                    Toggle("Расписание активно", isOn: $routine.enabled)
                    Text(
                        "В демо расписания работают, пока приложение открыто. Интернет и управление компьютером не используются."
                    ).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
                    if !MacDemoScheduler().validTime(routine.time) {
                        Text("Введите время в формате 09:00.").font(.system(size: 11))
                    }
                }.font(.system(size: 12)).padding(24)
            }
            Divider()
            HStack {
                if routineID != nil {
                    Button("Удалить", role: .destructive) { confirmDelete = true }.buttonStyle(BlotPlainButtonStyle())
                }
                Spacer()
                if routineID != nil {
                    Button("Запустить сейчас") {
                        presentation.demo.saveRoutine(routine)
                        presentation.runRoutine(routine.id)
                    }.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(!valid)
                }
                Button("Сохранить") {
                    presentation.demo.saveRoutine(routine)
                    dismiss()
                }.buttonStyle(WorkspaceButtonStyle()).disabled(!valid)
            }.padding(18)
        }.frame(width: 600, height: 740)
            .onAppear {
                if let saved = presentation.routines.first(where: { $0.id == routineID }) {
                    routine = saved
                } else {
                    routine.agentID = presentation.agent.id
                }
            }
            .confirmationDialog("Удалить расписание из демо?", isPresented: $confirmDelete) {
                Button("Удалить", role: .destructive) {
                    presentation.demo.update { $0.routines.removeAll { $0.id == routine.id } }
                    dismiss()
                }
            }
    }
}
