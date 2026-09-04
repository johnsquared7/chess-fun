import Testing
@testable import Oddfish

struct GameSessionTests {
    @Test @MainActor func tapAndDirectMoveUseTheSameLegalCommit() {
        let session = GameSession(mode: .classic)
        session.handleTap(on: Square("e2")!)
        session.handleTap(on: Square("e4")!)
        #expect(session.lastMove?.from == Square("e2")!)
        #expect(session.lastMove?.to == Square("e4")!)
        #expect(session.position.sideToMove == .black)
        #expect(session.isBotThinking)
    }

    @Test @MainActor func restartInvalidatesPendingBotWork() async throws {
        let session = GameSession(mode: .classic)
        #expect(session.attemptMove(from: Square("d2")!, to: Square("d4")!))
        session.restart()
        try await Task.sleep(for: .milliseconds(550))
        #expect(session.position == .starting)
        #expect(session.moveHistory.isEmpty)
        #expect(!session.isBotThinking)
    }

}
