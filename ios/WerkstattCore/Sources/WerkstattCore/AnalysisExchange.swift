import Foundation

/// Explicit file exchange with the chat; no network requests or API credentials.
public enum AnalysisExchange {
    private struct RequestPhoto: Encodable {
        let id: String, filename: String, relativePath: String
        let isSelected: Bool
    }
    private struct Request: Encodable {
        let schemaVersion = 1
        let type = "analysis_request"
        let itemID: String
        let revision: Int
        let item: Item
        let photos: [RequestPhoto]
        let instructions: [String]
    }
    private struct Response: Decodable {
        let schemaVersion: Int
        let type: String
        let itemID: String
        let revision: Int
        let kind: ProductKind?
        let title: String?, brand: String?, category: String?, color: String?, variant: String?
        let facts: [String]?, questions: [String]?
        let price: Double?, pricingNote: String?, sources: [PriceSource]?
        let coverPhotoID: String?, coverReason: String?, photoOrder: [String]?
    }
    public static func requestData(item: Item, photos: [Photo]) throws -> Data {
        let owned = photos.filter { $0.itemID == item.id && $0.isSelected }
        guard !owned.isEmpty else { throw WerkstattError.validation("Keine Fotos für das Analysepaket vorhanden.") }
        guard Set(owned.map(\.id)).count == owned.count else { throw WerkstattError.validation("Doppelte Foto-IDs im Analysepaket.") }
        // Excluded label/serial photos are never shared automatically. The seller can select
        // a necessary model photo explicitly after checking it contains no sensitive data.
        let requestPhotos = owned.map { RequestPhoto(id: $0.id, filename: $0.filename, relativePath: "photos/\($0.id).jpg", isSelected: $0.isSelected) }
        var sharedItem = item
        sharedItem.notes = ""
        sharedItem.listingURL = ""
        sharedItem.answers = item.answers.filter { !$0.key.hasPrefix("_") }
        let sharedIDs = Set(owned.map(\.id))
        sharedItem.photoOrder = item.photoOrder.filter { sharedIDs.contains($0) }
        sharedItem.photoOrder += owned.map(\.id).filter { !sharedItem.photoOrder.contains($0) }
        if let cover = sharedItem.coverPhotoID, !sharedIDs.contains(cover) {
            sharedItem.coverPhotoID = nil; sharedItem.coverReason = ""
        }
        sharedItem.facts = item.facts.filter { !containsPrivateLabel($0) }
        sharedItem.questions = item.questions.filter { !containsPrivateLabel($0) }
        let request = Request(itemID: item.id, revision: item.revision, item: sharedItem, photos: requestPhotos, instructions: [
            "Alle mitgelieferten Bilder ansehen. Nicht anhand von Dateinamen oder Reihenfolge gruppieren.",
            "Modell und Varianten mit Quellen prüfen. Unklare Attribute leer lassen.",
            "Funktion, Akkugesundheit und Laufzeit nicht aus Fotos erfinden. Verkäuferantworten haben Vorrang.",
            "Konkrete sichtbare Mängel als facts, offene Punkte als questions. Keine Seriennummern in öffentlichen Texten.",
            "Alle Bilder für das Titelbild vergleichen; ausgeschlossenes Etikettfoto nicht als Titelbild wählen.",
            "Aktuelle Detailseiten über mehrere Marktplätze prüfen; Angebotspreise, belegte Verkaufspreise und Händlerpreise unterscheiden.",
            "Antwortformat: schemaVersion 1, type analysis_response, itemID und revision unverändert; Preisquellen und pricingNote angeben.",
            "photoOrder enthält genau alle mitgelieferten ausgewählten Foto-IDs, jede genau einmal. Interne ausgeschlossene Fotos nicht anfordern oder in die Antwort aufnehmen.",
            "Keine Felder für answers, condition, description, platform oder status zurückgeben. Veröffentlichung erfolgt manuell."
        ])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(request)
    }
    public static func applyResponse(_ data: Data, to item: Item, photos: [Photo]) throws -> Item {
        guard data.count <= 2 * 1_024 * 1_024 else { throw WerkstattError.validation("Die Analyseantwort ist zu groß.") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WerkstattError.validation("Die Analyseantwort muss ein JSON-Objekt sein.") }
        let allowed: Set<String> = ["schemaVersion", "type", "itemID", "revision", "kind", "title", "brand", "category", "color", "variant", "facts", "questions", "price", "pricingNote", "sources", "coverPhotoID", "coverReason", "photoOrder"]
        guard Set(object.keys).isSubset(of: allowed) else { throw WerkstattError.validation("Die Analyseantwort enthält nicht erlaubte Felder. Verkäuferangaben bleiben geschützt.") }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw WerkstattError.validation("Die Analyseantwort hat nicht das erwartete Format: \(error.localizedDescription)") }
        guard response.schemaVersion == 1, response.type == "analysis_response" else { throw WerkstattError.validation("Nicht unterstütztes Analyseformat.") }
        guard response.itemID == item.id else { throw WerkstattError.validation("Die Analyse gehört zu einem anderen Artikel.") }
        guard response.revision == item.revision else { throw WerkstattError.conflict }
        guard item.status == .draft else { throw WerkstattError.validation("Analyseantworten nur in Artikel mit Status „In Prüfung“ importieren.") }
        try validate(response: response, item: item, photos: photos)
        var result = item
        // A revision token prevents races; fill-only preserves earlier seller edits in addition.
        let replaceOCR = item.answers["_identityOrigin"] == "ocr"
        if let value = response.title, result.title.isEmpty || replaceOCR { result.title = value }
        if let value = response.brand, result.brand.isEmpty || replaceOCR { result.brand = value }
        if let value = response.category, result.category.isEmpty || replaceOCR { result.category = value }
        if let value = response.color, result.color.isEmpty || replaceOCR { result.color = value }
        if let value = response.variant, result.variant.isEmpty || replaceOCR { result.variant = value }
        if let value = response.kind, result.kind == .other || replaceOCR { result.kind = value }
        if replaceOCR { result.answers["_identityOrigin"] = "analysis" }
        for fact in response.facts ?? [] where !result.facts.contains(fact) { result.facts.append(fact) }
        for question in response.questions ?? [] where !result.questions.contains(question) { result.questions.append(question) }
        if result.price == nil, let price = response.price {
            result.price = price
            result.pricingNote = response.pricingNote ?? ""
        }
        for source in response.sources ?? [] where !result.sources.contains(source) { result.sources.append(source) }
        if result.pricingNote.isEmpty { result.pricingNote = response.pricingNote ?? "" }
        // Seller cover/order choices have priority over provisional or previous analysis choices.
        if item.answers["_coverOrigin"] != "manual", let cover = response.coverPhotoID {
            result.coverPhotoID = cover; result.coverReason = response.coverReason ?? ""
            result.answers["_coverOrigin"] = "analysis"
        }
        if item.answers["_coverOrigin"] != "manual", let order = response.photoOrder {
            let internalIDs = Set(photos.filter { $0.itemID == item.id && !$0.isSelected }.map(\.id))
            let existingInternal = item.photoOrder.filter { internalIDs.contains($0) }
            let remainingInternal = photos.filter { $0.itemID == item.id && !$0.isSelected }.map(\.id).filter { !existingInternal.contains($0) }
            result.photoOrder = order + existingInternal + remainingInternal
        }
        if result.photoOrder.isEmpty { result.photoOrder = photos.filter { $0.itemID == item.id }.map(\.id) }
        return result
    }
    private static func validate(response: Response, item: Item, photos: [Photo]) throws {
        let fields = [response.title, response.brand, response.category, response.color, response.variant, response.coverReason]
        guard fields.allSatisfy({ ($0?.count ?? 0) <= 1_000 }), (response.pricingNote?.count ?? 0) <= 10_000,
              (response.facts?.count ?? 0) <= 100, (response.questions?.count ?? 0) <= 100,
              (response.facts ?? []).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1_000 }),
              (response.questions ?? []).allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1_000 }),
              (response.sources?.count ?? 0) <= 100 else { throw WerkstattError.validation("Analysefelder sind leer oder zu lang.") }
        let owned = photos.filter { $0.itemID == item.id }
        let selectedIDs = Set(owned.filter(\.isSelected).map(\.id))
        if let cover = response.coverPhotoID, !selectedIDs.contains(cover) { throw WerkstattError.validation("Das vorgeschlagene Titelbild ist kein ausgewähltes Foto dieses Artikels.") }
        if let order = response.photoOrder, Set(order).count != order.count || Set(order) != selectedIDs { throw WerkstattError.validation("Die vorgeschlagene Fotoreihenfolge muss alle ausgewählten mitgelieferten Fotos genau einmal enthalten.") }
        for source in response.sources ?? [] {
            guard let url = URLComponents(string: source.url), url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
                  ["asking", "sold", "retail", "refurbished", "buyback", "context"].contains(source.kind),
                  source.title.count <= 1_000, source.note.count <= 10_000, source.url.count <= 4_096,
                  validDate(source.checked), source.price == nil || (source.price!.isFinite && source.price! >= 0) else {
                throw WerkstattError.validation("Eine Preisquelle hat einen ungültigen Link, Typ, Prüfzeitpunkt oder Preis.")
            }
        }
        if let price = response.price {
            guard price.isFinite, price >= 0, price <= 1_000_000 else { throw WerkstattError.validation("Ungültiger Preisvorschlag.") }
            if item.priceType == .free {
                guard price == 0 else { throw WerkstattError.validation("Verschenkartikel dürfen keinen Verkaufspreis erhalten.") }
            } else {
                guard price > 0, !(response.sources ?? []).isEmpty, !(response.pricingNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WerkstattError.validation("Ein Preisvorschlag braucht belegte Quellen und eine Begründung.") }
            }
        }
    }
    private static func containsPrivateLabel(_ text: String) -> Bool {
        let lower = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        if ["private label", "privatetikett", "belegfoto"].contains(where: lower.contains) { return true }
        return lower.range(of: #"\b(sn|s\s*[/.-]\s*n|serial|serialnumber|seriennummer|imei|meid|udid|iccid)\b"#, options: .regularExpression) != nil
    }
    private static func validDate(_ value: String) -> Bool {
        if value.count == 10 {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let date = formatter.date(from: value) else { return false }
            return formatter.string(from: date) == value
        }
        return ISO8601DateFormatter().date(from: value) != nil
    }
}
