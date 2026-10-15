import XCTest
@testable import WerkstattCore

final class ListingComposerTests: XCTestCase {
    func testMigratedEditorialWearNoteStaysPrivateAndWatchPackagingIsExplicit() {
        let item = Item(title: "Samsung Galaxy Watch6 Classic", kind: .smartwatch,
            answers: ["condition": "good", "defects": "normalWear", "packaging": "opened"],
            facts: ["Gebrauchsspuren auf den Fotos erkennbar; kurze neutrale Zustandsbeschreibung gemäß deinem Wunsch.", "Gebrauchsspuren am Gehäuse", "Kleine Macke gemäß deinem Wunsch knapp beschreiben", "Kleine Macke an der Rückseite"])
        let result = ListingComposer.applyAnswers(to: item, location: "Konstanz")
        XCTAssertTrue(result.description.contains("Die Originalverpackung ist dabei und wurde geöffnet."))
        XCTAssertFalse(result.description.contains("Wunsch"))
        XCTAssertFalse(result.description.contains("Zustandsbeschreibung"))
        XCTAssertEqual(result.description.components(separatedBy: "Gebrauchsspuren").count - 1, 1)
        XCTAssertTrue(result.description.contains("Kleine Macke an der Rückseite."))
        XCTAssertTrue(Questionnaire.allQuestions(for: item).contains { $0.id == "packaging" })
    }
    func testWatchUsesSellerAssessmentWithoutMeasurementsOrPrivateQuestions() {
        let item = Item(title: "Samsung Galaxy Watch6 Classic", kind: .smartwatch, answers: ["condition": "good", "function": "works", "battery": "good", "charger": "included", "delivery": "pickup"], facts: ["Schwarzes Gehäuse", "Seriennummer ABC123", "Akkugesundheit 100 %", "Akku hält 48 Stunden"], questions: ["Akkugesundheit noch messen?"])
        let result = ListingComposer.applyAnswers(to: item, location: "Konstanz")
        XCTAssertEqual(result.condition, "Gut")
        XCTAssertTrue(result.description.contains("Der Akku ist nach meiner Einschätzung in gutem Zustand."))
        XCTAssertTrue(result.description.contains("hat Gebrauchsspuren. Bitte die Fotos anschauen."))
        XCTAssertTrue(result.description.contains("Ein Ladekabel ist dabei."))
        XCTAssertTrue(result.description.contains("Nur Abholung in Konstanz. Kein Versand."))
        XCTAssertFalse(result.description.contains("100"))
        XCTAssertFalse(result.description.contains("48"))
        XCTAssertFalse(result.description.contains("ABC123"))
        XCTAssertFalse(result.description.contains("messen?"))
    }
    func testVeryGoodChairRetainsEstablishedNotch() {
        let item = Item(title: "IKEA FJÄLLBERGET", kind: .chair, answers: ["condition": "likeNew", "chairRotation": "works", "chairHeight": "works", "defects": "none"], facts: ["Kleine Macke an der Rückseite"])
        let result = ListingComposer.applyAnswers(to: item, location: "Konstanz")
        XCTAssertTrue(result.description.contains("fast wie neu"))
        XCTAssertTrue(result.description.contains("Drehen und Höhenverstellung funktionieren einwandfrei"))
        XCTAssertTrue(result.description.contains("Kleine Macke an der Rückseite"))
        XCTAssertFalse(result.description.contains("mängelfrei"))
    }
    func testNewIsNotAutomaticallySealedOrFunctionTested() {
        var item = Item(title: "HUAWEI FreeBuds SE 4 ANC", kind: .headphones, answers: ["condition": "new", "packaging": "unknown"])
        var result = ListingComposer.applyAnswers(to: item, location: "")
        XCTAssertTrue(result.description.contains("Neu und unbenutzt"))
        XCTAssertFalse(result.description.contains("ungeöffnet"))
        XCTAssertFalse(result.description.contains("einwandfrei"))
        item.answers["packaging"] = "sealed"
        result = ListingComposer.applyAnswers(to: item, location: "")
        XCTAssertTrue(result.description.contains("ungeöffneter Originalverpackung"))
        XCTAssertFalse(result.description.contains("in ."))
    }
    func testPrivateResearchOCRAndFilenamesNeverBecomePublicCopy() {
        let item = Item(title: "IKEA FJÄLLBERGET", kind: .chair, answers: ["condition": "veryGood"], facts: [
            "Modellhinweis aus lokaler Texterkennung – bitte im Chat prüfen",
            "IMG_2919.HEIC", "Nutzerin bestätigt: sehr guter Zustand",
            "Kratzer laut Recherche eventuell vorhanden", "SN 987654",
            "Kleine Macke an der Rückseite", "Schwarzes Gehäuse", "Quelle: Kratzer im Bild IMG_2919.HEIC", "Keine Kratzer", "Möglicher Riss?"
        ])
        let result = ListingComposer.applyAnswers(to: item, location: "Konstanz")
        XCTAssertTrue(result.description.contains("Kleine Macke an der Rückseite."))
        for privateText in ["Modellhinweis", "Texterkennung", "IMG_", "Nutzerin", "Recherche", "987654", "Schwarzes Gehäuse", "Quelle:", "Keine Kratzer", "Möglicher Riss"] {
            XCTAssertFalse(result.description.contains(privateText), privateText)
        }
    }
    func testExplicitLaterClearsPreviousConditionAssessment() {
        let item = Item(title: "Artikel", condition: "Sehr gut", answers: ["condition": "later"])
        let result = ListingComposer.applyAnswers(to: item, location: "Konstanz")
        XCTAssertEqual(result.condition, "")
        XCTAssertFalse(result.description.contains("sehr gut"))
    }
    func testUnknownBatteryDoesNotBecomePublicClaimAndDeliveryIsRespected() {
        let item = Item(title: "Uhr", kind: .smartwatch, answers: ["battery": "notMeasured", "function": "later", "delivery": "shipping"])
        let result = ListingComposer.applyAnswers(to: item, location: "Konstanz")
        XCTAssertFalse(result.description.contains("Akku"))
        XCTAssertFalse(result.description.contains("funktioniert"))
        XCTAssertFalse(result.description.contains("Abholung"))
        XCTAssertTrue(result.description.contains("Nur Versand."))
    }
}
