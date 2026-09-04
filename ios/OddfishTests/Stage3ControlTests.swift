import Testing
@testable import Oddfish

@MainActor
struct Stage3SessionTests {
    private struct FirstAllowedOpponent: ChessOpponent {
        let name = "First"
        func bestMove(for request: OpponentRequest) async -> Move? {
            request.allowedMoves.first
        }
    }

    private struct RisingRatingRule: GimmickRule {
        let startingRating = OpponentRating(100)

        func rating(
            after ply: GimmickPly,
            currentRating: OpponentRating,
            parameters: GimmickParameters
        ) -> OpponentRating {
            currentRating.adjusted(by: 10)
        }
    }

    private struct BlackMateRule: GimmickRule {
        let startingPosition = Position(fen: "r5k1/8/8/8/8/8/5PPP/6K1 b - - 0 1")!
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    @Test func blackGameFlipsTurnOwnershipAndLetsTheOpponentOpen() async throws {
        let session = GameSession(
            mode: .classic,
            playerColor: .black,
            opponent: { FirstAllowedOpponent() }
        )

        #expect(session.playerColor == .black)
        #expect(!session.isPlayerTurn)
        #expect(await waitUntil { session.moveHistory.count == 1 })
        #expect(session.position.sideToMove == .black)
        #expect(session.isPlayerTurn)
        #expect(!session.canUndo, "The engine's forced opening is not a player decision to undo")

        let blackMove = try #require(session.legalMoves.first)
        #expect(session.position.piece(at: blackMove.from)?.color == .black)
        #expect(session.attemptMove(from: blackMove.from, to: blackMove.to))
        session.exit()
    }

    @Test func undoAndRedoRestoreAFullPairIncludingVariantAndRatingState() async {
        let session = GameSession(
            mode: .restfish,
            rule: RisingRatingRule(),
            opponent: { FirstAllowedOpponent() }
        )

        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(await waitUntil { session.moveHistory.count == 2 })
        let resolvedPosition = session.position
        let resolvedVariant = session.variantState
        let resolvedHistory = session.positionHistory
        #expect(session.currentRating == OpponentRating(120))

        session.undo()
        #expect(session.position == .starting)
        #expect(session.moveHistory.isEmpty)
        #expect(session.positionHistory.isEmpty)
        #expect(session.variantState == VariantState())
        #expect(session.currentRating == OpponentRating(100))
        #expect(session.integrity.count(for: .undo) == 1)
        #expect(session.integrity.maximumCrownTier == 1)
        #expect(session.canRedo)

        session.redo()
        #expect(session.position == resolvedPosition)
        #expect(session.variantState == resolvedVariant)
        #expect(session.positionHistory == resolvedHistory)
        #expect(session.moveHistory.count == 2)
        #expect(session.currentRating == OpponentRating(120))
        #expect(session.integrity.count(for: .redo) == 1)
        session.exit()
    }

    @Test func undoCancelsTheReplyAlreadyInFlight() async throws {
        let session = GameSession(mode: .classic, opponent: { FirstAllowedOpponent() })
        #expect(session.attemptMove(from: Square("d2")!, to: Square("d4")!))
        #expect(session.isBotThinking)

        session.undo()
        try await Task.sleep(for: .milliseconds(800))

        #expect(session.position == .starting)
        #expect(session.moveHistory.isEmpty)
        #expect(session.isPlayerTurn)
        #expect(!session.isBotThinking)
        session.exit()
    }

    @Test func aBlackCheckmateIsRecordedAsAPlayerWin() throws {
        var recorded: GameRecord?
        let session = GameSession(
            mode: .classic,
            rule: BlackMateRule(),
            playerColor: .black,
            opponent: { FirstAllowedOpponent() },
            onRecord: { recorded = $0 }
        )
        let mate = try #require(session.legalMoves.first { move in
            guard let next = ChessEngine.apply(move, to: session.position) else { return false }
            return ChessEngine.outcome(for: next, history: [session.position]) == .checkmate(winner: .black)
        })

        #expect(session.attemptMove(from: mate.from, to: mate.to))
        #expect(session.outcome == .checkmate(winner: .black))
        #expect(recorded?.result == .win)
    }

    @Test func materialBalanceIsSignedFromThePlayersSide() {
        let position = Position(fen: "7k/8/8/8/8/8/8/Q5rK w - - 0 1")!
        #expect(position.materialValue(for: .white) == 9)
        #expect(position.materialValue(for: .black) == 5)
        #expect(position.materialBalance(for: .white) == 4)
        #expect(position.materialBalance(for: .black) == -4)
    }
}

struct BoardPerspectiveTests {
    @Test func whiteAndBlackPerspectivesAreExactInverses() {
        let white = BoardPerspective(color: .white)
        let black = BoardPerspective(color: .black)

        #expect(white.visualCoordinates(for: Square("a1")!) == (0, 7))
        #expect(white.visualCoordinates(for: Square("h8")!) == (7, 0))
        #expect(black.visualCoordinates(for: Square("a1")!) == (7, 0))
        #expect(black.visualCoordinates(for: Square("h8")!) == (0, 7))

        for square in Position.starting.squares() {
            let whiteVisual = white.visualCoordinates(for: square)
            let blackVisual = black.visualCoordinates(for: square)
            #expect(white.square(visualFile: whiteVisual.file, visualRank: whiteVisual.rank) == square)
            #expect(black.square(visualFile: blackVisual.file, visualRank: blackVisual.rank) == square)
        }
    }
}
