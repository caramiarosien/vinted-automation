import XCTest
@testable import WerkstattCore

final class QuestionnaireTests: XCTestCase {
    private func watch() -> (Item, [Photo]) {
        let item = Item(id: "watch", title: "Samsung Galaxy Watch6 Classic", description: "Verkaufe meine Uhr.", kind: .smartwatch, condition: "Gut", price: 100, coverPhotoID: "photo", photoOrder: ["photo", "label"], answers: ["condition": "good", "defects": "normalWear", "function": "works", "battery": "good", "charger": "included", "packaging": "unknown", "delivery": "pickup"])
        return (item, [Photo(id: "photo", itemID: "watch"), Photo(id: "label", itemID: "watch", isSelected: false)])
    }
    func testQualitativeBatteryAndExcludedLabelDoNotBlockReady() {
        var (item, photos) = watch()
        XCTAssertEqual(Questionnaire.blockers(item: item, photos: photos), [])
        item.answers["battery"] = "notMeasured"
        XCTAssertEqual(Questionnaire.blockers(item: item, photos: photos), [])
        XCTAssertEqual(Questionnaire.questions(for: item), [])
    }
    func testUnverifiedFunctionAndIssuesNeedSpecificFollowup() {
        var (item, photos) = watch()
        item.answers["function"] = "later"
        XCTAssertTrue(Questionnaire.blockers(item: item, photos: photos).contains(where: { $0.contains("Funktioniert") }))
        item.answers["function"] = "issues"
        XCTAssertEqual(Questionnaire.questions(for: item).map(\.id), ["functionIssue"])
        item.answers["functionIssue"] = "other"
        XCTAssertFalse(Questionnaire.blockers(item: item, photos: photos).isEmpty)
        item.answers["functionIssue"] = "notWorking"
        XCTAssertEqual(Questionnaire.blockers(item: item, photos: photos), [])
    }
    func testNewHeadphonesNeverRequireOpeningForFunctionTest() {
        var item = Item(kind: .headphones, answers: ["condition": "new"])
        XCTAssertFalse(Questionnaire.allQuestions(for: item).contains(where: { $0.id == "function" }))
        XCTAssertTrue(Questionnaire.allQuestions(for: item).contains(where: { $0.id == "packaging" }))
        item.answers["condition"] = "veryGood"
        XCTAssertTrue(Questionnaire.allQuestions(for: item).contains(where: { $0.id == "function" }))
    }
    func testContradictoryAndUnknownChoicesAreRejected() {
        var (item, photos) = watch()
        item.answers["defects"] = "none,scratches"
        XCTAssertTrue(Questionnaire.blockers(item: item, photos: photos).contains(where: { $0.contains("kombinieren") }))
        item.answers["defects"] = "none"
        item.answers["battery"] = "health100"
        XCTAssertTrue(Questionnaire.blockers(item: item, photos: photos).contains(where: { $0.contains("Ungültige Antwort") }))
    }
    func testExternalQuestionsRemainPrivateReviewBlockers() {
        var (item, photos) = watch()
        item.questions = ["Ist die Glasgröße wirklich 43 mm?"]
        XCTAssertEqual(Questionnaire.questions(for: item).map(\.id), ["review-0"])
        XCTAssertFalse(Questionnaire.blockers(item: item, photos: photos).isEmpty)
        item.answers["review-0"] = "reviewed"
        XCTAssertTrue(Questionnaire.blockers(item: item, photos: photos).isEmpty)
    }
}
