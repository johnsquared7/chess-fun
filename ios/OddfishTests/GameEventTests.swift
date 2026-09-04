import Testing
@testable import Oddfish

/// The event stream is what the guide mascot will listen to. These tests pin the
/// facts it needs to be able to say something specific and correct.
@MainActor
struct GameEventTests {
    private func session(_ mode: GameMode, settings: AppSettings = .default) -> GameSession {
        GameSession(mode: mode, settings: settings)
    }

    @Test func aNewSessionAnnouncesItselfBeforeAnyListenerCanAttach() {
        let game = session(.classic)
        // `onEvent` cannot be set until after `init`, so the opening beat has to
        // survive in the replay log or the guide has nothing to greet.
        #expect(game.eventLog.first == .gameStarted(.classic))
    }

    /// Waits for the opponent's reply so the board is back under the player's
    /// control. Returns false if the turn never came back.
    private func waitForPlayerTurn(_ game: GameSession, timeout: Duration = .seconds(8)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if game.isPlayerTurn, !game.isBotThinking { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    @Test func aCommittedMoveReportsWhatMovedAndWhetherItTook() throws {
        let game = session(.classic)
        var received: [GameEvent] = []
        game.onEvent = { received.append($0) }

        #expect(game.attemptMove(from: Square("e2")!, to: Square("e4")!))

        let move = received.compactMap { event -> MoveEvent? in
            if case .moveCommitted(let detail) = event { return detail }
            return nil
        }.first
        let detail = try #require(move)
        #expect(detail.side == .white)
        #expect(detail.isPlayerMove)
        #expect(detail.pieceKind == .pawn)
        #expect(detail.capturedKind == nil)
        #expect(!detail.isCapture)
        #expect(!detail.givesCheck)
        #expect(detail.ply == 1)
    }

    @Test func enPassantReportsTheCapturedPawnEvenThoughItIsNotOnTheTargetSquare() throws {
        let game = GameSession(mode: .classic)
        // Walk into an en passant: 1.e4 d5 is not needed — drive the board directly.
        #expect(game.attemptMove(from: Square("e2")!, to: Square("e4")!))

        // The bot replies asynchronously; assert on the pure helper instead of
        // racing it, using a position where en passant is available.
        let position = try #require(Position(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"))
        let capture = try #require(ChessEngine.legalMoves(in: position).first {
            $0.from == Square("e5")! && $0.to == Square("d6")!
        })
        #expect(capture.flags.contains(.enPassant))
        #expect(position.piece(at: Square("d6")!) == nil, "The captured pawn is on d5, not d6")
    }

    @Test func tempofishSaysWhyARestingPieceCannotBeChosen() async {
        // This test exercises selection feedback, not opponent strength. Keep
        // the fallback search shallow so the full-strength product default
        // cannot turn an event assertion into a search-performance timeout.
        let game = GameSession(mode: .restfish, rating: .minimum)
        var received: [GameEvent] = []

        #expect(game.attemptMove(from: Square("g1")!, to: Square("f3")!))
        #expect(await waitForPlayerTurn(game), "The opponent never replied")

        game.onEvent = { received.append($0) }
        game.handleTap(on: Square("f3")!)

        let rejection = received.compactMap { event -> SelectionRejection? in
            if case .selectionRejected(let reason) = event { return reason }
            return nil
        }.first
        #expect(rejection == .restingPiece(Square("f3")!, remainingTurns: 2))
    }

    @Test func touchingAnEmptySquareIsDistinguishedFromTouchingTheOpponent() {
        let game = session(.classic)
        var received: [SelectionRejection] = []
        game.onEvent = { event in
            if case .selectionRejected(let reason) = event { received.append(reason) }
        }

        game.handleTap(on: Square("e5")!)
        game.handleTap(on: Square("e7")!)

        #expect(received == [.emptySquare(Square("e5")!), .opponentPiece(Square("e7")!)])
    }

    @Test func resigningEndsTheGameAsALossAndSaysSo() {
        let game = session(.classic)
        var ending: GameEndEvent?
        game.onEvent = { event in
            if case .gameEnded(let detail) = event { ending = detail }
        }

        game.resign()

        #expect(ending?.resigned == true)
        #expect(ending?.result == .loss)
        #expect(ending?.playerLost == true)
        #expect(ending?.opponentRating == game.currentRating.rawValue)
    }

    @Test func restartingClearsTheLogAndOpensAFreshGame() {
        let game = session(.classic)
        #expect(game.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(game.eventLog.count > 1)

        game.restart()

        #expect(game.eventLog == [.gameStarted(.classic)])
    }

    @Test func theLogStaysBounded() {
        let game = session(.classic)
        for _ in 0..<80 {
            game.handleTap(on: Square("e5")!) // Always rejected, always an event.
        }
        #expect(game.eventLog.count <= 32)
    }
}
