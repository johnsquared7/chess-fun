import XCTest

/// Captures the screens the interface rebuild touches, so each pass can be
/// looked at rather than reasoned about. Not an assertion suite — it fails only
/// when a screen cannot be reached at all.
final class DesignEvidenceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-oddfishUITestReset",
            "-oddfishUITestSkipIntroduction",
            "-oddfishUITestSilentGuide"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    func testCaptureCoreScreens() throws {
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 10))
        capture("01-home")

        app.swipeUp()
        capture("02-home-catalogue")
        app.swipeDown()
        app.swipeDown()

        app.buttons["Play Classic"].tap()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 6))
        capture("03-game-fresh")

        // Selection state: dots, capture rings, highlighted source square.
        // Given a moment to settle, since the markers animate in.
        app.buttons["e2, white pawn"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        capture("04-game-selected")
        app.buttons["e4, empty"].tap()
        waitForBotTurn()
        capture("05-game-after-move")

        // A few more moves so the move tape and captured material have content.
        playIfPossible(from: "d2, white pawn", to: "d4, empty")
        playIfPossible(from: "g1, white knight", to: "f3, empty")
        capture("06-game-developed")

        app.buttons["Options"].tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 4))
        capture("07-game-options")
        app.swipeUp()
        capture("08-game-options-full")
        app.buttons["Done"].tap()

        // The end of a game, and the sequence that leads to it.
        app.buttons["Options"].tap()
        XCTAssertTrue(app.buttons["Resign"].waitForExistence(timeout: 4))
        app.buttons["Resign"].tap()
        XCTAssertTrue(app.buttons["Resign game"].waitForExistence(timeout: 3))
        capture("08b-resign-confirmation")
        app.buttons["Resign game"].tap()
        capture("09-result-immediately-after")
        XCTAssertTrue(app.buttons["Rematch"].waitForExistence(timeout: 6))
        capture("10-result-card")
    }

    func testCaptureSettingsAndHistory() throws {
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 10))
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        capture("12-settings")
        app.swipeUp()
        capture("13-settings-scrolled")
        app.buttons["Done"].tap()

        app.buttons["Game history"].tap()
        XCTAssertTrue(app.buttons["history-import-pgn"].waitForExistence(timeout: 5))
        capture("14-history-empty")
    }

    func testCaptureModeDetail() throws {
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 10))
        let restfish = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Restfish.")
        ).firstMatch
        XCTAssertTrue(restfish.waitForExistence(timeout: 5))
        restfish.tap()
        XCTAssertTrue(app.navigationBars["Restfish"].waitForExistence(timeout: 5))
        capture("11-mode-detail")
    }

    // MARK: - Helpers

    private func playIfPossible(from: String, to: String) {
        let source = app.buttons[from]
        guard source.waitForExistence(timeout: 3), source.isHittable else { return }
        source.tap()
        let target = app.buttons[to]
        guard target.waitForExistence(timeout: 2), target.isHittable else { return }
        target.tap()
        waitForBotTurn()
    }

    private func waitForBotTurn() {
        let thinking = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Thinking"))
            .firstMatch
        _ = thinking.waitForExistence(timeout: 3)
        let predicate = NSPredicate(format: "exists == false")
        expectation(for: predicate, evaluatedWith: thinking)
        waitForExpectations(timeout: 25)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
