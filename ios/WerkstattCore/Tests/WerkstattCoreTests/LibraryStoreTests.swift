import XCTest
import CryptoKit
@testable import WerkstattCore

final class LibraryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WerkstattCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    private func photo(_ store: LibraryStore, _ number: Int = 1) throws -> Photo {
        try store.importPhoto(data: Data("original-\(number)".utf8),
                              filename: "IMG_\(number).HEIC",
                              previewData: Data("preview-\(number)".utf8))
    }

    private func ready(_ item: Item) -> Item {
        var result = item
        result.title = "Bastelmaterial"
        result.description = "Bastelmaterial mit Gebrauchsspuren. Nur Abholung in Konstanz."
        result.condition = "Gut"
        result.price = 12
        result.coverPhotoID = item.photoOrder.first
        result.answers = ["condition": "good", "defects": "normalWear", "delivery": "pickup"]
        result.status = .ready
        return result
    }

    func testSixtyArticlesSurviveRestartWithOriginalsAndOrder() throws {
        let store = try LibraryStore(root: directory)
        for number in 1...60 {
            let imported = try photo(store, number)
            let item = try store.createItem(photoIDs: [imported.id], kind: .supplies)
            XCTAssertEqual(item.photoOrder, [imported.id])
        }
        let restarted = try LibraryStore(root: directory)
        XCTAssertEqual(restarted.library.items.count, 60)
        XCTAssertEqual(restarted.library.photos.count, 60)
        for number in 1...60 {
            let stored = try XCTUnwrap(restarted.library.photos.first { $0.filename == "IMG_\(number).HEIC" })
            XCTAssertTrue(stored.relativePath.hasPrefix("bearbeitet/"))
            XCTAssertEqual(try Data(contentsOf: restarted.imageURL(photoID: stored.id)), Data("original-\(number)".utf8))
        }
        let remaining = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("inbox"), includingPropertiesForKeys: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testHashDuplicateRetainsAssignmentAndOriginalPreview() throws {
        let store = try LibraryStore(root: directory)
        let imported = try photo(store)
        let item = try store.createItem(photoIDs: [imported.id], kind: .chair)
        let duplicate = try store.importPhoto(data: Data("original-1".utf8), filename: "renamed.jpg", previewData: Data("different preview".utf8))
        XCTAssertEqual(store.library.photos.count, 1)
        XCTAssertEqual(duplicate.itemID, item.id)
        XCTAssertEqual(duplicate.filename, "IMG_1.HEIC")
        XCTAssertEqual(try Data(contentsOf: store.imageURL(photoID: imported.id, preview: true)), Data("preview-1".utf8))
    }

    func testExpectedRevisionRejectsStaleEditsAndOtherStore() throws {
        let first = try LibraryStore(root: directory)
        let imported = try photo(first)
        let item = try first.createItem(photoIDs: [imported.id], kind: .supplies)
        let stale = try LibraryStore(root: directory)
        var updated = item
        updated.title = "Aktuelle Verkäuferangabe"
        try first.updateItem(updated, expectedRevision: 1)
        XCTAssertEqual(first.library.items[0].revision, 2)
        var outdated = item
        outdated.title = "Veraltete Analyse"
        XCTAssertThrowsError(try first.updateItem(outdated, expectedRevision: 1)) { error in
            XCTAssertEqual(error as? WerkstattError, .conflict)
        }
        XCTAssertThrowsError(try stale.updateItem(outdated, expectedRevision: 1)) { error in
            XCTAssertEqual(error as? WerkstattError, .conflict)
        }
        XCTAssertEqual(try LibraryStore(root: directory).library.items[0].title, "Aktuelle Verkäuferangabe")
    }

    func testReadyValidationIsAtomicAndUnknownBatteryIsNotFabricated() throws {
        let store = try LibraryStore(root: directory)
        let imported = try photo(store)
        let item = try store.createItem(photoIDs: [imported.id], kind: .smartwatch)
        var incomplete = item
        incomplete.status = .ready
        incomplete.title = "Uhr"
        incomplete.description = "Eine Uhr."
        incomplete.condition = "Gut"
        incomplete.price = 100
        incomplete.coverPhotoID = imported.id
        incomplete.answers = ["condition": "good", "defects": "normalWear", "function": "later", "battery": "notMeasured", "charger": "included", "packaging": "unknown", "delivery": "pickup"]
        XCTAssertThrowsError(try store.updateItem(incomplete, expectedRevision: 1))
        XCTAssertEqual(store.library.items[0].status, .draft)
        XCTAssertEqual(store.library.items[0].revision, 1)
        incomplete.answers["function"] = "works"
        try store.updateItem(incomplete, expectedRevision: 1)
        XCTAssertEqual(store.library.items[0].status, .ready)
        XCTAssertEqual(store.library.items[0].answers["battery"], "notMeasured")
        XCTAssertFalse(store.library.items[0].description.contains("%"))
    }

    func testRegroupArchivesAndReturnsInboxWithoutDeletingOriginal() throws {
        let store = try LibraryStore(root: directory)
        let firstPhoto = try photo(store, 1)
        let secondPhoto = try photo(store, 2)
        let first = try store.createItem(photoIDs: [firstPhoto.id], kind: .supplies)
        let second = try store.createItem(photoIDs: [secondPhoto.id], kind: .supplies)
        try store.updateItem(ready(first), expectedRevision: 1)
        try store.regroup(photoIDs: [firstPhoto.id], destinationID: second.id)
        XCTAssertEqual(store.library.items.first { $0.id == first.id }?.status, .draft)
        XCTAssertEqual(store.library.items.first { $0.id == first.id }?.photoOrder, [])
        let moved = try XCTUnwrap(store.library.photos.first { $0.id == firstPhoto.id })
        XCTAssertTrue(moved.relativePath.hasPrefix("bearbeitet/\(second.id)/"))
        try store.regroup(photoIDs: [firstPhoto.id], destinationID: nil)
        let inbox = try XCTUnwrap(store.library.photos.first { $0.id == firstPhoto.id })
        XCTAssertNil(inbox.itemID)
        XCTAssertTrue(inbox.relativePath.hasPrefix("inbox/"))
        XCTAssertEqual(try Data(contentsOf: store.imageURL(photoID: firstPhoto.id)), Data("original-1".utf8))
        XCTAssertEqual(try LibraryStore(root: directory).library.photos.first { $0.id == firstPhoto.id }?.relativePath, inbox.relativePath)
    }

    func testArchiveCollisionDoesNotOverwriteOrCommit() throws {
        let store = try LibraryStore(root: directory)
        let imported = try photo(store)
        var candidate = store.library
        let item = Item(id: "collision-item", kind: .supplies, coverPhotoID: imported.id, photoOrder: [imported.id])
        candidate.items.append(item)
        candidate.photos[0].itemID = item.id
        let target = directory.appendingPathComponent("bearbeitet/\(item.id)/\(imported.id.prefix(12))-\(imported.filename)")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("somebody else's file".utf8).write(to: target)
        XCTAssertThrowsError(try store.save(candidate))
        XCTAssertTrue(store.library.items.isEmpty)
        XCTAssertEqual(try Data(contentsOf: store.imageURL(photoID: imported.id)), Data("original-1".utf8))
        XCTAssertEqual(try Data(contentsOf: target), Data("somebody else's file".utf8))
        XCTAssertTrue(try LibraryStore(root: directory).library.items.isEmpty)
    }

    func testRestartRecoversInterruptedMoveByHash() throws {
        let store = try LibraryStore(root: directory)
        let imported = try photo(store)
        let original = try store.imageURL(photoID: imported.id)
        let stray = directory.appendingPathComponent("bearbeitet/interrupted/\(original.lastPathComponent)")
        try FileManager.default.createDirectory(at: stray.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: stray)
        let restarted = try LibraryStore(root: directory)
        XCTAssertEqual(try Data(contentsOf: restarted.imageURL(photoID: imported.id)), Data("original-1".utf8))
        XCTAssertTrue(restarted.library.photos[0].relativePath.hasPrefix("inbox/"))
    }

    func testUnsafeRestorePathsAndSymlinkEscapeAreRejected() throws {
        let store = try LibraryStore(root: directory)
        _ = try photo(store)
        var unsafe = store.library
        unsafe.photos[0].relativePath = "../outside.jpg"
        XCTAssertThrowsError(try store.save(unsafe))
        unsafe = store.library
        unsafe.photos[0].previewRelativePath = "library.json"
        XCTAssertThrowsError(try store.save(unsafe))
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("WerkstattOutside-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let alias = directory.appendingPathComponent("bearbeitet/escape")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: external)
        unsafe = store.library
        let imported = unsafe.photos[0]
        unsafe.items.append(Item(id: "escape", kind: .supplies, coverPhotoID: imported.id, photoOrder: [imported.id]))
        unsafe.photos[0].itemID = "escape"
        XCTAssertThrowsError(try store.save(unsafe))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: external.path).isEmpty)
    }

    func testExcludedLabelCanRemainInPhotoOrderButCannotBeCover() throws {
        let store = try LibraryStore(root: directory)
        let first = try photo(store, 1)
        let label = try photo(store, 2)
        let item = try store.createItem(photoIDs: [first.id, label.id], kind: .supplies)
        var candidate = store.library
        candidate.photos[1].isSelected = false
        try store.save(candidate)
        try store.updateItem(ready(item), expectedRevision: 1)
        var wrongCover = store.library.items[0]
        wrongCover.coverPhotoID = label.id
        XCTAssertThrowsError(try store.updateItem(wrongCover, expectedRevision: 2))
        XCTAssertEqual(store.library.items[0].coverPhotoID, first.id)
    }

    func testInvalidPricesAndDuplicateOrderCannotCommit() throws {
        let store = try LibraryStore(root: directory)
        let imported = try photo(store)
        let item = try store.createItem(photoIDs: [imported.id], kind: .supplies)
        for price in [Double.nan, Double.infinity, -1, 0] {
            var invalid = item
            invalid.price = price
            XCTAssertThrowsError(try store.updateItem(invalid, expectedRevision: 1))
        }
        var duplicate = item
        duplicate.photoOrder.append(imported.id)
        XCTAssertThrowsError(try store.updateItem(duplicate, expectedRevision: 1))
        var free = ready(item)
        free.priceType = .free; free.price = 0
        try store.updateItem(free, expectedRevision: 1)
        XCTAssertEqual(store.library.items[0].price, 0)
    }

    func testSettingsSurviveRestartAndRemoteRootsAreRejected() throws {
        let store = try LibraryStore(root: directory)
        var settings = store.library
        settings.defaultLocation = "Berlin"
        try store.save(settings)
        XCTAssertEqual(try LibraryStore(root: directory).library.defaultLocation, "Berlin")
        XCTAssertThrowsError(try LibraryStore(root: URL(string: "https://example.com/library")!))
    }

    func testChangedOriginalStopsExportAndRestartWithoutDeletingEvidence() throws {
        let store = try LibraryStore(root: directory)
        let imported = try photo(store)
        let url = try store.imageURL(photoID: imported.id)
        let altered = Data("changed outside the app".utf8)
        try altered.write(to: url)
        XCTAssertThrowsError(try store.imageURL(photoID: imported.id))
        XCTAssertThrowsError(try LibraryStore(root: directory))
        XCTAssertEqual(try Data(contentsOf: url), altered)
    }

    func testPublishedAndSoldCannotBypassUnansweredReview() throws {
        let store = try LibraryStore(root: directory)
        let imported = try photo(store)
        let item = try store.createItem(photoIDs: [imported.id], kind: .supplies)
        for status in [ItemStatus.ready, .published, .sold] {
            var incomplete = ready(item)
            incomplete.status = status
            incomplete.answers = [:]
            XCTAssertThrowsError(try store.updateItem(incomplete, expectedRevision: 1))
            XCTAssertEqual(store.library.items[0].status, .draft)
            XCTAssertEqual(store.library.items[0].revision, 1)
        }
        var published = ready(item)
        published.status = .published
        try store.updateItem(published, expectedRevision: 1)
        var sold = store.library.items[0]
        sold.status = .sold
        try store.updateItem(sold, expectedRevision: 2)
        XCTAssertEqual(store.library.items[0].status, .sold)
        XCTAssertEqual(try LibraryStore(root: directory).library.items[0].status, .sold)
    }

    func testPriceCeilingRejectsOversizedValuesWithoutLosingValidEdit() throws {
        let store = try LibraryStore(root: directory)
        let imported = try photo(store)
        let item = try store.createItem(photoIDs: [imported.id], kind: .supplies)
        var allowed = item
        allowed.price = 1_000_000
        try store.updateItem(allowed, expectedRevision: 1)
        var oversized = store.library.items[0]
        oversized.price = 1_000_000.01
        XCTAssertThrowsError(try store.updateItem(oversized, expectedRevision: 2))
        XCTAssertEqual(store.library.items[0].price, 1_000_000)
        XCTAssertEqual(store.library.items[0].revision, 2)
    }
}
