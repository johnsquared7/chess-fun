import Testing
@testable import Oddfish

struct BotTests {
    @Test func botAlwaysReturnsOneOfTheProvidedLegalMoves() {
        var position = Position.starting
        let configuration = ChessBot.Configuration(depth: 2, variationWindow: 1, seed: 42)

        for _ in 0..<12 {
            let legal = ChessEngine.legalMoves(in: position)
            let move = ChessBot.chooseMove(in: position, legalMoves: legal, configuration: configuration)
            #expect(move != nil)
            #expect(legal.contains(move!))
            position = ChessEngine.apply(move!, to: position)!
        }
    }

    @Test func botDoesNotEscapeVariantRootRestrictions() {
        let position = Position.starting
        let allowed = ChessEngine.legalMoves(in: position).filter { $0.from.algebraic == "e2" }
        let input = BotSearchInput(position: position, legalRootMoves: allowed, configuration: .init(depth: 1))
        let move = ChessBot.chooseMove(for: input)
        #expect(move != nil)
        #expect(allowed.contains(move!))
    }

    @Test func botSelectionIsDeterministicForTheSameInput() {
        let input = BotSearchInput(position: .starting, configuration: .init(depth: 2, variationWindow: 2, seed: 8))
        #expect(ChessBot.chooseMove(for: input) == ChessBot.chooseMove(for: input))
    }

    /// The earlier bot tests proved legality and determinism, never that the
    /// search actually evaluates. A bot that only ever returned a legal move
    /// would pass them all, so cover the two simplest evaluation facts: it
    /// takes a mate it can see, and it answers check instead of ignoring it.
    @Test func botTakesAMateThatIsOneMoveAway() throws {
        // White can mate from g6 on either g7 or h7.
        let position = try #require(Position(fen: "7k/8/6QK/8/8/8/8/8 w - - 0 1"))
        let move = try #require(ChessBot.chooseMove(for: BotSearchInput(
            position: position,
            configuration: .init(depth: 2)
        )))
        let next = try #require(ChessEngine.apply(move, to: position))
        #expect(ChessEngine.outcome(for: next, history: [position]) == .checkmate(winner: .white))
    }

    @Test func botAnswersCheckWithAMoveThatResolvesIt() throws {
        let position = try #require(Position(fen: "k7/8/8/8/8/8/3r4/3K4 w - - 0 1"))
        let legal = ChessEngine.legalMoves(in: position)
        let move = try #require(ChessBot.chooseMove(for: BotSearchInput(
            position: position,
            configuration: .init(depth: 3)
        )))
        let next = try #require(ChessEngine.apply(move, to: position))
        #expect(legal.contains(move))
        #expect(!ChessEngine.isInCheck(.white, in: next))
    }

    @Test func botConfigurationMapsTheRatingDialOntoStrengthBands() {
        let cases: [(rating: Int, depth: Int, window: Int)] = [
            (0, 1, 3),
            (1_319, 1, 3),
            (1_320, 1, 2),
            (2_199, 1, 2),
            (2_200, 2, 1),
            (3_189, 2, 1),
            (3_190, 3, 0),
            (3_191, 4, 0),
            (3_600, 4, 0),
        ]
        for testCase in cases {
            let configuration = ChessBot.Configuration(rating: OpponentRating(testCase.rating))
            #expect(configuration.depth == testCase.depth, "depth for \(testCase.rating)")
            #expect(configuration.variationWindow == testCase.window, "window for \(testCase.rating)")
        }
    }
}
