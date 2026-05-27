import XCTest
@testable import PicSee

final class AppVersionTests: XCTestCase {
    func testComparesPatchVersionsNumerically() throws {
        let newer = try XCTUnwrap(AppVersion("0.2.12"))
        let current = try XCTUnwrap(AppVersion("0.2.11"))

        XCTAssertGreaterThan(newer, current)
    }

    func testComparesAcrossMinorVersions() throws {
        let newer = try XCTUnwrap(AppVersion("0.3.0"))
        let current = try XCTUnwrap(AppVersion("0.2.99"))

        XCTAssertGreaterThan(newer, current)
    }

    func testTreatsMissingComponentsAsZero() throws {
        let short = try XCTUnwrap(AppVersion("1.0"))
        let full = try XCTUnwrap(AppVersion("1.0.0"))

        XCTAssertEqual(short, full)
    }

    func testComparesMultiDigitComponentsNumerically() throws {
        let newer = try XCTUnwrap(AppVersion("0.10.0"))
        let current = try XCTUnwrap(AppVersion("0.9.9"))

        XCTAssertGreaterThan(newer, current)
    }

    func testNormalizesLeadingV() throws {
        let tagged = try XCTUnwrap(AppVersion("v0.2.11"))
        let plain = try XCTUnwrap(AppVersion("0.2.11"))

        XCTAssertEqual(tagged, plain)
    }

    func testRejectsInvalidVersions() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("0.2.beta"))
    }
}
