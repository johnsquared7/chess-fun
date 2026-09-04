import XCTest

/// Stage 8: the game survives being interrupted, and the licence offer is
/// reachable by anyone holding a copy of the app.
final class Stage8ShipReadinessTests: XCTestCase {
    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestSkipIntroduction", "-oddfishUITestSilentGuide"]
        if reset { app.launchArguments += ["-oddfishUITestReset"] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    func testAnInterruptedGameIsWaitingOnRelaunch() throws {
        let first = launch(reset: true)
        XCTAssertTrue(first.buttons["Play Classic"].waitForExistence(timeout: 10))
        first.buttons["Play Classic"].tap()
        XCTAssertTrue(first.navigationBars["Classic"].waitForExistence(timeout: 8))

        first.buttons["e2, white pawn"].tap()
        first.buttons["e4, empty"].tap()
        XCTAssertTrue(first.buttons["e4, white pawn"].waitForExistence(timeout: 5))
        capture(first, "stage8-01-game-in-progress")

        // The phone call.
        first.terminate()

        // Same install, second launch. The board should be where it was left,
        // not a fresh game and not the home screen.
        let second = launch(reset: false)
        XCTAssertTrue(
            second.navigationBars["Classic"].waitForExistence(timeout: 10),
            "Relaunch did not return to the interrupted game"
        )
        XCTAssertTrue(
            second.buttons["e4, white pawn"].waitForExistence(timeout: 8),
            "The board came back but the moves did not"
        )
        XCTAssertFalse(second.buttons["e2, white pawn"].exists, "The board was reset instead of restored")
        capture(second, "stage8-02-restored")
    }

    func testAnExplicitlyLeftGameStaysLeftOnRelaunch() throws {
        let first = launch(reset: true)
        XCTAssertTrue(first.buttons["Play Classic"].waitForExistence(timeout: 10))
        first.buttons["Play Classic"].tap()
        XCTAssertTrue(first.navigationBars["Classic"].waitForExistence(timeout: 8))

        first.buttons["e2, white pawn"].tap()
        first.buttons["e4, empty"].tap()
        XCTAssertTrue(first.buttons["e4, white pawn"].waitForExistence(timeout: 5))

        let exit = first.buttons["Exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 3))
        exit.tap()
        let leave = first.buttons["Leave game"]
        XCTAssertTrue(leave.waitForExistence(timeout: 3))
        leave.tap()
        XCTAssertTrue(
            first.buttons["Play Classic"].waitForExistence(timeout: 8),
            "Explicitly leaving did not return to Home"
        )

        first.terminate()

        let second = launch(reset: false)
        XCTAssertTrue(
            second.buttons["Play Classic"].waitForExistence(timeout: 10),
            "A deliberately abandoned game was incorrectly restored"
        )
        XCTAssertFalse(second.navigationBars["Classic"].exists)
    }

    func testAFinishedGameIsNotOfferedBack() throws {
        let first = launch(reset: true)
        XCTAssertTrue(first.buttons["Play Classic"].waitForExistence(timeout: 10))
        first.buttons["Play Classic"].tap()
        XCTAssertTrue(first.navigationBars["Classic"].waitForExistence(timeout: 8))

        first.buttons["e2, white pawn"].tap()
        first.buttons["e4, empty"].tap()
        XCTAssertTrue(first.buttons["e4, white pawn"].waitForExistence(timeout: 5))

        expandGameControls(in: first)
        first.buttons["Resign"].tap()
        first.buttons["Resign game"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        first.terminate()

        let second = launch(reset: false)
        XCTAssertTrue(
            second.buttons["Play Classic"].waitForExistence(timeout: 10),
            "A resigned game should not be waiting on the next launch"
        )
    }

    func testTheLicenceAndSourceOfferAreReachable() throws {
        let app = launch(reset: true)
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 10))

        let settings = app.buttons.matching(NSPredicate(format: "label == %@", "Settings")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let licence = app.descendants(matching: .any)["settings-licence"]
        for _ in 0..<8 where !licence.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(licence.waitForExistence(timeout: 5), "GPLv3 requires the offer reach whoever has the binary")
        licence.tap()
        XCTAssertTrue(app.navigationBars["Licence"].waitForExistence(timeout: 5))

        let sourceLink = app.descendants(matching: .any)["licence-source-link"]
        let missingSource = app.descendants(matching: .any)["licence-source-missing"]
        XCTAssertTrue(
            sourceLink.waitForExistence(timeout: 3),
            "Ship-readiness requires a link to this build's complete corresponding source"
        )
        XCTAssertFalse(
            missingSource.exists,
            "The licence screen still reports that corresponding source is not configured"
        )
        capture(app, "stage8-03-licence")
    }

    private func expandGameControls(in app: XCUIApplication) {
        XCTAssertTrue(app.openGameOptions(), "The options sheet never opened")
        XCTAssertTrue(app.buttons["Resign"].waitForExistence(timeout: 3))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
