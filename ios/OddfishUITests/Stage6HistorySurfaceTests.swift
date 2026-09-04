import XCTest

final class Stage6HistorySurfaceTests: XCTestCase {
    @MainActor
    private func launchWithCrownedHistory() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-oddfishUITestReset",
            "-oddfishUITestSkipIntroduction",
            "-oddfishUITestSilentGuide",
            "-oddfishUITestHistorySample"
        ]
        app.launch()
        return app
    }

    @MainActor
    func testPersonalBestSurfacesOnHomeAndHistoryOpensReplay() {
        let app = launchWithCrownedHistory()

        XCTAssertTrue(app.otherElements["home-best-classic"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["home-history"].waitForExistence(timeout: 2))
        app.buttons["home-history"].tap()

        XCTAssertTrue(app.buttons["history-import-pgn"].waitForExistence(timeout: 3))
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-record-'")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 3))
        record.tap()

        XCTAssertTrue(app.otherElements["history-review-board"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["history-review-controls"].waitForExistence(timeout: 3))
        app.swipeUp()
        XCTAssertTrue(app.buttons["history-ply-1"].waitForExistence(timeout: 3))
        app.buttons["history-ply-1"].tap()
        XCTAssertTrue(app.buttons["history-export-pgn"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testModeDetailExplainsItsCrownContract() {
        let app = launchWithCrownedHistory()
        let restfish = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Restfish.'")).firstMatch
        XCTAssertTrue(restfish.waitForExistence(timeout: 4))
        restfish.tap()

        XCTAssertTrue(app.otherElements["mode-crown-contract"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Crown run"].exists)
    }
}
