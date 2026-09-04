import Testing
@testable import Oddfish

/// The in-game move tape reads `GameSession.moveNotation` on every view update,
/// so it is cached. A cache that answers the previous game's list is worse than
/// no cache at all, which is what these cover.
struct MoveNotationTests {
    @Test @MainActor func notationFollowsThePlayedMoves() {
        let session = GameSession(mode: .classic)
        #expect(session.moveNotation.isEmpty)
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(session.moveNotation == ["e4"])
        #expect(session.attemptMove(from: Square("g1")!, to: Square("f3")!) == false,
                "It is not White's move")
        #expect(session.moveNotation == ["e4"])
    }

    /// The key is the ply count *and* the position, because undoing a move and
    /// playing a different one leaves the count where it was.
    @Test @MainActor func adifferentMoveAtTheSamePlyIsNotServedFromTheCache() {
        let session = GameSession(mode: .classic)
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(session.moveNotation == ["e4"])

        session.restart()
        #expect(session.moveNotation.isEmpty)
        #expect(session.attemptMove(from: Square("d2")!, to: Square("d4")!))
        #expect(session.moveNotation == ["d4"])
    }

    @Test @MainActor func restartClearsTheNotation() {
        let session = GameSession(mode: .classic)
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(!session.moveNotation.isEmpty)
        session.restart()
        #expect(session.moveNotation.isEmpty)
    }
}
