import SwiftUI
import WerkstattCore

struct QuestionFlowView: View {
    let itemID: String
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selections: Set<String> = []
    @State private var history: [String] = []

    private var item: Item? { model.item(id: itemID) }
    private var pending: [GuidedQuestion] { item.map { model.questions(item: $0) } ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let question = pending.first {
                    progress
                    Text(question.title).font(WerkstattTheme.title).foregroundStyle(WerkstattTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(question.subtitle).foregroundStyle(WerkstattTheme.muted)
                    if question.allowsMultiple {
                        Text("Du kannst mehrere Antworten auswählen.").font(.footnote).foregroundStyle(WerkstattTheme.muted)
                    }
                    VStack(spacing: 12) {
                        ForEach(question.choices) { choice in
                            choiceCard(choice, multiple: question.allowsMultiple)
                        }
                    }
                    Button {
                        model.resetError()
                        model.answer(itemID: itemID, questionID: question.id,
                                     choiceIDs: question.choices.filter { selections.contains($0.id) }.map(\.id))
                        if model.errorMessage == nil { history.append(question.id); selections = [] }
                    } label: { Label("Weiter", systemImage: "arrow.right") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(selections.isEmpty || model.isBusy)
                        .accessibilityIdentifier("question.next")
                    if !history.isEmpty { Button("Zurück zur letzten Frage") { goBack() } }
                } else if let item {
                    review(item)
                } else {
                    ContentUnavailableView("Artikel nicht verfügbar", systemImage: "tray")
                }
            }.padding(24)
        }.workshopBackground().id(pending.first?.id ?? "review")
        .navigationTitle("Die wichtigen Details").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Später") { dismiss() } } }
        .onChange(of: pending.first?.id) { _, _ in selections = [] }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FRAGE \(history.count + 1) · \(pending.count) NOCH OFFEN")
                .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(WerkstattTheme.accent)
            ProgressView(value: Double(history.count), total: Double(max(1, history.count + pending.count)))
                .tint(WerkstattTheme.accent)
        }.accessibilityElement(children: .combine)
    }

    private func choiceCard(_ choice: QuestionChoice, multiple: Bool) -> some View {
        let active = selections.contains(choice.id)
        return Button {
            if multiple {
                if active { selections.remove(choice.id) }
                else if ["none", "later", "other"].contains(choice.id) { selections = [choice.id] }
                else {
                    selections.remove("none")
                    selections.remove("later")
                    selections.remove("other")
                    selections.insert(choice.id)
                }
            } else { selections = [choice.id] }
        } label: {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(choice.label).font(.headline)
                    if !choice.detail.isEmpty { Text(choice.detail).font(.subheadline).foregroundStyle(WerkstattTheme.muted) }
                }
                Spacer(minLength: 0)
                Image(systemName: active ? "checkmark.circle.fill" : "circle").font(.title2)
            }.foregroundStyle(WerkstattTheme.ink).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(active ? WerkstattTheme.accent.opacity(0.12) : .white.opacity(0.8), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(active ? WerkstattTheme.accent : WerkstattTheme.line, lineWidth: active ? 2 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(active ? [.isSelected] : [])
            .accessibilityIdentifier("choice." + choice.id)
    }

    private func review(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundStyle(WerkstattTheme.accent).accessibilityHidden(true)
            Text("Du kennst\ndie Details.").font(WerkstattTheme.title).foregroundStyle(WerkstattTheme.ink)
                .accessibilityAddTraits(.isHeader)
            Button {
                model.resetError()
                model.regenerate(itemID: itemID)
                if model.errorMessage == nil { dismiss() }
            } label: { Text("Antworten übernehmen") }.buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("question.finish")
            ForEach(Questionnaire.allQuestions(for: item).filter { item.answers[$0.id] != nil }) { question in
                let key = question.id
                    PaperCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(question.title).font(.headline)
                            Text(answerLabel(key, question: question, item: item)).foregroundStyle(WerkstattTheme.muted)
                            Button("Antwort ändern") {
                                var updated = item
                                updated.answers.removeValue(forKey: key)
                                if updated.status == .ready { updated.status = .draft }
                                model.resetError()
                                model.saveItem(updated)
                                if model.errorMessage == nil { selections = []; history = [] }
                            }.font(.subheadline.weight(.semibold))
                        }
                    }
            }
            if !history.isEmpty { Button("Zurück zur letzten Frage") { goBack() } }
        }
    }

    private func answerLabel(_ key: String, question: GuidedQuestion, item: Item) -> String {
        let ids = Set((item.answers[key] ?? "").split(separator: ",").map(String.init))
        return question.choices.filter { ids.contains($0.id) }.map(\.label).joined(separator: ", ")
    }

    private func goBack() {
        guard let key = history.last, var updated = item else { return }
        updated.answers.removeValue(forKey: key)
        if updated.status == .ready { updated.status = .draft }
        model.resetError()
        model.saveItem(updated)
        if model.errorMessage == nil { history.removeLast(); selections = [] }
    }
}
