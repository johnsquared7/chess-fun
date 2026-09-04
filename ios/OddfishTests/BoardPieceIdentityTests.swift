import Testing
@testable import Oddfish

/// The piece layer animates by identity, so these tokens decide whether a move
/// slides or pops. A wrong pairing is not a crash — it is a piece teleporting.
struct BoardPieceIdentityTests {
    private func advanced(_ from: Position, by move: Move) throws -> (before: BoardPieceIdentity, after: BoardPieceIdentity, position: Position) {
        let identity = BoardPieceIdentity(from)
        let next = try #require(ChessEngine.apply(move, to: from))
        var updated = identity
        updated.advance(from: from, to: next, lastMove: move)
        return (identity, updated, next)
    }

    private func move(from: String, to: String, in position: Position) throws -> Move {
        let source = try #require(Square(from))
        let destination = try #require(Square(to))
        return try #require(ChessEngine.legalMoves(in: position).first {
            $0.from == source && $0.to == destination
        })
    }

    @Test func aQuietMoveCarriesTheSameTokenToTheDestination() throws {
        let start = Position.starting
        let e4 = try move(from: "e2", to: "e4", in: start)
        let result = try advanced(start, by: e4)

        let original = try #require(result.before.token(at: Square("e2")!))
        #expect(result.after.token(at: Square("e4")!) == original)
        #expect(result.after.token(at: Square("e2")!) == nil)
    }

    @Test func untouchedPiecesKeepTheirTokens() throws {
        let start = Position.starting
        let e4 = try move(from: "e2", to: "e4", in: start)
        let result = try advanced(start, by: e4)

        for square in start.squares() where square != Square("e2")! {
            guard start.piece(at: square) != nil else { continue }
            #expect(result.after.token(at: square) == result.before.token(at: square))
        }
    }

    @Test func aCaptureDropsTheCapturedPieceAndKeepsTheCaptor() throws {
        // Black knight on d5, white pawn on e4: exd5 removes the knight.
        let position = try #require(Position(fen: "4k3/8/8/3n4/4P3/8/8/4K3 w - - 0 1"))
        let capture = try move(from: "e4", to: "d5", in: position)
        let result = try advanced(position, by: capture)

        let pawn = try #require(result.before.token(at: Square("e4")!))
        let knight = try #require(result.before.token(at: Square("d5")!))
        #expect(result.after.token(at: Square("d5")!) == pawn)
        #expect(result.after.tokens.compactMap { $0 }.contains(knight) == false)
    }

    @Test func castlingMovesTheKingAndTheRookToTheirOwnDestinations() throws {
        let position = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R w K - 0 1"))
        let castle = try move(from: "e1", to: "g1", in: position)
        let result = try advanced(position, by: castle)

        let king = try #require(result.before.token(at: Square("e1")!))
        let rook = try #require(result.before.token(at: Square("h1")!))
        // Without the last-move hint the king could be paired with the rook's
        // origin, which would send both pieces sliding through each other.
        #expect(result.after.token(at: Square("g1")!) == king)
        #expect(result.after.token(at: Square("f1")!) == rook)
    }

    @Test func aPromotedPawnTravelsAsTheSameObject() throws {
        let position = try #require(Position(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"))
        let promotion = try #require(ChessEngine.legalMoves(in: position).first {
            $0.from == Square("a7")! && $0.to == Square("a8")! && $0.promotion == .queen
        })
        let result = try advanced(position, by: promotion)

        let pawn = try #require(result.before.token(at: Square("a7")!))
        #expect(result.after.token(at: Square("a8")!) == pawn)
        #expect(result.position.piece(at: Square("a8")!)?.kind == .queen)
    }

    @Test func everyOccupiedSquareHasExactlyOneTokenAfterAdvancing() throws {
        var position = Position.starting
        var identity = BoardPieceIdentity(position)

        for (from, to) in [("e2", "e4"), ("e7", "e5"), ("g1", "f3"), ("b8", "c6")] {
            let step = try move(from: from, to: to, in: position)
            let next = try #require(ChessEngine.apply(step, to: position))
            identity.advance(from: position, to: next, lastMove: step)
            position = next
        }

        let occupied = position.squares().filter { position.piece(at: $0) != nil }
        let tokens = occupied.compactMap { identity.token(at: $0) }
        #expect(tokens.count == occupied.count)
        #expect(Set(tokens).count == tokens.count, "Two pieces must never share a token")
    }

    @Test func aWholesaleBoardChangeStillProducesACoherentBoard() throws {
        // A restart is not a move. The diff has to cope without a hint.
        var identity = BoardPieceIdentity(Position.starting)
        let midgame = try #require(Position(fen: "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"))
        identity.advance(from: .starting, to: midgame, lastMove: nil)

        let occupied = midgame.squares().filter { midgame.piece(at: $0) != nil }
        let tokens = occupied.compactMap { identity.token(at: $0) }
        #expect(tokens.count == occupied.count)
        #expect(Set(tokens).count == tokens.count)
    }
}
