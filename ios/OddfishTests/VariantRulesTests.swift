import Testing
@testable import Oddfish

struct VariantRulesTests {
    @Test func tempofishBlocksMovedPieceForTwoLaterTurns() {
        var position = Position.starting
        var state = VariantState()
        let configuration = ModeConfiguration.restfish

        let first = move("g1", "f3", in: position)
        state = VariantRules.applying(first, in: position, state: state, configuration: configuration)
        position = ChessEngine.apply(first, to: position)!
        #expect(state.restTurns(at: Square("f3")!) == 2)

        let blackReply = move("e7", "e5", in: position)
        state = VariantRules.applying(blackReply, in: position, state: state, configuration: configuration)
        position = ChessEngine.apply(blackReply, to: position)!
        #expect(!VariantRules.legalMoves(in: position, state: state, configuration: configuration).contains { $0.from == Square("f3")! })

        let whiteReply = move("b1", "c3", in: position)
        state = VariantRules.applying(whiteReply, in: position, state: state, configuration: configuration)
        position = ChessEngine.apply(whiteReply, to: position)!
        let blackSecondReply = move("b8", "c6", in: position)
        state = VariantRules.applying(blackSecondReply, in: position, state: state, configuration: configuration)
        position = ChessEngine.apply(blackSecondReply, to: position)!
        #expect(state.restTurns(at: Square("f3")!) == 1)
        #expect(!VariantRules.legalMoves(in: position, state: state, configuration: configuration).contains { $0.from == Square("f3")! })

        let finalWhiteTurn = move("a2", "a3", in: position)
        state = VariantRules.applying(finalWhiteTurn, in: position, state: state, configuration: configuration)
        position = ChessEngine.apply(finalWhiteTurn, to: position)!
        #expect(state.restTurns(at: Square("f3")!) == 0)
        // It is now Black's turn; after an ordinary reply the knight is free.
        let finalBlackTurn = move("a7", "a6", in: position)
        state = VariantRules.applying(finalBlackTurn, in: position, state: state, configuration: configuration)
        position = ChessEngine.apply(finalBlackTurn, to: position)!
        #expect(VariantRules.legalMoves(in: position, state: state, configuration: configuration).contains { $0.from == Square("f3")! })
    }

    @Test func tempofishWaivesRestsWhenInCheckHasNoAllowedEvasion() {
        let position = Position(fen: "4r2k/8/8/8/8/8/8/4K3 w - - 0 1")!
        let standard = ChessEngine.legalMoves(in: position)
        let everySourceResting = VariantState(restTurnsBySquare: Dictionary(
            standard.map { ($0.from, 2) },
            uniquingKeysWith: { existing, _ in existing }
        ))
        let filtered = VariantRules.legalMoves(in: position, state: everySourceResting, configuration: .restfish)
        #expect(!standard.isEmpty)
        #expect(filtered == standard)
    }

    @Test func enPassantCaptureClearsCapturedRestSquare() {
        let position = Position(fen: "7k/8/8/3pP3/8/8/8/4K3 w - d6 0 1")!
        let move = ChessEngine.legalMoves(in: position).first { $0.flags.contains(.enPassant) }!
        let state = VariantRules.applying(move, in: position, state: VariantState(restTurnsBySquare: [Square("d5")!: 2]), configuration: .restfish)
        #expect(state.restTurns(at: Square("d5")!) == 0)
        #expect(state.restTurns(at: Square("d6")!) == 2)
    }

    private func move(_ from: String, _ to: String, in position: Position) -> Move {
        ChessEngine.legalMoves(in: position).first { $0.from == Square(from)! && $0.to == Square(to)! }!
    }
}
