import Foundation
import Testing
@testable import Oddfish

/// Stage 8: an interrupted game survives.
///
/// `ARCHITECTURE.md` claimed this from the beginning and nothing implemented it,
/// so a phone call mid-game silently threw the game away.
@MainActor
struct GameSnapshotTests {
    private struct SlowStartingOpponent: ChessOpponent {
        let name = "Slow starter"

        func newGame() async {
            try? await Task.sleep(for: .milliseconds(180))
        }

        func bestMove(for request: OpponentRequest) async -> Move? {
            request.allowedMoves.first
        }
    }

    private func playedGame(mode: GameMode = .classic) -> GameSession {
        let session = GameSession(mode: mode)
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        return session
    }

    @Test func afreshGameIsNotWorthResuming() {
        // Identical to starting over, so offering it would be noise on launch.
        let session = GameSession(mode: .classic)
        #expect(!session.snapshot.isResumable)
    }

    @Test func aGameInProgressCarriesEverythingAPositionCannot() {
        let session = playedGame()
        let snapshot = session.snapshot

        #expect(snapshot.isResumable)
        #expect(snapshot.modeID == GameMode.classic.rawValue)
        #expect(snapshot.currentFEN == session.position.fen)
        #expect(snapshot.moveHistory == session.moveHistory)
        #expect(snapshot.historyFENs.count == session.moveHistory.count)
        #expect(snapshot.gameSeed != 0 || snapshot.gameSeed == 0)
        #expect(snapshot.currentRating == session.currentRating)
    }

    @Test func restoringReturnsTheSameBoard() throws {
        let original = playedGame()
        let snapshot = original.snapshot

        let resumed = GameSession(mode: .classic, restoring: snapshot)
        #expect(resumed.position.fen == original.position.fen)
        #expect(resumed.moveHistory == original.moveHistory)
        #expect(resumed.positionHistory.map(\.fen) == original.positionHistory.map(\.fen))
        #expect(resumed.currentRating == original.currentRating)
        #expect(resumed.playerColor == original.playerColor)
    }

    @Test func aResumedGameKeepsItsRestCountersAndIntegrity() async {
        // Restfish rest counters cannot be rebuilt from a position, and the
        // integrity audit decides the crown tier.
        let session = GameSession(mode: .restfish)
        #expect(session.attemptMove(from: Square("g1")!, to: Square("f3")!))
        session.recordControlUse(.undo)

        let resumed = GameSession(mode: .restfish, restoring: session.snapshot)
        #expect(resumed.variantState == session.variantState)
        #expect(resumed.variantState.restTurns(at: Square("f3")!) > 0)
        #expect(resumed.integrity.count(for: .undo) == 1)
        #expect(resumed.integrity.maximumCrownTier == 1, "Undo must still cost the crown tier after a restore")
    }

    @Test func aSnapshotSurvivesEncodingAndDecoding() throws {
        let snapshot = playedGame().snapshot
        let restored = try JSONDecoder().decode(
            GameSnapshot.self,
            from: try JSONEncoder().encode(snapshot)
        )
        #expect(restored == snapshot)
        #expect(restored.isResumable)
    }

    @Test func aSnapshotFromAnotherVersionIsRefused() throws {
        // Better to lose one interrupted game than to restore a corrupted one.
        var json = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(playedGame().snapshot)
        ) as! [String: Any]
        json["version"] = GameSnapshot.currentVersion + 1
        let bumped = try JSONSerialization.data(withJSONObject: json)
        let restored = try JSONDecoder().decode(GameSnapshot.self, from: bumped)
        #expect(!restored.isResumable)
    }

    @Test func aSnapshotForADifferentModeIsIgnored() {
        let snapshot = playedGame(mode: .classic).snapshot
        // Restoring into the wrong mode must start fresh, not graft one game's
        // board onto another game's rules.
        let mismatched = GameSession(mode: .rattleFish, restoring: snapshot)
        #expect(mismatched.moveHistory.isEmpty)
        #expect(mismatched.position == mismatched.rule.startingPosition(playerColor: mismatched.playerColor))
    }

    @Test func aFinishedGameStopsBeingResumable() {
        let session = playedGame()
        #expect(session.snapshot.isResumable)
        session.resign()
        // `publishSnapshot` clears the store on a terminal game; the snapshot
        // itself is still well-formed, so the guard lives in the session.
        #expect(session.resigned)
    }

    @Test func theStoreOnlyKeepsResumableGames() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "oddfish.appStore.payload")
        let store = AppStateStore(userDefaults: defaults)
        #expect(store.activeGame == nil)

        let session = playedGame()
        store.setActiveGame(session.snapshot)
        #expect(store.activeGame != nil)

        let reloaded = AppStateStore(userDefaults: defaults)
        #expect(reloaded.activeGame?.currentFEN == session.position.fen)

        store.setActiveGame(nil)
        #expect(store.activeGame == nil)
        #expect(AppStateStore(userDefaults: defaults).activeGame == nil)
    }

    @Test func anUntouchedGameIsNeverStored() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "oddfish.appStore.payload")
        let store = AppStateStore(userDefaults: defaults)
        store.setActiveGame(GameSession(mode: .classic).snapshot)
        #expect(store.activeGame == nil, "A game with no moves is the same as no game")
    }

    @Test func explicitlyLeavingClearsThePublishedGame() {
        var stored: GameSnapshot?
        let session = GameSession(
            mode: .classic,
            onSnapshot: { stored = $0 }
        )

        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(stored?.currentFEN == session.position.fen)

        session.exit()

        #expect(stored == nil, "Leave means discard; it must not behave like an interruption")
    }

    @Test func restartAndTimelineChangesRepublishImmediately() {
        var stored: GameSnapshot?
        let session = GameSession(
            mode: .classic,
            onSnapshot: { stored = $0 }
        )

        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        let playedFEN = session.position.fen
        #expect(stored?.currentFEN == playedFEN)

        session.undo()
        #expect(stored == nil, "Undoing to an untouched board must clear the old resumable game")

        session.redo()
        #expect(stored?.currentFEN == playedFEN)
        #expect(stored?.integrity.count(for: .undo) == 1)
        #expect(stored?.integrity.count(for: .redo) == 1)

        session.restart()
        #expect(stored == nil, "A restart must never leave the pre-restart board on disk")
    }

    @Test func nonMoveStateChangesReachThePublishedSnapshot() {
        var stored: GameSnapshot?
        var settings = AppSettings.default
        let session = GameSession(
            mode: .classic,
            settings: settings,
            onSnapshot: { stored = $0 }
        )

        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))

        session.pause()
        #expect(stored?.integrity.count(for: .pause) == 1)

        session.resume()
        #expect(stored?.integrity.count(for: .resume) == 1)

        settings.showLegalMoves.toggle()
        session.applySettings(settings)
        #expect(stored?.integrity.count(for: .settingChange) == 1)

        session.exit()
    }

    @Test func exitingDuringOpponentStartupCannotRepublishTheGame() async {
        var publications: [GameSnapshot?] = []
        let session = GameSession(
            mode: .classic,
            playerColor: .black,
            opponent: { SlowStartingOpponent() },
            onSnapshot: { publications.append($0) }
        )

        session.exit()
        try? await Task.sleep(for: .milliseconds(450))

        #expect(publications.count == 1)
        #expect(publications[0] == nil)
        #expect(session.moveHistory.isEmpty, "Late engine startup moved after the session had exited")
    }
}
