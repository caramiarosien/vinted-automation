import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import UIKit
import WerkstattCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var library = Library()
    @Published var errorMessage: String?
    @Published private(set) var isBusy = false
    private var store: LibraryStore?
    private let root: URL
    private let fm = FileManager.default

    init() {
        var documentRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #if DEBUG && targetEnvironment(simulator)
        // UI automation uses its own persistent sandbox, never the user's library.
        let testID = ProcessInfo.processInfo.environment["WERKSTATT_UI_TEST_ID"].flatMap(UUID.init(uuidString:))
        if let testID { documentRoot = documentRoot.appendingPathComponent("UI-Tests/" + testID.uuidString, isDirectory: true) }
        #endif
        root = documentRoot.appendingPathComponent("Werkstatt", isDirectory: true)
        do {
            let loaded = try LibraryStore(root: root)
            #if DEBUG && targetEnvironment(simulator)
            if testID != nil && loaded.library.items.isEmpty {
                let kind = ProductKind(rawValue: ProcessInfo.processInfo.environment["WERKSTATT_UI_TEST_KIND"] ?? "smartwatch") ?? .smartwatch
                let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
                    UIColor.systemGreen.setFill(); context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
                }
                guard let data = image.jpegData(compressionQuality: 0.9) else { throw WerkstattError.validation("Testfoto konnte nicht erstellt werden.") }
                let photo = try loaded.importPhoto(data: data, filename: "Simulator-Test.jpg", previewData: data)
                var fixture = try loaded.createItem(photoIDs: [photo.id], kind: kind)
                fixture.title = "Simulator-Testartikel"
                fixture.price = 100
                fixture.pricingNote = "Preisbegründung-Test"
                fixture.sources = [PriceSource(title: "Testvergleich", url: "https://example.com/vergleich", checked: "2026-10-15", price: 100)]
                try loaded.updateItem(fixture, expectedRevision: fixture.revision)
            }
            #endif
            store = loaded
            library = loaded.library
        } catch {
            errorMessage = "Dein Bestand konnte nicht geladen werden. Er wurde nicht ersetzt. Du kannst eine Sicherung wiederherstellen.\n\(error.localizedDescription)"
        }
    }
    func resetError() { errorMessage = nil }
    func item(id: String) -> Item? { library.items.first { $0.id == id } }
    func photoURL(_ photo: Photo, preview: Bool = true) -> URL? {
        try? store?.imageURL(photoID: photo.id, preview: preview)
    }
    func questions(item: Item) -> [GuidedQuestion] { Questionnaire.questions(for: item) }
    func setPublications(itemID: String, publications: [ListingPublication], expectedRevision: Int? = nil) {
        perform { current in
            guard var item = current.library.items.first(where: { $0.id == itemID }) else { throw WerkstattError.missing("Artikel") }
            let revision = item.revision
            if let expectedRevision, expectedRevision != revision { throw WerkstattError.conflict }
            item.publications = publications
            item.answers["_publicationMigrated"] = "1"
            if item.status == .published { item.status = .draft }
            try current.updateItem(item, expectedRevision: revision)
        }
    }
    private func availableStore() throws -> LibraryStore {
        guard let store else { throw WerkstattError.validation("Der Bestand ist nicht geladen. Bitte zuerst eine gültige Sicherung wiederherstellen.") }
        return store
    }
    private func perform(_ operation: (LibraryStore) throws -> Void) {
        resetError()
        do {
            let current = try availableStore()
            try operation(current)
            library = current.library
        } catch { errorMessage = error.localizedDescription }
    }

    func importPhotoData(_ data: Data, filename: String) async {
        guard !isBusy else { errorMessage = "Bitte den laufenden Import abwarten."; return }
        isBusy = true; resetError()
        defer { isBusy = false }
        do {
            guard data.count <= 64 * 1_024 * 1_024 else { throw WerkstattError.validation("Ein Foto darf höchstens 64 MB groß sein.") }
            let preview = try await Task.detached(priority: .userInitiated) {
                try PhotoRendering.jpeg(data, maximumDimension: 1_600)
            }.value
            var actualFilename = filename
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let type = CGImageSourceGetType(source), let ext = UTType(type as String)?.preferredFilenameExtension {
                actualFilename = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + "." + ext
            }
            let current = try availableStore()
            _ = try current.importPhoto(data: data, filename: actualFilename, previewData: preview)
            library = current.library
        } catch { errorMessage = error.localizedDescription }
    }
    func createItem(photoIDs: [String], kind: ProductKind) -> String? {
        resetError()
        do {
            let current = try availableStore()
            let item = try current.createItem(photoIDs: photoIDs, kind: kind)
            library = current.library
            return item.id
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func saveItem(_ item: Item) {
        perform { current in
            var update = item
            if let original = current.library.items.first(where: { $0.id == item.id }) {
                if original.status == .published {
                    if update.publications.isEmpty {
                        update.publications = [ListingPublication(platform: original.platform == .both ? nil : original.platform, url: ListingPublication.isPublicURL(original.listingURL) ? original.listingURL : "")]
                    }
                    if original.platform != item.platform { update.status = .draft }
                }
                if original.title != item.title || original.brand != item.brand || original.color != item.color || original.variant != item.variant || original.category != item.category || original.kind != item.kind {
                    update.answers["_identityOrigin"] = "manual"
                }
                if original.coverPhotoID != item.coverPhotoID || original.photoOrder != item.photoOrder { update.answers["_coverOrigin"] = "manual" }
                if original.kind != item.kind {
                    for key in ["function", "functionIssue", "battery", "charger", "packaging", "chairRotation", "chairHeight"] { update.answers.removeValue(forKey: key) }
                    if update.status != .archived { update.status = .draft }
                }
            }
            try current.updateItem(update, expectedRevision: item.revision)
        }
    }
    func answer(itemID: String, questionID: String, choiceIDs: [String]) {
        perform { current in
            guard var item = current.library.items.first(where: { $0.id == itemID }),
                  let question = Questionnaire.allQuestions(for: item).first(where: { $0.id == questionID }) else {
                throw WerkstattError.missing("Frage")
            }
            let choices = Set(choiceIDs)
            guard !choices.isEmpty, choices.isSubset(of: Set(question.choices.map(\.id))),
                  question.allowsMultiple || choices.count == 1 else { throw WerkstattError.validation("Bitte eine gültige Antwort auswählen.") }
            if choices.count > 1 && (choices.contains("none") || choices.contains("later") || choices.contains("other")) {
                throw WerkstattError.validation("„Keine weiteren Mängel“, „Anderer Mangel“ oder „Später prüfen“ bitte einzeln auswählen.")
            }
            let revision = item.revision
            item.answers[questionID] = choiceIDs.joined(separator: ",")
            // Old conditional answers must not silently reappear after changing an earlier card.
            if questionID == "condition" { for key in ["defects", "function", "functionIssue", "packaging"] { item.answers.removeValue(forKey: key) } }
            if questionID == "function" { item.answers.removeValue(forKey: "functionIssue") }
            item.condition = ListingComposer.applyAnswers(to: item, location: current.library.defaultLocation).condition
            if item.status == .ready { item.status = .draft }
            try current.updateItem(item, expectedRevision: revision)
        }
    }
    func regenerate(itemID: String) {
        perform { current in
            guard let item = current.library.items.first(where: { $0.id == itemID }) else { throw WerkstattError.missing("Artikel") }
            var composed = ListingComposer.applyAnswers(to: item, location: current.library.defaultLocation)
            if composed.status == .ready { composed.status = .draft }
            try current.updateItem(composed, expectedRevision: item.revision)
        }
    }
    func regroup(photoIDs: [String], destinationID: String?) {
        perform { try $0.regroup(photoIDs: photoIDs, destinationID: destinationID) }
    }
    func setPhotoSelected(photoID: String, itemID: String, selected: Bool) {
        perform { current in
            var next = current.library
            guard let photoIndex = next.photos.firstIndex(where: { $0.id == photoID && $0.itemID == itemID }),
                  let itemIndex = next.items.firstIndex(where: { $0.id == itemID }) else { throw WerkstattError.missing("Artikelfoto") }
            guard next.items[itemIndex].status == .draft || next.items[itemIndex].status == .ready else {
                throw WerkstattError.validation("Die Fotoauswahl bitte vor dem Einstellen ändern.")
            }
            next.photos[photoIndex].isSelected = selected
            if !selected && next.items[itemIndex].coverPhotoID == photoID {
                next.items[itemIndex].coverPhotoID = next.items[itemIndex].photoOrder.first { id in
                    next.photos.contains { $0.id == id && $0.itemID == itemID && $0.isSelected }
                }
                next.items[itemIndex].coverReason = ""
            }
            if next.items[itemIndex].status == .ready { next.items[itemIndex].status = .draft }
            next.items[itemIndex].revision += 1; next.items[itemIndex].updatedAt = Date()
            try current.save(next)
        }
    }
    func setDefaultLocation(_ value: String) {
        perform { current in
            let location = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !location.isEmpty, location.count <= 100 else { throw WerkstattError.validation("Bitte einen Ort mit höchstens 100 Zeichen eingeben.") }
            var next = current.library; next.defaultLocation = location
            try current.save(next)
        }
    }
    func runOCR(itemID: String) async {
        guard !isBusy else { return }
        isBusy = true; resetError(); defer { isBusy = false }
        do {
            let current = try availableStore()
            guard var item = current.library.items.first(where: { $0.id == itemID }) else { throw WerkstattError.missing("Artikel") }
            guard item.status == .draft else { throw WerkstattError.validation("Texterkennung ist für Artikel in Prüfung verfügbar.") }
            let revision = item.revision
            let photos = current.library.photos.filter { $0.itemID == itemID }
            let inputs = try photos.map { OCRInput(photoID: $0.id, url: try current.imageURL(photoID: $0.id, preview: true)) }
            let observations = try await VisionScanner.scan(inputs)
            guard current.library.items.first(where: { $0.id == itemID })?.revision == revision else { throw WerkstattError.conflict }
            let text = observations.filter { !$0.mayContainPrivateLabel }.map(\.text).joined(separator: "\n")
            if let hint = DetectionHints.from(text: text) {
                if item.title.isEmpty { item.title = hint.title; item.answers["_identityOrigin"] = "ocr" }
                if item.brand.isEmpty { item.brand = hint.brand }
                if item.color.isEmpty { item.color = hint.color }
                if item.kind == .other { item.kind = hint.kind }
                if item.category.isEmpty {
                    switch item.kind {
                    case .smartwatch: item.category = "Elektronik > Wearables"
                    case .headphones: item.category = "Elektronik > Audio & Hifi"
                    case .chair: item.category = "Haus & Garten > Büro"
                    case .supplies: item.category = "Hobby > Bastelmaterial"
                    case .other: break
                    }
                }
                let fact = "Modellhinweis aus lokaler Texterkennung – bitte mit Verpackung oder Etikett prüfen."
                if !item.facts.contains(fact) { item.facts.append(fact) }
            }
            // No raw label text is stored or shared; potentially private labels stay internal.
            var next = current.library
            next.items[next.items.firstIndex(where: { $0.id == itemID })!] = item
            for observation in observations where observation.mayContainPrivateLabel {
                if let idx = next.photos.firstIndex(where: { $0.id == observation.photoID }) { next.photos[idx].isSelected = false }
                if item.coverPhotoID == observation.photoID { item.coverPhotoID = nil; item.coverReason = "" }
            }
            if observations.contains(where: \.mayContainPrivateLabel) {
                item.notes += "\nBelegfoto mit möglicher Seriennummer intern gehalten; bewusst für Analyse/Export auswählen, falls benötigt."
            }
            item.revision += 1; item.updatedAt = Date()
            next.items[next.items.firstIndex(where: { $0.id == itemID })!] = item
            try current.save(next)
            library = current.library
        } catch { errorMessage = error.localizedDescription }
    }

    func importAnalysis(url: URL, itemID: String) {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        perform { current in
            guard let item = current.library.items.first(where: { $0.id == itemID }) else { throw WerkstattError.missing("Artikel") }
            let data = try Data(contentsOf: url)
            var updated = try AnalysisExchange.applyResponse(data, to: item, photos: current.library.photos)
            if item.description.isEmpty { updated = ListingComposer.applyAnswers(to: updated, location: current.library.defaultLocation) }
            try current.updateItem(updated, expectedRevision: item.revision)
        }
    }
    func exportAnalysis(itemID: String) -> URL? {
        exportFile(name: "Analyse") { current in
            guard let item = current.library.items.first(where: { $0.id == itemID }) else { throw WerkstattError.missing("Artikel") }
            let photos = current.library.photos.filter { $0.itemID == itemID && $0.isSelected }
            var entries = ["analysis-request.json": try AnalysisExchange.requestData(item: item, photos: photos)]
            entries["LIESMICH.txt"] = Data("Fotos und analysis-request.json im Chat prüfen lassen. Die Antwort als analysis-response.json in denselben Artikel importieren. Der Revisionswert schützt zwischenzeitliche Änderungen. Nicht veröffentlichen, bevor die Fragen geklärt sind.".utf8)
            for photo in photos {
                entries["photos/\(photo.id).jpg"] = try PhotoRendering.jpeg(Data(contentsOf: current.imageURL(photoID: photo.id)))
            }
            return try ZIPArchive.make(entries: entries)
        }
    }
    func exportListing(itemID: String) -> URL? {
        exportFile(name: "Angebot") { current in
            guard let item = current.library.items.first(where: { $0.id == itemID }) else { throw WerkstattError.missing("Artikel") }
            let photos = current.library.photos.filter { $0.itemID == itemID }
            let blockers = Questionnaire.blockers(item: item, photos: photos)
            guard [.ready, .published, .sold].contains(item.status), blockers.isEmpty else {
                throw WerkstattError.validation("Bitte Angebot prüfen und als bereit markieren. " + blockers.joined(separator: " "))
            }
            // Internal facts, notes, raw answers and serial-label photos are excluded.
            let publicInfo: [String: Any] = ["title": item.title, "description": item.description,
                "brand": item.brand, "category": item.category, "color": item.color,
                "variant": item.variant, "condition": item.condition, "price": item.price ?? 0,
                "price_type": item.priceType.rawValue, "platform": item.platform.rawValue]
            var entries = ["Titel.txt": Data(item.title.utf8), "Beschreibung.txt": Data(item.description.utf8),
                "Artikeldaten.json": try JSONSerialization.data(withJSONObject: publicInfo, options: [.prettyPrinted, .sortedKeys])]
            let selected = photos.filter(\.isSelected).sorted { a, b in
                if a.id == item.coverPhotoID { return true }; if b.id == item.coverPhotoID { return false }
                return (item.photoOrder.firstIndex(of: a.id) ?? Int.max) < (item.photoOrder.firstIndex(of: b.id) ?? Int.max)
            }
            for (index, photo) in selected.enumerated() {
                entries[String(format: "Fotos/%02d.jpg", index + 1)] = try PhotoRendering.jpeg(Data(contentsOf: current.imageURL(photoID: photo.id)))
            }
            return try ZIPArchive.make(entries: entries)
        }
    }
    private func exportFile(name: String, content: (LibraryStore) throws -> Data) -> URL? {
        resetError()
        do {
            let current = try availableStore()
            let data = try content(current)
            let folder = fm.temporaryDirectory.appendingPathComponent("Werkstatt-Exporte", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("\(name)-\(UUID().uuidString).zip")
            try data.write(to: url, options: .atomic)
            return url
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func exportBackup() -> URL? {
        exportFile(name: "Werkstatt-Sicherung") { current in
            // Serialize the current snapshot, not an earlier file that might be in transition.
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var entries = ["library.json": try encoder.encode(current.library)]
            for photo in current.library.photos {
                entries[photo.relativePath] = try Data(contentsOf: current.imageURL(photoID: photo.id))
                entries[photo.previewRelativePath] = try Data(contentsOf: current.imageURL(photoID: photo.id, preview: true))
            }
            return try ZIPArchive.make(entries: entries)
        }
    }
    func restoreBackup(url: URL) {
        resetError()
        guard !isBusy else { errorMessage = "Bitte den laufenden Vorgang abwarten."; return }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let parent = root.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("Werkstatt-Restore-\(UUID().uuidString)", isDirectory: true)
        let retained = parent.appendingPathComponent("Werkstatt-Vor-Wiederherstellung-\(UUID().uuidString)", isDirectory: true)
        var movedOld = false
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 256 * 1_024 * 1_024 else { throw WerkstattError.validation("Die Sicherung ist größer als 256 MB.") }
            let entries = try ZIPArchive.read(Data(contentsOf: url))
            guard let metadata = entries["library.json"] else { throw WerkstattError.validation("Diese Datei ist keine Werkstatt-Sicherung.") }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(Library.self, from: metadata)
            let allowed = Set(["library.json"] + decoded.photos.flatMap { [$0.relativePath, $0.previewRelativePath] })
            guard Set(entries.keys) == allowed else { throw WerkstattError.validation("Die Sicherung enthält fehlende oder unerwartete Dateien.") }
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            for (path, data) in entries { let target = staging.appendingPathComponent(path); try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: target, options: .atomic) }
            let candidate = try LibraryStore(root: staging)
            try candidate.save(candidate.library) // Full model, path and hash validation before touching current data.
            for photo in candidate.library.photos {
                _ = try candidate.imageURL(photoID: photo.id)
                // Reject malformed or oversized preview images before they reach UIImage.
                let preview = try Data(contentsOf: candidate.imageURL(photoID: photo.id, preview: true))
                _ = try PhotoRendering.jpeg(preview, maximumDimension: 1_600)
            }
            if fm.fileExists(atPath: root.path) { try fm.moveItem(at: root, to: retained); movedOld = true }
            try fm.moveItem(at: staging, to: root)
            store = try LibraryStore(root: root)
            library = store!.library
        } catch {
            if movedOld {
                if fm.fileExists(atPath: root.path) { try? fm.removeItem(at: root) }
                try? fm.moveItem(at: retained, to: root)
                store = try? LibraryStore(root: root)
                if let store { library = store.library }
            }
            errorMessage = "Die Sicherung konnte nicht wiederhergestellt werden. Der bisherige Bestand bleibt erhalten.\n\(error.localizedDescription)"
        }
        try? fm.removeItem(at: staging)
    }
}
