import Foundation

/// The compact runtime state owned by a game session. It intentionally contains
/// no board data: orthodox chess state remains solely in `Position`.
nonisolated struct VariantState: Codable, Hashable, Sendable {
    /// Remaining *same-colour turns* for a piece at its current square.
    private(set) var restTurnsBySquare: [Square: Int] = [:]

    init(restTurnsBySquare: [Square: Int] = [:]) {
        self.restTurnsBySquare = restTurnsBySquare.filter { $0.value > 0 }
    }

    func restTurns(at square: Square) -> Int {
        restTurnsBySquare[square, default: 0]
    }

    func isResting(_ square: Square) -> Bool {
        restTurns(at: square) > 0
    }
}

/// Small mode policies applied to the engine's already-legal moves.
nonisolated enum VariantRules {
    static func legalMoves(
        in position: Position,
        state: VariantState,
        configuration: ModeConfiguration
    ) -> [Move] {
        let standard = ChessEngine.legalMoves(in: position)
        if configuration.rule == .reluctantKing {
            let withoutCastling = standard.filter { !$0.isCastle }
            let nonKing = withoutCastling.filter { position.piece(at: $0.from)?.kind != .king }
            let kingMoves = withoutCastling.filter { position.piece(at: $0.from)?.kind == .king }
            if ChessEngine.isInCheck(position.sideToMove, in: position) {
                // The king may move only when no other piece can answer check.
                return nonKing.isEmpty ? kingMoves : nonKing
            }
            let kingCaptures = kingMoves.filter(\.isCapture)
            return nonKing + kingCaptures
        }
        if configuration.rule == .forwardOnly {
            // "Back toward its own back rank" is a rank change against the
            // pawn direction. Sideways is not a retreat, so rooks and knights
            // keep their lateral moves, and castling moves its rook along the
            // rank rather than down it.
            let forward = standard.filter { move in
                guard let piece = position.piece(at: move.from), piece.kind != .king else { return true }
                return (move.to.rank - move.from.rank) * piece.color.pawnDirection >= 0
            }
            // As with Restfish, a mode rule is never allowed to turn a check
            // into an impossible position. Only standard legal evasions are
            // considered, so this cannot reintroduce an illegal chess move.
            if forward.isEmpty, ChessEngine.isInCheck(position.sideToMove, in: position) {
                return standard
            }
            return forward
        }
        guard configuration.rule == .restingPiece else { return standard }

        let unrestricted = standard.filter { !state.isResting($0.from) }
        // A Restfish rest is never allowed to turn a check into an impossible
        // position. Only standard legal evasions are considered here, so this
        // cannot reintroduce an illegal chess move.
        if unrestricted.isEmpty, ChessEngine.isInCheck(position.sideToMove, in: position) {
            return standard
        }
        return unrestricted
    }

    /// Advances existing rest counters for the player who just moved, then
    /// marks the moved piece as resting. Captures clear any state belonging to
    /// the removed piece, including en-passant captures.
    static func applying(
        _ move: Move,
        in position: Position,
        state: VariantState,
        configuration: ModeConfiguration
    ) -> VariantState {
        guard configuration.rule == .restingPiece,
              let movingPiece = position.piece(at: move.from) else { return state }

        var rests = state.restTurnsBySquare
        for (square, remaining) in rests where position.piece(at: square)?.color == movingPiece.color {
            if remaining <= 1 { rests.removeValue(forKey: square) }
            else { rests[square] = remaining - 1 }
        }

        let capturedSquare = move.flags.contains(.enPassant)
            ? move.to.offset(file: 0, rank: -movingPiece.color.pawnDirection)
            : move.to
        if let capturedSquare { rests.removeValue(forKey: capturedSquare) }
        rests.removeValue(forKey: move.from)
        rests[move.to] = max(1, configuration.restTurns)
        return VariantState(restTurnsBySquare: rests)
    }

}
