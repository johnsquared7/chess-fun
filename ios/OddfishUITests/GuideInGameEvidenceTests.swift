import XCTest

/// Gil during an actual game: the perch, and a bubble over a live board.
final class GuideInGameEvidenceTests: XCTestCase {
    func testGilAppearsDuringAGame() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSkipIntroduction"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let play = app.buttons["Play Classic"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 5))

        // He is on the perch for the whole game.
        XCTAssertTrue(app.buttons["Gil, your guide"].waitForExistence(timeout: 3))
        capture(app, "guide-01-perch")

        // A first move is one of his triggers.
        app.buttons["e2, white pawn"].tap()
        app.buttons["e4, empty"].tap()

        let bubble = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Gil says:"))
            .firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 6), "Gil never said anything")
        capture(app, "guide-02-bubble")

        // And the board must not have moved to make room for him.
        XCTAssertTrue(app.buttons["a1, white rook"].exists)
        XCTAssertTrue(app.buttons["h8, black rook"].exists)

        bubble.tap()
        XCTAssertFalse(bubble.waitForExistence(timeout: 1.5), "Tapping the bubble did not dismiss it")
        capture(app, "guide-03-dismissed")
    }

    /// The emotional core of the app: Stockfish wins, and Gil offers the
    /// variants as handicaps rather than letting the player conclude they are
    /// simply bad at chess.
    func testTheHingeOffersTheHandicaps() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSkipIntroduction"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let play = app.buttons["Play Classic"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.openGameOptions(), "The options sheet never opened")
        XCTAssertTrue(app.buttons["Resign"].waitForExistence(timeout: 3))
        app.buttons["Resign"].tap()
        app.buttons["Resign game"].tap()

        let tempofish = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Restfish.")
        ).firstMatch
        XCTAssertTrue(tempofish.waitForExistence(timeout: 8), "Gil never offered the handicaps")
        // The two-act structure: sympathy lands before the offer appears.
        capture(app, "hinge-01-offer")

        // Every pitch must state what changes for the opponent.
        for mode in ["RattleFish", "FumbleFish", "Restfish"] {
            let card = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "\(mode).")
            ).firstMatch
            XCTAssertTrue(card.exists, "Missing the \(mode) offer")
        }

        tempofish.tap()
        XCTAssertTrue(app.navigationBars["Restfish"].waitForExistence(timeout: 6),
                      "Choosing a handicap did not start that game")
        capture(app, "hinge-02-chosen")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
