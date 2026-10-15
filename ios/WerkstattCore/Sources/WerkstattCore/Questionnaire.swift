import Foundation

public struct QuestionChoice: Identifiable, Equatable {
    public let id: String
    public let label: String
    public let detail: String
    public init(id: String, label: String, detail: String = "") {
        self.id = id; self.label = label; self.detail = detail
    }
}

public struct GuidedQuestion: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let choices: [QuestionChoice]
    public let allowsMultiple: Bool
    public init(id: String, title: String, subtitle: String = "", choices: [QuestionChoice], allowsMultiple: Bool = false) {
        self.id = id; self.title = title; self.subtitle = subtitle
        self.choices = choices; self.allowsMultiple = allowsMultiple
    }
}

public enum Questionnaire {
    private static func choice(_ id: String, _ label: String, _ detail: String = "") -> QuestionChoice {
        QuestionChoice(id: id, label: label, detail: detail)
    }
    public static func choices(_ answer: String?) -> Set<String> {
        Set((answer ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }
    /// All applicable cards, including already answered cards, for review and validation.
    public static func allQuestions(for item: Item) -> [GuidedQuestion] {
        var result = [GuidedQuestion(id: "condition", title: "Wie ist der Zustand?", subtitle: "Deine Angaben haben Vorrang vor einer Einschätzung anhand der Bilder.", choices: [
            choice("new", "Neu und unbenutzt", "Verpackung wird separat abgefragt."),
            choice("likeNew", "Fast wie neu"), choice("veryGood", "Sehr gut"),
            choice("good", "Gut, mit Gebrauchsspuren"), choice("fair", "Deutliche Gebrauchsspuren"),
            choice("later", "Später prüfen")
        ])]
        let unused = item.answers["condition"] == "new"
        if let condition = item.answers["condition"], condition != "new", condition != "later" {
            result.append(GuidedQuestion(id: "defects", title: "Gibt es bekannte Mängel?", subtitle: "Mehrere Antworten möglich. Bereits festgestellte Mängel bleiben in der Beschreibung erhalten.", choices: [
                choice("none", "Keine weiteren bekannten Mängel"), choice("normalWear", "Normale Gebrauchsspuren"),
                choice("scratches", "Kratzer"), choice("dents", "Kleine Macken oder Dellen"),
                choice("cracks", "Risse oder Brüche"), choice("other", "Anderer Mangel", "Bitte vor Freigabe genauer klären."),
                choice("later", "Später prüfen")
            ], allowsMultiple: true))
        }
        switch item.kind {
        case .smartwatch:
            result.append(functionCard())
            result.append(GuidedQuestion(id: "battery", title: "Wie ist der Akku?", subtitle: "Eine ehrliche Einschätzung genügt. Kein erfundener Prozentwert und keine geschätzte Laufzeit.", choices: [
                choice("good", "Nach meiner Einschätzung gut"),
                choice("notMeasured", "Nicht geprüft / nicht messbar", "Wir nennen keine Akkugesundheit oder Laufzeit."),
                choice("weak", "Hält nur noch kurz"), choice("later", "Später prüfen")
            ]))
            result.append(GuidedQuestion(id: "charger", title: "Ist ein Ladekabel dabei?", choices: [choice("included", "Ja, enthalten"), choice("notIncluded", "Nein"), choice("unknown", "Weiß ich noch nicht")]))
            result.append(packagingCard())
        case .headphones:
            result.append(packagingCard())
            if !unused { result.append(functionCard()) }
        case .chair:
            result.append(GuidedQuestion(id: "chairRotation", title: "Funktioniert das Drehen?", choices: mechanismChoices()))
            result.append(GuidedQuestion(id: "chairHeight", title: "Funktioniert die Höhenverstellung?", choices: mechanismChoices()))
        case .other:
            let identity = (item.title + " " + item.category).lowercased()
            if ["elektr", "gerät", "konsole", "kamera", "telefon", "lautsprecher", "monitor", "computer"].contains(where: identity.contains) { result.append(functionCard()) }
        case .supplies: break
        }
        if item.answers["function"] == "issues" {
            result.append(GuidedQuestion(id: "functionIssue", title: "Welches Funktionsproblem ist bekannt?", choices: [
                choice("notWorking", "Funktioniert nicht"), choice("intermittent", "Funktioniert nur zeitweise"),
                choice("other", "Anderes Problem", "Bitte vor Freigabe genauer klären."), choice("later", "Noch prüfen")
            ]))
        }
        result.append(GuidedQuestion(id: "delivery", title: "Wie möchtest du den Artikel übergeben?", choices: [
            choice("pickup", "Nur Abholung", "Kein Versand."), choice("shipping", "Nur Versand"), choice("both", "Abholung oder Versand")
        ]))
        for (index, question) in item.questions.enumerated() {
            result.append(GuidedQuestion(id: "review-\(index)", title: question, subtitle: "Offener Punkt aus der Bildanalyse. Kläre die Angabe im Analysepaket oder Artikel, bevor du sie als geprüft markierst.", choices: [
                choice("reviewed", "Geprüft und geklärt"), choice("later", "Noch offen")
            ]))
        }
        return result
    }
    public static func questions(for item: Item) -> [GuidedQuestion] {
        allQuestions(for: item).filter { choices(item.answers[$0.id]).isEmpty }
    }
    private static func functionCard() -> GuidedQuestion {
        GuidedQuestion(id: "function", title: "Funktioniert alles einwandfrei?", subtitle: "Aus einem Foto lässt sich die Funktion nicht zuverlässig prüfen.", choices: [choice("works", "Ja, geprüft und funktioniert"), choice("issues", "Es gibt ein Problem"), choice("later", "Noch nicht geprüft")])
    }
    private static func packagingCard() -> GuidedQuestion {
        GuidedQuestion(id: "packaging", title: "Wie ist die Verpackung?", subtitle: "Originalverpackt bedeutet nicht automatisch ungeöffnet.", choices: [choice("sealed", "Originalverpackung ungeöffnet"), choice("opened", "Originalverpackung geöffnet"), choice("none", "Ohne Originalverpackung"), choice("unknown", "Nicht sicher")])
    }
    private static func mechanismChoices() -> [QuestionChoice] {
        [choice("works", "Funktioniert einwandfrei"), choice("issues", "Funktioniert nicht einwandfrei"), choice("notApplicable", "Hat diese Funktion nicht"), choice("later", "Noch prüfen")]
    }
    public static func blockers(item: Item, photos: [Photo]) -> [String] {
        var result: [String] = []
        if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("Ein Anzeigetitel fehlt.") }
        if item.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("Eine Beschreibung fehlt.") }
        if item.condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append("Der Zustand fehlt.") }
        let owned = Set(photos.filter { $0.itemID == item.id }.map(\.id))
        let selected = Set(photos.filter { $0.itemID == item.id && $0.isSelected }.map(\.id))
        if selected.isEmpty { result.append("Mindestens ein Anzeigenfoto auswählen.") }
        if let cover = item.coverPhotoID {
            if !selected.contains(cover) { result.append("Das Titelbild muss ein ausgewähltes Foto dieses Artikels sein.") }
        } else { result.append("Ein Titelbild auswählen.") }
        if Set(item.photoOrder).count != item.photoOrder.count || Set(item.photoOrder) != owned {
            result.append("Die Fotoreihenfolge muss jedes zugeordnete Foto genau einmal enthalten.")
        }
        if item.priceType == .free {
            if item.price != 0 || item.platform != .kleinanzeigen { result.append("Verschenken benötigt 0 € und Kleinanzeigen als Plattform.") }
        } else if let price = item.price {
            if !price.isFinite || price <= 0 || price > 1_000_000 { result.append("Einen gültigen Preis größer als 0 € und höchstens 1.000.000 € festlegen.") }
        } else { result.append("Ein Preis fehlt. Erst recherchieren oder selbst festlegen.") }
        for question in allQuestions(for: item) {
            let answers = choices(item.answers[question.id])
            if answers.isEmpty {
                result.append("Noch beantworten: \(question.title)")
                continue
            }
            if !answers.isSubset(of: Set(question.choices.map(\.id))) || (!question.allowsMultiple && answers.count != 1) {
                result.append("Ungültige Antwort: \(question.title)")
                continue
            }
            if answers.contains("later") || answers.contains("other") { result.append("Noch klären: \(question.title)") }
            if question.id == "defects", answers.count > 1, answers.contains("none") {
                result.append("„Keine weiteren Mängel“ bitte nicht mit weiteren Mängeln kombinieren.")
            }
        }
        return result
    }
}
