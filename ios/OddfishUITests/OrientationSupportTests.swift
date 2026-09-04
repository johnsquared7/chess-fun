import XCTest

/// The app declares only the orientations it has actually been built for.
///
/// iPad landscape was on from the start and never looked at; when it finally
/// was, the portrait layout simply stretched, so the declaration was narrowed
/// to match what existed. The wide layout it was waiting for — board beside a
/// control panel — now exists as `GameView.sidePanelLayout`, so iPad landscape
/// is declared again and `testTheSidePanelLayoutAppearsInLandscapeOnIPad`
/// holds it to that. iPhone stays portrait-only: `usesSidePanel` wants 900pt
/// of width, which no phone has, so rotating one would only stretch.
final class OrientationSupportTests: XCTestCase {
    func testTheGameIsFullyUsableInASupportedOrientation() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSkipIntroduction", "-oddfishUITestSilentGuide"]
        app.launch()
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 10))
        app.buttons["Play Classic"].tap()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 10))

        // Every corner of the board, and a playable square.
        for square in ["a1, white rook", "h1, white rook", "a8, black rook", "h8, black rook"] {
            XCTAssertTrue(app.buttons[square].exists, "Missing \(square)")
        }
        let pawn = app.buttons["e2, white pawn"]
        XCTAssertTrue(pawn.isHittable, "The board is not reachable")
        pawn.tap()
        XCTAssertTrue(app.buttons["e4, empty"].isHittable, "Legal destinations are not reachable")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "orientation-supported"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Rotating an iPad gives the board a control panel beside it, not a
    /// stretched phone layout — and the bottom bar goes away, because the two
    /// are alternatives rather than a bar plus a panel.
    func testTheSidePanelLayoutAppearsInLandscapeOnIPad() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "The wide layout needs 900pt of landscape width, which only an iPad has."
        )

        let app = XCUIApplication()
        app.launchArguments += ["-oddfishUITestReset", "-oddfishUITestSkipIntroduction", "-oddfishUITestSilentGuide"]
        app.launch()
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 10))
        app.buttons["Play Classic"].tap()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 10))

        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft

        let panel = app.descendants(matching: .any)["game-control-side-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Landscape did not produce the side panel")
        XCTAssertFalse(
            app.descendants(matching: .any)["game-control-drawer"].exists,
            "The bottom bar and the side panel are alternatives, never both"
        )

        // The board is still the thing you play on, not a picture beside a panel.
        let pawn = app.buttons["e2, white pawn"]
        XCTAssertTrue(pawn.waitForExistence(timeout: 5))
        XCTAssertTrue(pawn.isHittable, "The board is not reachable in landscape")
        pawn.tap()
        XCTAssertTrue(app.buttons["e4, empty"].isHittable, "Legal destinations are not reachable in landscape")

        // Side by side, and both on screen. Asserted on frames because this is
        // the failure the old stretched layout had — everything present, and
        // half of it off the edge or underneath something else.
        let boardColumn = app.descendants(matching: .any)["game-opponent-strip"].firstMatch.frame
        let panelFrame = panel.frame
        let screen = app.frame
        XCTAssertGreaterThan(boardColumn.width, 0, "The board column has no width")
        XCTAssertLessThanOrEqual(
            boardColumn.maxX, panelFrame.minX + 1,
            "The board column and the side panel overlap"
        )
        XCTAssertLessThanOrEqual(
            panelFrame.maxX, screen.maxX + 1,
            "The side panel runs off the right edge"
        )

        // The panel's own contents, rather than its frame: SwiftUI propagates
        // an accessibility identifier to child nodes, so the panel's id also
        // matches small things inside it and its measured frame is whichever
        // of those the query happens to return.
        XCTAssertTrue(
            app.staticTexts["GAME CONTROLS"].exists,
            "The side panel did not lay out its contents"
        )
        // Queried by label, the way the rest of this suite reaches these three.
        // The wide layout moves them from the bottom bar into the panel, and
        // they keep the same labels precisely so that stays true.
        for control in ["Pause", "Undo", "Redo"] {
            XCTAssertTrue(app.buttons[control].exists, "\(control) is missing from the side panel")
        }
        XCTAssertTrue(
            app.buttons["Pause"].isHittable,
            "The side panel's controls are not reachable in landscape"
        )

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "orientation-ipad-landscape"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
