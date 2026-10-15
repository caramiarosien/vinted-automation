import XCTest
@testable import WerkstattCore

final class PublicationTests: XCTestCase {
    func testOldBackupDecodesWithoutPublicationFieldAndRoundtripsNewRecords() throws {
        let encoder = JSONEncoder(); let decoder = JSONDecoder()
        let original = Item(title: "Mein Titel", description: "Mein Text", answers: ["battery": "good"])
        var object = try JSONSerialization.jsonObject(with: encoder.encode(original)) as! [String: Any]
        object.removeValue(forKey: "publications")
        var restored = try decoder.decode(Item.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.publications, [])
        XCTAssertEqual(restored.description, original.description)
        restored.publications = [ListingPublication(platform: .vinted, url: "https://www.vinted.de/items/123", confirmedAt: Date(timeIntervalSince1970: 100))]
        XCTAssertEqual(try decoder.decode(Item.self, from: encoder.encode(restored)), restored)
    }
    func testPublicationDoesNotInventAnswersOrBypassReadiness() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(root: root)
        let p = try store.importPhoto(data: Data("original".utf8), filename: "foto.jpg", previewData: Data("preview".utf8))
        var item = try store.createItem(photoIDs: [p.id], kind: .smartwatch)
        item.publications = [ListingPublication(platform: .kleinanzeigen)]
        try store.updateItem(item, expectedRevision: item.revision)
        var saved = store.library.items[0]
        XCTAssertEqual(saved.displayStatus, .published)
        XCTAssertEqual(saved.status, .draft)
        XCTAssertEqual(saved.answers, [:])
        XCTAssertFalse(Questionnaire.blockers(item: saved, photos: store.library.photos).isEmpty)
        saved.status = .ready
        XCTAssertThrowsError(try store.updateItem(saved, expectedRevision: saved.revision))
        XCTAssertEqual(try LibraryStore(root: root).library.items[0].displayStatus, .published)
    }
    func testLegacyMigrationIsExactAndIdempotent() {
        let confirmed = Item(id: "yes", platform: .vinted, notes: "Mac-Fortschritt vor dem Umzug: published. In der iPhone-App zuerst die Auswahlfragen beantworten.", listingURL: "https://www.vinted.de/items/123")
        let draft = Item(id: "no", notes: "Mac-Fortschritt vor dem Umzug: ready. Noch nicht veröffentlicht.", listingURL: "https://www.kleinanzeigen.de/p-anzeige-aufgeben-schritt2.html?draftId=123")
        let migrated = PublicationHistory.migrate(Library(items: [confirmed, draft]))
        XCTAssertEqual(migrated.items[0].displayStatus, .published)
        XCTAssertEqual(migrated.items[0].publications[0].origin, .macImport)
        XCTAssertEqual(migrated.items[0].answers.count, 1)
        XCTAssertEqual(migrated.items[1], draft)
        XCTAssertEqual(PublicationHistory.migrate(migrated), migrated)
        var cleared = migrated; cleared.items[0].publications = []
        XCTAssertEqual(PublicationHistory.migrate(cleared), cleared)
    }
    func testSoldAndArchivedKeepTheirDisplayState() {
        var item = Item(status: .ready, publications: [ListingPublication(platform: .vinted)])
        XCTAssertEqual(item.displayStatus, .published)
        item.status = .sold; XCTAssertEqual(item.displayStatus, .sold)
        item.status = .archived; XCTAssertEqual(item.displayStatus, .archived)
    }
    func testDraftLinksAndUnsafeLinksCannotRepresentPublicURLs() {
        for link in ["javascript:alert(1)", "http://www.vinted.de/items/1", "https://www.kleinanzeigen.de/p-anzeige-aufgeben-schritt2.html?draftId=secret", "https://www.vinted.de/items/new", "https://name:secret@example.com/item"] {
            XCTAssertFalse(ListingPublication.isPublicURL(link), link)
        }
        XCTAssertTrue(ListingPublication.isPublicURL("https://www.kleinanzeigen.de/s-anzeige/stuhl/123"))
    }
}
