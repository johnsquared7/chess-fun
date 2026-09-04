import Foundation

/// Stable identities for the pieces currently on the board.
///
/// `Position` stores squares, not objects, so two consecutive positions share no
/// identity a view can animate between. Rendering pieces keyed by square index —
/// which is what the board did before — makes SwiftUI treat a move as "the piece
/// on e2 disappeared and a different piece on e4 appeared", so moves cross-fade
/// instead of sliding.
///
/// This assigns each piece a token that survives a move, so the view can key its
/// piece layer on the token and let SwiftUI animate the position change.
nonisolated struct BoardPieceIdentity: Hashable, Sendable {
    /// One slot per square; `nil` where the square is empty.
    private(set) var tokens: [Int?]
    private var nextToken: Int

    init(_ position: Position) {
        tokens = Array(repeating: nil, count: 64)
        nextToken = 0
        for index in 0..<64 where position.board[index] != nil {
            tokens[index] = nextToken
            nextToken += 1
        }
    }

    func token(at square: Square) -> Int? { tokens[square.index] }

    /// Carries identities from `previous` onto `current`.
    ///
    /// Deliberately derived from the two positions rather than from the move
    /// list: a diff is self-healing, so a restart, a restored snapshot, or any
    /// other jump still produces a coherent board instead of stale tokens.
    /// `lastMove` is only a hint for which pairing to prefer.
    mutating func advance(from previous: Position, to current: Position, lastMove: Move?) {
        var updated = [Int?](repeating: nil, count: 64)
        var availableSources: [Square: Int] = [:]
        var unmatchedDestinations: [Square] = []

        // Pass 1: anything unchanged keeps its token. Whatever is left over on
        // either side is the actual movement to reconcile.
        for index in 0..<64 {
            let square = Square(file: index % 8, rank: index / 8)
            let before = previous.piece(at: square)
            let after = current.piece(at: square)
            if let after, after == before, let token = tokens[square.index] {
                updated[square.index] = token
            } else {
                if before != nil, let token = tokens[square.index] {
                    availableSources[square] = token
                }
                if after != nil { unmatchedDestinations.append(square) }
            }
        }

        // Pass 2: pair each vacated square with a newly occupied one. The mover
        // named by `lastMove` is matched first so castling — two pieces moving
        // at once — cannot pair the king with the rook's origin.
        if let lastMove, unmatchedDestinations.contains(lastMove.to),
           let token = availableSources[lastMove.from] {
            updated[lastMove.to.index] = token
            availableSources.removeValue(forKey: lastMove.from)
            unmatchedDestinations.removeAll { $0 == lastMove.to }
        }

        for destination in unmatchedDestinations {
            guard let piece = current.piece(at: destination) else { continue }
            // Same piece, nearest origin: with two knights in play this picks the
            // shorter, more plausible slide.
            let match = availableSources
                .filter { previous.piece(at: $0.key) == piece }
                .min { lhs, rhs in
                    distance(lhs.key, destination) < distance(rhs.key, destination)
                }
            if let match {
                updated[destination.index] = match.value
                availableSources.removeValue(forKey: match.key)
            } else {
                // A promoted pawn, or a board that changed wholesale. Either way
                // this is a new object as far as the animation is concerned.
                updated[destination.index] = nextToken
                nextToken += 1
            }
        }

        tokens = updated
    }

    private func distance(_ lhs: Square, _ rhs: Square) -> Int {
        max(abs(lhs.file - rhs.file), abs(lhs.rank - rhs.rank))
    }
}
