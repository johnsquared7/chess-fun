import Testing
@testable import Oddfish

struct ChessEngineTests {
    @Test func initialPositionHasTwentyLegalMoves() {
        #expect(ChessEngine.legalMoves(in: .starting).count == 20)
        #expect(Position.starting.fen == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
    }

    @Test func openingPerftMatchesKnownCounts() {
        #expect(perft(Position.starting, depth: 2) == 400)
        #expect(perft(Position.starting, depth: 3) == 8_902)
    }

    @Test func castlingThroughAnAttackedSquareIsIllegal() {
        let position = Position(fen: "r3k2r/8/8/8/2b5/8/8/R3K2R w KQkq - 0 1")!
        let castles = ChessEngine.legalMoves(in: position).filter(\.isCastle)
        #expect(!castles.contains { $0.to.algebraic == "g1" })
        #expect(castles.contains { $0.to.algebraic == "c1" })
    }

    @Test func enPassantThatExposesOwnKingIsIllegal() {
        let position = Position(fen: "k3r3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")!
        let pseudo = ChessEngine.pseudoLegalMoves(in: position)
        #expect(pseudo.contains { $0.from.algebraic == "e5" && $0.to.algebraic == "d6" && $0.flags.contains(.enPassant) })
        #expect(!ChessEngine.legalMoves(in: position).contains { $0.from.algebraic == "e5" && $0.to.algebraic == "d6" })
    }

    @Test func allPromotionChoicesAreGeneratedAndApplied() {
        let position = Position(fen: "7k/P7/8/8/8/8/8/7K w - - 0 1")!
        let promotions = ChessEngine.legalMoves(in: position).filter { $0.from.algebraic == "a7" && $0.to.algebraic == "a8" }
        #expect(Set(promotions.compactMap(\.promotion)) == Set([.queen, .rook, .bishop, .knight]))
        for move in promotions {
            let next = ChessEngine.apply(move, to: position)
            #expect(next?.piece(at: Square("a8")!) == Piece(color: .white, kind: move.promotion!))
        }
    }

    @Test func mateAndStalemateAreClassified() {
        let mate = Position(fen: "7k/6Q1/6K1/8/8/8/8/8 b - - 0 1")!
        let stalemate = Position(fen: "7k/5Q2/7K/8/8/8/8/8 b - - 0 1")!
        #expect(ChessEngine.outcome(for: mate) == .checkmate(winner: .white))
        #expect(ChessEngine.outcome(for: stalemate) == .stalemate)
    }

    @Test func commonInsufficientMaterialDrawsAreDetected() {
        #expect(ChessEngine.outcome(for: Position(fen: "7k/8/8/8/8/8/8/K7 w - - 0 1")!) == .draw(reason: .insufficientMaterial))
        #expect(ChessEngine.outcome(for: Position(fen: "7k/8/8/8/8/8/8/KN6 w - - 0 1")!) == .draw(reason: .insufficientMaterial))
        #expect(ChessEngine.outcome(for: Position(fen: "7k/8/8/8/8/8/8/KB6 w - - 0 1")!) == .draw(reason: .insufficientMaterial))
    }

    @Test func repetitionAndFiftyMoveDrawsUseProvidedState() {
        let position = Position.starting
        #expect(ChessEngine.outcome(for: position, history: [position, position]) == .draw(reason: .threefoldRepetition))
        let fifty = Position(fen: "7k/8/8/8/8/8/8/KR6 w - - 100 1")!
        #expect(ChessEngine.outcome(for: fifty) == .draw(reason: .fiftyMoveRule))
    }

    private func perft(_ position: Position, depth: Int) -> Int {
        if depth == 0 { return 1 }
        return ChessEngine.legalMoves(in: position).reduce(0) { total, move in
            total + perft(ChessEngine.apply(move, to: position)!, depth: depth - 1)
        }
    }
}
