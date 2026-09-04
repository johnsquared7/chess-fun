import XCTest

final class BrandEvidenceTests: XCTestCase {
    func testLaunchAndHomeBrandSystem() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-oddfishUITestReset",
            "-oddfishUITestSkipIntroduction",
            "-oddfishUITestSilentGuide",
            "-oddfishUITestHoldBrand"
        ]
        app.launch()

        capture(app, "brand-01-startup-lockup")

        XCTAssertTrue(app.buttons["Play Classic"].waitForExistence(timeout: 6))
        // The home hierarchy exists briefly behind the 160 ms brand fade.
        // Let that presentation-only handoff finish before recording Home.
        Thread.sleep(forTimeInterval: 0.6)
        capture(app, "brand-02-home-lockup")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
