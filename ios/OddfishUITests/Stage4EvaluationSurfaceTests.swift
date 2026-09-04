import XCTest

final class Stage4EvaluationSurfaceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "-oddfishUITestReset",
            "-oddfishUITestSilentGuide",
            "-oddfishUITestSkipIntroduction",
            "-oddfishUITestEvaluation",
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    func testEvaluationControlsRanksTideAndGilReviewEvidence() throws {
        app.buttons["Play Classic"].tap()
        XCTAssertTrue(app.navigationBars["Classic"].waitForExistence(timeout: 4))

        let firstRank = app.descendants(matching: .any)["game-move-rank-1"]
        XCTAssertTrue(firstRank.waitForExistence(timeout: 20))
        capture("stage4-ranked-board")

        XCTAssertTrue(app.openGameOptions(), "The options sheet never opened")

        let evaluation = app.switches["game-evaluation-toggle"]
        XCTAssertTrue(evaluation.waitForExistence(timeout: 3))
        XCTAssertEqual(evaluation.value as? String, "1")
        evaluation.tap()
        XCTAssertFalse(app.otherElements["game-evaluation-tide"].exists)
        evaluation.tap()
        XCTAssertTrue(app.otherElements["game-evaluation-tide"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.steppers["game-analysis-depth"].exists)
        XCTAssertTrue(app.buttons["game-analysis-time"].exists)
        XCTAssertTrue(app.switches["game-evaluation-bar-toggle"].exists)
        XCTAssertTrue(app.switches["game-move-ranks-toggle"].exists)
        XCTAssertTrue(app.switches["game-move-review-toggle"].exists)
        XCTAssertTrue(app.switches["game-ponder-toggle"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "CPU and battery")).firstMatch.exists
        )
        capture("stage4-analysis-controls")

        // Back to the board, which is what the rest of the evidence needs.
        app.closeGameOptions()
        XCTAssertTrue(firstRank.waitForExistence(timeout: 8))

        app.buttons["f2, white pawn"].tap()
        app.buttons["f3, empty"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["game-gil-square"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.openGameOptions())
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any)["game-move-review"].waitForExistence(timeout: 4)
        )
        capture("stage4-gil-move-review")
    }

    func testWidePanelKeepsEvaluationBesideTheBoard() throws {
        app.buttons["Play Classic"].tap()
        XCTAssertTrue(app.buttons["a2, white pawn"].waitForExistence(timeout: 8))
        XCUIDevice.shared.orientation = .landscapeLeft

        guard app.windows.firstMatch.frame.width >= 900 else {
            throw XCTSkip("The wide Stage 4 surface requires an iPad-sized window")
        }
        XCTAssertTrue(app.otherElements["game-control-side-panel"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.switches["game-evaluation-toggle"].exists)
        XCTAssertTrue(app.otherElements["game-evaluation-tide"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["game-move-rank-1"].waitForExistence(timeout: 20)
        )
        capture("stage4-ipad-evaluation-panel")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
