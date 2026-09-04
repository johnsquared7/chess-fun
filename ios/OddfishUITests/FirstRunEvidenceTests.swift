import XCTest

/// The introduction, end to end: a fresh install goes straight into a game
/// against the boss, and leaving it in any way ends the introduction rather
/// than looping the player back into it.
final class FirstRunEvidenceTests: XCTestCase {
    private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if reset { app.launchArguments += ["-oddfishUITestReset"] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }

    /// The introduction is a persistent moment now, so it has to be answered
    /// before the board underneath it can be touched.
    @discardableResult
    private func dismissIntroduction(_ app: XCUIApplication) -> Bool {
        let dismiss = app.buttons["guide-moment-decline"]
        guard dismiss.waitForExistence(timeout: 10) else { return false }
        dismiss.tap()
        return true
    }

    func testAFreshInstallLandsInAGameNotOnTheHomeScreen() throws {
        let app = launch()

        XCTAssertTrue(
            app.navigationBars["Classic"].waitForExistence(timeout: 8),
            "A first launch should open a game, not a menu"
        )
        XCTAssertFalse(app.buttons["Play Classic"].exists, "The home screen should have been skipped")

        // The boss is named, and Gil introduces it.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "Stockfish"))
                .firstMatch.waitForExistence(timeout: 6)
        )
        // Gil introduces the boss in a moment that waits for the player, not a
        // bubble on a timer that a slow cold launch can outlast.
        // Target the semantic moment, not a sentence Gil is free to rewrite.
        // The old copy assertion stayed red after the product copy changed even
        // though the introduction itself was working correctly.
        let introduction = app.descendants(matching: .any)["guide-moment"]
        XCTAssertTrue(introduction.waitForExistence(timeout: 10), "Gil never introduced the boss")
        capture(app, "firstrun-01-straight-into-the-game")

        XCTAssertTrue(dismissIntroduction(app), "The introduction had no way out")
        XCTAssertFalse(
            introduction.waitForExistence(timeout: 2),
            "The introduction stayed up after being answered"
        )
    }

    func testFinishingTheIntroductionLeadsToTheHandicapsAndThenHome() throws {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 8))
        dismissIntroduction(app)

        expandGameControls(in: app)
        app.buttons["Resign"].tap()
        app.buttons["Resign game"].tap()

        let tempofish = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Restfish.")
        ).firstMatch
        XCTAssertTrue(tempofish.waitForExistence(timeout: 8), "The introduction did not lead to the offer")
        capture(app, "firstrun-02-hinge")

        tempofish.tap()
        XCTAssertTrue(app.navigationBars["Restfish"].waitForExistence(timeout: 8))
        capture(app, "firstrun-03-handicapped-game")
    }

    func testTheIntroductionIsNotShownTwice() throws {
        let first = launch()
        XCTAssertTrue(first.navigationBars["Classic"].waitForExistence(timeout: 8))
        dismissIntroduction(first)
        expandGameControls(in: first)
        first.buttons["Resign"].tap()
        first.buttons["Resign game"].tap()
        XCTAssertTrue(
            first.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Restfish."))
                .firstMatch.waitForExistence(timeout: 8)
        )
        first.terminate()

        // Relaunching WITHOUT a reset: the same install, second launch.
        let second = launch(reset: false)
        XCTAssertTrue(
            second.buttons["Play Classic"].waitForExistence(timeout: 8),
            "A returning player should land on the home screen"
        )
        capture(second, "firstrun-04-returning-player")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func expandGameControls(in app: XCUIApplication) {
        XCTAssertTrue(app.openGameOptions(), "The options sheet never opened")
        XCTAssertTrue(app.buttons["Resign"].waitForExistence(timeout: 3))
    }
}
