import Foundation

public enum ListingComposer {
    /// Builds public text from seller choices and established visible facts, never private questions.
    /// Call explicitly after an answer or with the „Text aus Antworten erstellen“ action.
    public static func applyAnswers(to item: Item, location: String) -> Item {
        var result = item
        let answer = item.answers
        let conditionSentences: [String: (String, String)] = [
            "new": ("Neu", "Neu und unbenutzt."),
            "likeNew": ("Sehr gut", "Der Artikel ist in sehr gutem Zustand, fast wie neu."),
            "veryGood": ("Sehr gut", "Der Artikel ist in sehr gutem Zustand."),
            "good": ("Gut", "Der Artikel hat Gebrauchsspuren. Bitte die Fotos anschauen."),
            "fair": ("Zufriedenstellend", "Der Artikel hat deutliche Gebrauchsspuren. Bitte die Fotos anschauen.")
        ]
        var lines: [String] = []
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { lines.append(title + (title.hasSuffix(".") ? "" : ".")) }
        if let value = conditionSentences[answer["condition"] ?? ""] {
            result.condition = value.0
            lines.append(value.1)
        } else if answer["condition"] == "later" {
            result.condition = ""
        }
        if item.kind == .headphones, answer["condition"] == "new" {
            // Unused sealed headphones cannot be function-tested without opening the box.
        } else if answer["function"] == "works" {
            lines.append("Funktioniert einwandfrei.")
        } else if answer["function"] == "issues" {
            switch answer["functionIssue"] {
            case "notWorking": lines.append("Der Artikel funktioniert nicht.")
            case "intermittent": lines.append("Der Artikel funktioniert nur zeitweise.")
            default: break // Remains a private blocker until the specific defect is established.
            }
        }
        if item.kind == .chair {
            if answer["chairRotation"] == "works", answer["chairHeight"] == "works" {
                lines.append("Drehen und Höhenverstellung funktionieren einwandfrei.")
            } else {
                if answer["chairRotation"] == "works" { lines.append("Die Drehfunktion funktioniert einwandfrei.") }
                if answer["chairHeight"] == "works" { lines.append("Die Höhenverstellung funktioniert einwandfrei.") }
            }
            if answer["chairRotation"] == "issues" { lines.append("Die Drehfunktion funktioniert nicht einwandfrei.") }
            if answer["chairHeight"] == "issues" { lines.append("Die Höhenverstellung funktioniert nicht einwandfrei.") }
        }
        if item.kind == .smartwatch {
            if answer["battery"] == "good" { lines.append("Der Akku ist nach meiner Einschätzung in gutem Zustand.") }
            if answer["battery"] == "weak" { lines.append("Der Akku hält nur noch kurz.") }
            if answer["charger"] == "included" { lines.append("Ein Ladekabel ist dabei.") }
            if answer["charger"] == "notIncluded" { lines.append("Ohne Ladekabel.") }
        }
        if item.kind == .headphones || item.kind == .smartwatch {
            if answer["packaging"] == "sealed" { lines.append("In ungeöffneter Originalverpackung.") }
            if answer["packaging"] == "opened" { lines.append("Die Originalverpackung ist dabei und wurde geöffnet.") }
        }
        let defects = Questionnaire.choices(answer["defects"])
        if defects.contains("scratches") { lines.append("Der Artikel hat Kratzer. Bitte die Fotos anschauen.") }
        if defects.contains("dents") { lines.append("Der Artikel hat kleine Macken oder Dellen. Bitte die Fotos anschauen.") }
        if defects.contains("cracks") { lines.append("Der Artikel hat Risse oder Brüche. Bitte die Fotos anschauen.") }
        if defects.contains("normalWear"), answer["condition"] != "good", answer["condition"] != "fair" {
            lines.append("Der Artikel hat Gebrauchsspuren. Bitte die Fotos anschauen.")
        }
        // Preserve concrete visible facts (for example the notch on the chair's back).
        // Photos/OCR must not supply unconfirmed functional or measured battery claims.
        for fact in item.facts {
            let cleaned = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, cleaned.count <= 1_000, publicVisualFact(cleaned) else { continue }
            let folded = cleaned.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            if folded.contains("gebrauchsspuren"), ["good", "fair"].contains(answer["condition"] ?? "") || defects.contains("normalWear") {
                // Keep a concrete notch/scratch, but do not repeat a generic wear sentence.
                if folded.range(of: #"\b(macke|macken|delle|dellen|kratzer|riss|risse|rissen|bruch|bruche|fleck|flecken|verfarbung|verfarbungen)\b"#, options: .regularExpression) == nil { continue }
            }
            let sentence = cleaned + (".!?".contains(cleaned.last ?? ".") ? "" : ".")
            if !lines.contains(sentence) { lines.append(sentence) }
        }
        let city = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = city.isEmpty ? "" : " in \(city)"
        switch answer["delivery"] ?? "pickup" {
        case "shipping": lines.append("Nur Versand.")
        case "both": lines.append("Abholung\(place) oder Versand möglich.")
        default: lines.append("Nur Abholung\(place). Kein Versand.")
        }
        result.description = lines.joined(separator: "\n\n")
        return result
    }
    private static func publicVisualFact(_ text: String) -> Bool {
        let lower = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        // facts also holds research/provenance. Only a plain, concrete visual defect sentence
        // belongs in public copy; model hints, filenames and private seller notes do not.
        let privateTerms = ["seriennummer", "serial", "imei", "s/n", "akkugesund", "laufzeit", "batteriegesund", "%", "funktion", "akku", "batterie", "ladekabel", "ungeoffnet", "versiegelt", "quelle", "recherche", "hinweis", "texterkennung", "ocr", "analyse", "nutzer", "verkaufer", "bestatigt", "unbekannt", "unklar", "pruf", "eventuell", "vermut", "moglich", "schein", "konnte", "vielleicht", "nicht sicher", "http:", "https:", "www.", ".heic", ".jpg", ".jpeg", ".png", "img_", "dateiname", "foto-id", "fotoid"]
        let editorialTerms = ["zustandsbeschreibung", "beschreibung", "gemass deinem", "deinem wunsch", "formulierung", "workflow", "notiz", "anzeigentext", "neutral schreiben", "kurze neutrale"]
        guard !privateTerms.contains(where: lower.contains), !editorialTerms.contains(where: lower.contains), !lower.contains("?"),
              lower.range(of: #"\b(sn|kein|keine|keinen|keiner|ohne)\b"#, options: .regularExpression) == nil else { return false }
        return lower.range(of: #"\b(macke|macken|delle|dellen|kratzer|riss|risse|rissen|bruch|bruche|abnutzung|gebrauchsspuren|fleck|flecken|verfarbung|verfarbungen)\b"#, options: .regularExpression) != nil
    }
}
