import XCTest

final class Stage5CatalogueSurfaceTests: XCTestCase {
    func testGroupedCatalogueOpensANewLiveRatingMode() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSilentGuide", "-oddfishUITestSkipIntroduction"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Bruise its ego"].waitForExistence(timeout: 8))

        // Restfish moved beside the other modes that constrain legal choices.
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Restfish.")).firstMatch.exists
        )

        // The catalogue is a scrolling list of category rows rather than a set
        // of accordions, so a mode is reached by scrolling to it, not by
        // opening the group that hides it.
        XCTAssertTrue(app.staticTexts["Bruise its ego"].waitForExistence(timeout: 3))

        let tilt = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "RattleFish.")
        ).firstMatch
        for _ in 0..<8 where !(tilt.exists && tilt.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(tilt.waitForExistence(timeout: 3))
        XCTAssertTrue(tilt.isHittable, "RattleFish was never reachable in the catalogue")
        tilt.tap()
        XCTAssertTrue(app.navigationBars["RattleFish"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["It loses 100 Elo whenever you find a best move."].exists)

        app.buttons["Start RattleFish"].tap()
        XCTAssertTrue(app.navigationBars["RattleFish"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["3,600"].waitForExistence(timeout: 3))
    }
}
