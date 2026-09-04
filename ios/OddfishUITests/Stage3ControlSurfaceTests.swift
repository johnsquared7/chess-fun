import XCTest

final class Stage3ControlSurfaceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSilentGuide", "-oddfishUITestSkipIntroduction"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func testCompactBarUndoRedoAndBlackSideEvidence() throws {
        app.buttons["Play Classic"].tap()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 4))

        // The live controls are on the bar itself now. Only the settings, the
        // crown contract and the destructive actions are behind Options, which
        // is what "peek should expose status, not the full control set" was
        // always trying to say.
        let bar = app.otherElements["game-control-drawer"]
        XCTAssertTrue(bar.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Options"].exists)
        XCTAssertTrue(app.buttons["Undo"].exists)
        XCTAssertTrue(app.buttons["Redo"].exists)
        XCTAssertTrue(app.buttons["Pause"].exists)
        XCTAssertFalse(app.buttons["Restart"].exists, "The bar must not carry destructive actions")
        // The opponent's rating is on the board's own chrome rather than in a
        // drawer the player has to open.
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "rated"))
                .firstMatch.exists
        )
        capture("stage3-phone-bar")

        app.buttons["e2, white pawn"].tap()
        app.buttons["e4, empty"].tap()
        waitForBotTurnToFinish()

        app.buttons["Undo"].tap()
        XCTAssertTrue(app.buttons["e2, white pawn"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Redo"].isEnabled)
        app.buttons["Redo"].tap()
        XCTAssertTrue(app.buttons["e4, white pawn"].waitForExistence(timeout: 3))

        XCTAssertTrue(app.openGameOptions(), "The options sheet never opened")
        XCTAssertTrue(app.buttons["Restart"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Resign"].isHittable)
        XCTAssertTrue(app.buttons["Play as Black"].exists)
        capture("stage3-phone-options")

        app.buttons["Play as Black"].tap()
        XCTAssertTrue(app.staticTexts["Switch sides and restart?"].waitForExistence(timeout: 3))
        let restartAsBlack = app.buttons["Restart as Black"]
        XCTAssertTrue(restartAsBlack.waitForExistence(timeout: 2))
        restartAsBlack.tap()

        let blackStatus = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Your move · Black"))
            .firstMatch
        XCTAssertTrue(blackStatus.waitForExistence(timeout: 20), "The opponent never made White's opening move")
        XCTAssertTrue(app.buttons["a7, black pawn"].exists)
        capture("stage3-phone-black")
    }

    func testLandscapeUsesTheWideControlSurfaceWhenSpaceExists() throws {
        app.buttons["Play Classic"].tap()
        XCTAssertTrue(app.otherElements["game-control-drawer"].waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft

        if app.windows.firstMatch.frame.width >= 900 {
            XCTAssertTrue(app.otherElements["game-control-side-panel"].waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["Undo"].exists)
            XCTAssertTrue(app.buttons["Restart"].exists)
            XCTAssertTrue(app.buttons["Resign"].exists)
            XCTAssertTrue(app.buttons["Play as Black"].exists)
        } else {
            XCTAssertTrue(app.otherElements["game-control-drawer"].waitForExistence(timeout: 8))
        }
        capture("stage3-landscape-control-surface")
    }

    private func waitForBotTurnToFinish() {
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

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
