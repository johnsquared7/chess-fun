import XCTest

final class PurchaseFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPremiumModeOpensPaywallWhileFreeModeStillOpensDetail() {
        let app = launchApp()
        let premiumMode = app.buttons["home-mode-flinchfish"]
        XCTAssertTrue(premiumMode.waitForExistence(timeout: 8))
        XCTAssertTrue(premiumMode.label.contains("Locked"))

        premiumMode.tap()
        XCTAssertTrue(app.navigationBars["Full Oddfish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["One purchase"].exists)
        XCTAssertTrue(app.buttons["full-unlock-restore"].exists)

        app.buttons["full-unlock-close"].tap()
        let freeMode = app.buttons["home-mode-rattlefish"]
        XCTAssertTrue(freeMode.waitForExistence(timeout: 5))
        XCTAssertFalse(freeMode.label.contains("Locked"))
        freeMode.tap()
        XCTAssertTrue(app.navigationBars["RattleFish"].waitForExistence(timeout: 5))
    }

    func testDebugEntitlementLetsPremiumModeOpenNormally() {
        let app = launchApp(additionalArguments: ["-oddfishUITestFullUnlock"])
        let premiumMode = app.buttons["home-mode-flinchfish"]
        XCTAssertTrue(premiumMode.waitForExistence(timeout: 8))

        let unlocked = NSPredicate(format: "NOT label CONTAINS %@", "Locked")
        expectation(for: unlocked, evaluatedWith: premiumMode)
        waitForExpectations(timeout: 5)

        premiumMode.tap()
        XCTAssertTrue(app.navigationBars["FlinchFish"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Full Oddfish"].exists)
    }

    private func launchApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-oddfishUITestReset",
            "-oddfishUITestSkipIntroduction",
            "-oddfishUITestSilentGuide"
        ] + additionalArguments
        app.launch()
        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 8))
        return app
    }

}
