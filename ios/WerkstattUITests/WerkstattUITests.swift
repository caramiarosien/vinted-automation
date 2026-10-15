import XCTest

/// Simulator-only fixtures live in a separate directory and contain synthetic images.
final class WerkstattUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["WERKSTATT_UI_TEST_ID"] = UUID().uuidString
    }

    private func openFixture(_ kind: String, startQuestions: Bool = true) {
        app.launchEnvironment["WERKSTATT_UI_TEST_KIND"] = kind
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Werkstatt"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Werkstatt"].tap()
        let article = app.staticTexts["Simulator-Testartikel"].firstMatch
        XCTAssertTrue(article.waitForExistence(timeout: 10))
        article.tap()
        if startQuestions { tap("item.questions") }
    }

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
        // Start at the top; cards and the review can extend beyond a small iPhone.
        for _ in 0..<4 where !button.isHittable { app.scrollViews.firstMatch.swipeDown() }
        for _ in 0..<8 where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable, identifier)
        button.tap()
    }

    private func answer(_ identifier: String) {
        tap("choice." + identifier)
        tap("question.next")
    }

    private func description(containing text: String) -> XCUIElement {
        let element = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.exists, text)
        return element
    }

    func testWatchUsesQualitativeBatteryAndPersistsAnswersAfterRelaunch() {
        openFixture("smartwatch")
        for choice in ["good", "normalWear", "works", "good", "included", "opened", "pickup"] { answer(choice) }
        tap("question.finish")
        let copy = description(containing: "Der Akku ist nach meiner Einschätzung")
        XCTAssertFalse(copy.label.contains("%"))
        XCTAssertFalse(copy.label.contains("Stunden"))
        XCTAssertTrue(copy.label.contains("Kein Versand"))
        XCTAssertTrue(copy.label.contains("Originalverpackung"))
        app.terminate()
        app.launch()
        app.tabBars.buttons["Werkstatt"].tap()
        app.staticTexts["Simulator-Testartikel"].firstMatch.tap()
        tap("item.questions")
        XCTAssertTrue(app.buttons["question.finish"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["question.next"].exists)
    }

    func testNewHeadphonesAskPackagingWithoutRequiringFunctionTest() {
        openFixture("headphones")
        answer("new")
        answer("opened")
        answer("pickup")
        tap("question.finish")
        let copy = description(containing: "Originalverpackung")
        XCTAssertFalse(copy.label.lowercased().contains("versiegelt"))
        XCTAssertFalse(copy.label.lowercased().contains("einwandfrei"))
    }

    func testChairQuestionsDoNotAskForBattery() {
        openFixture("chair")
        for choice in ["veryGood", "none", "works", "works", "pickup"] { answer(choice) }
        tap("question.finish")
        let copy = description(containing: "Höhenverstellung")
        XCTAssertFalse(copy.label.lowercased().contains("akku"))
    }

    func testCompactDetailKeepsReadyAtTopAndPricingCollapsedWithPlatformPreview() {
        openFixture("smartwatch", startQuestions: false)
        XCTAssertTrue(app.buttons["item.preview"].isHittable)
        XCTAssertTrue(app.buttons["item.ready"].isHittable)
        XCTAssertFalse(app.buttons["item.ready"].isEnabled)
        XCTAssertTrue(app.staticTexts["Preisbegründung-Test"].waitForNonExistence(timeout: 3))
        tap("item.pricing")
        XCTAssertTrue(app.staticTexts["Preisbegründung-Test"].exists)
        tap("item.pricing")
        XCTAssertTrue(app.staticTexts["Preisbegründung-Test"].waitForNonExistence(timeout: 3))
        tap("item.preview")
        let picker = app.segmentedControls["preview.platform"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["Vinted"].tap()
        XCTAssertTrue(picker.buttons["Vinted"].isSelected)
        picker.buttons["Kleinanzeigen"].tap()
        XCTAssertTrue(picker.buttons["Kleinanzeigen"].isSelected)
        XCTAssertTrue(app.staticTexts["Beispielansicht"].exists)
    }

    func testConfirmedPublicationSurvivesRestartWithoutAnsweringDraftQuestions() {
        openFixture("chair", startQuestions: false)
        tap("item.publications")
        tap("publication.kleinanzeigen")
        XCTAssertTrue(app.buttons["publication.kleinanzeigen"].isSelected)
        tap("publication.save")
        XCTAssertTrue(app.staticTexts["Eingestellt"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.tabBars.buttons["Werkstatt"].tap()
        XCTAssertTrue(app.staticTexts["Eingestellt"].waitForExistence(timeout: 5))
        app.staticTexts["Simulator-Testartikel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["item.questions"].exists)
        XCTAssertTrue(app.buttons["item.ready"].exists)
        XCTAssertFalse(app.buttons["item.ready"].isEnabled)
    }
}
