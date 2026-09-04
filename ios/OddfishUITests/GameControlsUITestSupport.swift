import XCTest

/// Shared driving for the game screen's controls.
///
/// The controls used to live in a three-detent drawer that tests advanced by
/// tapping it repeatedly, so every test encoded the drawer's state machine.
/// They now live behind one Options sheet. Putting the two verbs here means the
/// next change to that surface is one edit rather than seven.
extension XCUIApplication {
    var gameOptionsButton: XCUIElement { buttons["Options"] }

    /// Opens the game options sheet and waits for it to be usable.
    @discardableResult
    func openGameOptions(timeout: TimeInterval = 5) -> Bool {
        // The wide layout has no sheet: its controls are always on screen.
        if otherElements["game-control-side-panel"].exists { return true }
        if buttons["Done"].exists { return true }
        guard gameOptionsButton.waitForExistence(timeout: timeout) else { return false }
        gameOptionsButton.tap()
        return buttons["Done"].waitForExistence(timeout: timeout)
    }

    func closeGameOptions() {
        guard buttons["Done"].exists else { return }
        buttons["Done"].tap()
    }
}
