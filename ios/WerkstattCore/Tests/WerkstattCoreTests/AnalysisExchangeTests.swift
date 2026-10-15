import XCTest
@testable import WerkstattCore

final class AnalysisExchangeTests: XCTestCase {
    private let photos = [Photo(id: "front", filename: "front.heic", itemID: "item"), Photo(id: "label", filename: "label.heic", itemID: "item", isSelected: false)]
    private func data(_ extras: [String: Any] = [:], revision: Int = 3, itemID: String = "item") throws -> Data {
        var object: [String: Any] = ["schemaVersion": 1, "type": "analysis_response", "itemID": itemID, "revision": revision]
        for (key, value) in extras { object[key] = value }
        return try JSONSerialization.data(withJSONObject: object)
    }
    func testRequestExcludesUnselectedLabelByDefault() throws {
        let item = Item(id: "item", photoOrder: ["label", "front"], revision: 3)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: AnalysisExchange.requestData(item: item, photos: photos)) as? [String: Any])
        let images = try XCTUnwrap(object["photos"] as? [[String: Any]])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0]["isSelected"] as? Bool, true)
        XCTAssertEqual(images[0]["relativePath"] as? String, "photos/front.jpg")
        let shared = try XCTUnwrap(object["item"] as? [String: Any])
        XCTAssertEqual(shared["photoOrder"] as? [String], ["front"])
    }
    func testRequestScrubsPrivateNotesSerialFactsAndInternalMetadata() throws {
        let item = Item(id: "item", answers: ["condition": "good", "battery": "good", "_identityOrigin": "manual", "_coverOrigin": "manual"], facts: ["Kleine Macke an der Rückseite", "SN: 9383811", "IMEI 35353737", "Seriennummer ABC", "S / N PRIVATE", "Artikelnummer IKEA 202.507.19"], questions: ["Funktion geprüft?", "Seriennummer 123 bestätigen?"], notes: "Persönliche Notiz mit Kontaktdaten", listingURL: "https://www.kleinanzeigen.de/p-anzeige-aufgeben-schritt2.html?draftId=secret", revision: 3)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: AnalysisExchange.requestData(item: item, photos: photos)) as? [String: Any])
        let shared = try XCTUnwrap(object["item"] as? [String: Any])
        XCTAssertEqual(shared["notes"] as? String, "")
        XCTAssertEqual(shared["listingURL"] as? String, "")
        XCTAssertEqual(shared["answers"] as? [String: String], ["condition": "good", "battery": "good"])
        XCTAssertEqual(shared["facts"] as? [String], ["Kleine Macke an der Rückseite", "Artikelnummer IKEA 202.507.19"])
        XCTAssertEqual(shared["questions"] as? [String], ["Funktion geprüft?"])
        XCTAssertEqual(item.notes, "Persönliche Notiz mit Kontaktdaten")
    }
    func testImportIsSameArticleRevisionBoundAndSellerFieldsHavePriority() throws {
        let item = Item(id: "item", title: "Mein eigener Titel", description: "Mein Text", kind: .smartwatch, condition: "Gut", price: 100, coverPhotoID: "front", photoOrder: ["front", "label"], answers: ["battery": "good", "_coverOrigin": "manual", "_identityOrigin": "manual"], revision: 3)
        let response = try data(["title": "Anderer Titel", "brand": "Samsung", "facts": ["Kleine Macke am Gehäuse"], "coverPhotoID": "front", "photoOrder": ["front"]])
        let result = try AnalysisExchange.applyResponse(response, to: item, photos: photos)
        XCTAssertEqual(result.title, "Mein eigener Titel")
        XCTAssertEqual(result.description, "Mein Text")
        XCTAssertEqual(result.condition, "Gut")
        XCTAssertEqual(result.answers, item.answers)
        XCTAssertEqual(result.price, 100)
        XCTAssertEqual(result.photoOrder, item.photoOrder)
        XCTAssertEqual(result.brand, "Samsung")
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(revision: 2), to: item, photos: photos)) { XCTAssertEqual($0 as? WerkstattError, .conflict) }
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(itemID: "other"), to: item, photos: photos))
    }
    func testInvalidCoverUnsafeURLAndUnjustifiedPriceAreRejectedAtomically() throws {
        let item = Item(id: "item", revision: 3)
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["coverPhotoID": "label"]), to: item, photos: photos))
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["price": 90]), to: item, photos: photos))
        let source: [String: Any] = ["title": "Vergleich", "url": "javascript:alert(1)", "checked": "2026-10-15", "note": "privat", "kind": "asking", "price": 90]
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["sources": [source]]), to: item, photos: photos))
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["condition": "Neu"]), to: item, photos: photos))
        XCTAssertEqual(item.price, nil)
        XCTAssertEqual(item.facts, [])
    }
    func testVerifiedPriceSourcesAndOpenReviewQuestionsImport() throws {
        let item = Item(id: "item", revision: 3)
        let source: [String: Any] = ["title": "Passender privater Vergleich", "url": "https://www.kleinanzeigen.de/s-anzeige/beispiel/123-93-42", "checked": "2026-10-15", "note": "Angebotspreis, keine belegte Transaktion", "kind": "asking", "price": 90]
        let result = try AnalysisExchange.applyResponse(try data(["price": 90, "pricingNote": "90 € VB als geschätzter Startpreis.", "sources": [source], "coverPhotoID": "front", "photoOrder": ["front"], "questions": ["Größe am Modell prüfen"]]), to: item, photos: photos)
        XCTAssertEqual(result.price, 90)
        XCTAssertEqual(result.sources.first?.kind, "asking")
        XCTAssertEqual(result.coverPhotoID, "front")
        XCTAssertTrue(Questionnaire.questions(for: result).contains(where: { $0.id == "review-0" }))
    }
    func testAnalysisReplacesOCRHintsButNeverManualIdentityOrCover() throws {
        var item = Item(id: "item", title: "Galaxy Watch", brand: "", kind: .smartwatch, answers: ["_identityOrigin": "ocr"], revision: 3)
        let response = try data(["title": "Galaxy Watch6 Classic 43 mm", "brand": "Samsung", "coverPhotoID": "front", "photoOrder": ["front"]])
        var result = try AnalysisExchange.applyResponse(response, to: item, photos: photos)
        XCTAssertEqual(result.title, "Galaxy Watch6 Classic 43 mm")
        XCTAssertEqual(result.answers["_identityOrigin"], "analysis")
        XCTAssertEqual(result.answers["_coverOrigin"], "analysis")
        item.title = "Mein geprüfter Titel"
        item.answers["_identityOrigin"] = "manual"
        item.answers["_coverOrigin"] = "manual"
        item.coverPhotoID = "front"
        item.photoOrder = ["label", "front"]
        result = try AnalysisExchange.applyResponse(response, to: item, photos: photos)
        XCTAssertEqual(result.title, "Mein geprüfter Titel")
        XCTAssertEqual(result.photoOrder, ["label", "front"])
        XCTAssertEqual(result.answers["_coverOrigin"], "manual")
    }
    func testSelectedOnlyResponseMergesInternalPhotosAndKeepsManualChoice() throws {
        let owned = [Photo(id: "front", itemID: "item"), Photo(id: "back", itemID: "item"), Photo(id: "label", itemID: "item", isSelected: false), Photo(id: "foreign", itemID: "another")]
        var item = Item(id: "item", photoOrder: ["label", "front", "back"], revision: 3)
        let response = try data(["coverPhotoID": "back", "photoOrder": ["back", "front"]])
        let result = try AnalysisExchange.applyResponse(response, to: item, photos: owned)
        XCTAssertEqual(result.photoOrder, ["back", "front", "label"])
        XCTAssertEqual(result.coverPhotoID, "back")
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["photoOrder": ["front"]]), to: item, photos: owned))
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["photoOrder": ["front", "back", "foreign"]]), to: item, photos: owned))
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["photoOrder": ["front", "back", "label"]]), to: item, photos: owned))
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["photoOrder": ["front", "back", "back"]]), to: item, photos: owned))
        item.answers["_coverOrigin"] = "manual"
        item.coverPhotoID = "front"
        let preserved = try AnalysisExchange.applyResponse(response, to: item, photos: owned)
        XCTAssertEqual(preserved.photoOrder, item.photoOrder)
        XCTAssertEqual(preserved.coverPhotoID, "front")
    }
    func testReadyArticleCannotBeRewrittenByAnalysis() throws {
        let item = Item(id: "item", status: .ready, revision: 3)
        XCTAssertThrowsError(try AnalysisExchange.applyResponse(try data(["facts": ["Ungeprüft"]]), to: item, photos: photos))
    }
}
