import XCTest
@testable import WerkstattCore

final class DetectionHintsTests: XCTestCase {
    func testExplicitModelsBecomeConservativeHints() {
        let result = DetectionHints.from(text: "HUAWEI\nFreeBuds SE 4 ANC\nWHITE\nSerial 817382")
        XCTAssertEqual(result?.kind, .headphones)
        XCTAssertEqual(result?.title, "FreeBuds SE 4 ANC")
        XCTAssertEqual(result?.brand, "HUAWEI")
        XCTAssertEqual(result?.color, "") // A label's white text is not proof of the pictured variant.
        XCTAssertEqual(DetectionHints.from(text: "IKEA FJÄLLBERGET")?.title, "FJÄLLBERGET")
    }
    func testUnknownVariantsStayBlankAndManufacturerAloneMeansNothing() {
        let result = DetectionHints.from(text: "Galaxy Watch 7 44MM LTE SAMSUNG")
        XCTAssertEqual(result?.kind, .smartwatch)
        XCTAssertEqual(result?.title, "")
        XCTAssertNil(DetectionHints.from(text: "SAMSUNG 8173637"))
        XCTAssertNil(DetectionHints.from(text: "IKEA 204.852.42"))
    }
    func testNoSubstringModelGuess() {
        XCTAssertNil(DetectionHints.from(text: "NOTFREEBUDS SE4 ANCXYZ"))
    }
}
