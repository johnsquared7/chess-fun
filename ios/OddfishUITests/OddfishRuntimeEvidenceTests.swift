import XCTest

final class OddfishRuntimeEvidenceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSilentGuide", "-oddfishUITestSkipIntroduction"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func testClassicTapMoveAndNavigationEvidence() throws {
        capture("01-home")
        openClassicFromHome()
        capture("04-classic-board")

        tapSquare("e2, white pawn")
        XCTAssertTrue(app.buttons["e4, empty"].waitForExistence(timeout: 2))
        capture("05-legal-indicators")
        tapSquare("e4, empty")
        XCTAssertTrue(app.buttons["e4, white pawn"].waitForExistence(timeout: 2))
        capture("06-player-move")
        waitForBotTurnToFinish()
        capture("07-bot-reply")

        tapButton("Exit")
        XCTAssertTrue(app.buttons["Leave game"].waitForExistence(timeout: 2))
        capture("08-exit-confirmation")
        tapButton("Leave game")
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 3))
    }

    /// The app must actually be playing the bundled engine, not quietly falling
    /// back to the built-in search. The status line names whoever is thinking.
    func testOpponentIsTheBundledEngine() throws {
        openClassicFromHome()
        // The opponent strip names the opponent for the whole game, so this
        // does not race the transient thinking indicator.
        let named = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "Stockfish"))
            .firstMatch
        XCTAssertTrue(
            named.waitForExistence(timeout: 10),
            "The opponent is not Stockfish — the engine failed to boot and the app fell back"
        )
        capture("21-stockfish-opponent")
    }

    func testModeDetailEvidence() throws {
        for (index, mode, rule) in [
            ("03b", "Restfish", "A moved piece rests for your next two turns."),
            ("03c", "RattleFish", "It loses 100 Elo whenever you find a best move."),
            ("03d", "FumbleFish", "It plays at full strength, with a 5% chance of the worst move.")
        ] {
            openMode(named: mode, rule: rule)
            XCTAssertTrue(app.staticTexts["See it on the board"].waitForExistence(timeout: 2))
            capture("\(index)-\(mode.lowercased())-instructions")
            app.navigationBars[mode].buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 3))
        }
    }

    func testDragInvalidRestartAndResultEvidence() throws {
        openClassicFromHome()

        let source = app.buttons["g1, white knight"]
        let destination = app.buttons["f3, empty"]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        XCTAssertTrue(destination.exists)
        source.press(forDuration: 0.12, thenDragTo: destination)
        let dragSucceeded = app.buttons["f3, white knight"].waitForExistence(timeout: 2)
        capture(dragSucceeded ? "09-valid-drag" : "09-drag-failed")
        if !dragSucceeded {
            // Preserve the failed drag as evidence, then use the independent tap
            // path so this evidence run can still reach restart and game-over UI.
            tapSquare("g1, white knight")
            tapSquare("f3, empty")
            XCTAssertTrue(app.buttons["f3, white knight"].waitForExistence(timeout: 2))
        }
        waitForBotTurnToFinish()

        tapSquare("f3, white knight")
        tapSquare("f4, empty")
        XCTAssertTrue(app.buttons["f3, white knight"].exists)
        capture("10-invalid-move-settled")

        expandGameControls()
        tapButton("Restart")
        XCTAssertTrue(app.buttons["Restart game"].waitForExistence(timeout: 2))
        capture("11-restart-confirmation")
        tapButton("Restart game")
        XCTAssertTrue(app.buttons["g1, white knight"].waitForExistence(timeout: 3))

        // Confirming a restart closes the options sheet, so resigning needs it
        // opened again rather than assuming it stayed up.
        expandGameControls()
        tapButton("Resign")
        XCTAssertTrue(app.buttons["Resign game"].waitForExistence(timeout: 2))
        tapButton("Resign game")
        XCTAssertTrue(app.staticTexts["You resigned"].waitForExistence(timeout: 3))
        capture("12-game-over")
        tapButton("Rematch")
        XCTAssertTrue(app.buttons["e2, white pawn"].waitForExistence(timeout: 3))
        capture("13-rematch")
    }

    func testRestfishEvidence() throws {
        openGameFromHome(mode: "Restfish", rule: "A moved piece rests for your next two turns.")
        tapSquare("g1, white knight")
        tapSquare("f3, empty")
        XCTAssertTrue(app.buttons["f3, white knight, resting for 2 more turns"].waitForExistence(timeout: 2))
        waitForBotTurnToFinish()
        capture("14-restfish-rest")
    }

    func testSettingsAndHistoryEvidence() throws {
        // The current home intentionally exposes more than one Settings entry.
        // Choose one deterministically while retaining that duplicate tree state
        // for the accessibility critic to evaluate independently.
        let settings = app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        capture("19-settings")
        tapButton("Done")

        app.swipeUp()
        tapButton("Game history")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 3))
        capture("20-history")
    }

    /// Classic is the home screen's one-tap action; it has no rule card.
    private func openClassicFromHome() {
        tapButton("Play Classic")
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 3))
    }

    private func openGameFromHome(mode: String, rule: String) {
        openMode(named: mode, rule: rule)
        tapButton("Start \(mode)")
        XCTAssertTrue(app.navigationBars[mode].waitForExistence(timeout: 3))
    }

    private func openMode(named mode: String, rule: String) {
        let card = app.buttons["\(mode). \(rule)"]
        if !card.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(card.waitForExistence(timeout: 3), "Missing mode card for \(mode)")
        card.tap()
        XCTAssertTrue(app.navigationBars[mode].waitForExistence(timeout: 3))
    }

    private func tapSquare(_ label: String) {
        let square = app.buttons[label]
        XCTAssertTrue(square.waitForExistence(timeout: 3), "Missing square: \(label)")
        square.tap()
    }

    private func tapButton(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Missing button: \(label)")
        button.tap()
    }

    private func waitForBotTurnToFinish() {
        // The opponent strip says so on its own line while a search is running.
        let thinking = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Thinking")
        ).firstMatch
        _ = thinking.waitForExistence(timeout: 2)
        let deadline = Date().addingTimeInterval(12)
        while thinking.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertFalse(thinking.exists, "Bot turn did not settle")
    }

    private func expandGameControls() {
        XCTAssertTrue(app.openGameOptions(), "The options sheet never opened")
        XCTAssertTrue(app.buttons["Restart"].waitForExistence(timeout: 3))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
