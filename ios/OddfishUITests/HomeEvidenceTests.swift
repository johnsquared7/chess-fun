import XCTest

/// The home screen and the mode explainer, which were both rebuilt in this
/// phase. Captured at the default text size and at an accessibility size, since
/// the layout they replaced could not survive the latter.
final class HomeEvidenceTests: XCTestCase {
    func testHomeAndModeExplainer() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSkipIntroduction"]
        app.launch()
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 8))
        capture(app, "home-01-default")

        let tempofish = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Restfish.")
        ).firstMatch
        XCTAssertTrue(tempofish.exists)
        tempofish.tap()
        XCTAssertTrue(app.navigationBars["Restfish"].waitForExistence(timeout: 5))
        capture(app, "home-02-mode-explainer")
    }

    func testHomeSurvivesAccessibilityTextSizes() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-oddfishUITestReset", "-oddfishUITestSkipIntroduction",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ]
        app.launch()

        // Every control must still be reachable, not clipped off a fixed-height
        // container the way the previous layout's 476pt rail did.
        let play = app.buttons["Play Classic"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        capture(app, "home-03-accessibility-text")

        // The catalogue is spread across five playful families, so at an
        // accessibility text size the utility row is several swipes down. Scroll
        // until it is reachable rather than assuming one swipe covers it.
        let history = app.buttons["Game history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        for _ in 0..<8 where !history.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(history.isHittable, "History was not reachable at accessibility text size")
        capture(app, "home-04-accessibility-scrolled")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
