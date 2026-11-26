import BlotDesign
import BlotWorkspace
import SwiftUI

struct WorkspaceSlidesEditor: View {
    @Bindable var session: WorkspaceDocumentEditSession
    @Environment(WorkspaceStore.self) private var store
    private var ru: Bool { store.language == "ru" }
    private var selected: Int { min(session.slide, max(0, session.draft.slides.count - 1)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(session.draft.slides.indices, id: \.self) { index in
                        Button { session.slide = index } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text((ru ? "Слайд " : "Slide ") + String(index + 1)).font(.caption).foregroundStyle(.secondary)
                                Text(session.draft.slides[index].title.isEmpty ? (ru ? "Без заголовка" : "Untitled") : session.draft.slides[index].title).font(.headline).lineLimit(2)
                            }.frame(width: 140, height: 66, alignment: .topLeading).padding(12)
                                .background(WorkspaceStyle.ink.opacity(selected == index ? 0.1 : 0.035), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.ink.opacity(selected == index ? 0.35 : 0.08)))
                                .contentShape(RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain).accessibilityLabel((ru ? "Выбрать слайд " : "Select slide ") + String(index + 1))
                    }
                }.padding(2)
            }
            VStack(alignment: .leading, spacing: 8) {
                Button { session.draft.slides.append(.init(title: "", body: "")); session.slide = session.draft.slides.count - 1 } label: { BlotLabel(ru ? "Добавить слайд" : "Add slide", symbol: "plus") }.disabled(session.draft.slides.count >= 30)
                HStack(spacing: 8) {
                Button { session.draft.slides.swapAt(selected, selected - 1); session.slide = selected - 1 } label: { BlotLabel(ru ? "Левее" : "Move left", symbol: "arrow.left") }.disabled(selected == 0)
                Button { session.draft.slides.swapAt(selected, selected + 1); session.slide = selected + 1 } label: { BlotLabel(ru ? "Правее" : "Move right", symbol: "arrow.right") }.disabled(selected >= session.draft.slides.count - 1)
                Button { session.draft.slides.remove(at: selected); session.slide = min(selected, session.draft.slides.count - 1) } label: { BlotLabel(ru ? "Удалить" : "Remove", symbol: "minus") }.disabled(session.draft.slides.count <= 1)
                }
            }.buttonStyle(WorkspaceButtonStyle(.secondary))
            if !session.draft.slides.isEmpty {
                TextField(ru ? "Заголовок слайда" : "Slide title", text: $session.draft.slides[selected].title)
                    .textFieldStyle(.plain).font(.title2.weight(.semibold)).padding(16)
                    .background(WorkspaceStyle.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(ru ? "Заголовок слайда" : "Slide title")
                TextEditor(text: $session.draft.slides[selected].body).font(.body).scrollContentBackground(.hidden)
                    .frame(minHeight: 250).padding(16)
                    .background(WorkspaceStyle.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceStyle.ink.opacity(0.08)))
                    .accessibilityLabel(ru ? "Текст слайда" : "Slide text")
                Text(ru ? "Сохраняется PDF со всеми слайдами. Текст должен помещаться на слайд." : "Saves a PDF with all slides. Text must fit on each slide.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
