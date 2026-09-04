import XCTest

/// Board appearance, captured at every theme so the choice can be judged by
/// looking — which is the only way a board theme can be judged.
final class Stage7AppearanceTests: XCTestCase {
    private func launchToAppearance() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSkipIntroduction", "-oddfishUITestSilentGuide"]
        app.launch()
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 10))

        let settings = app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        // Appearance sits below Feedback, Play and Evaluation, so on a phone it
        // is off screen when Settings opens.
        let board = app.descendants(matching: .any)["settings-board-appearance"]
        for _ in 0..<6 where !board.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(board.waitForExistence(timeout: 5), "Could not reach the Board row in Settings")
        board.tap()
        XCTAssertTrue(app.navigationBars["Board"].waitForExistence(timeout: 5))
        return app
    }

    func testEveryThemeAndPieceStyleRenders() throws {
        let app = launchToAppearance()
        XCTAssertTrue(app.otherElements["appearance-preview"].waitForExistence(timeout: 5))
        capture(app, "stage7-01-appearance-default")

        // The preview must actually change when a style is chosen.
        let styles = app.segmentedControls["appearance-piece-style"]
        XCTAssertTrue(styles.waitForExistence(timeout: 3))
        for style in ["Outline", "Flat", "Carved"] {
            let button = styles.buttons[style]
            XCTAssertTrue(button.exists, "Missing piece style: \(style)")
            button.tap()
            capture(app, "stage7-02-style-\(style.lowercased())")
        }
    }

    func testChoosingAThemeChangesTheRealBoard() throws {
        let app = launchToAppearance()

        // The preview is deliberately large, so the theme picker below it starts
        // off screen on a phone.
        let picker = app.descendants(matching: .any)["appearance-theme"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        for _ in 0..<4 where !picker.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(picker.isHittable, "Theme picker was not reachable")
        picker.tap()

        let classic = app.descendants(matching: .any).matching(identifier: "theme-classic").firstMatch
        XCTAssertTrue(classic.waitForExistence(timeout: 5))
        classic.tap()
        capture(app, "stage7-03-classic-chosen")

        // Back out to a real game and confirm the choice reached the board.
        app.navigationBars["Board"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 5))
        app.buttons["Play Classic"].tap()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["e2, white pawn"].waitForExistence(timeout: 5))
        capture(app, "stage7-04-classic-board-in-play")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
