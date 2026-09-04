import Foundation

/// Something that happened during a game, described in terms a narrator could
/// use.
///
/// `GameSession` emits these; it does not care who listens. The guide mascot is
/// the first consumer, but nothing here mentions the mascot — the session must
/// not learn about presentation.
nonisolated enum GameEvent: Hashable, Sendable {
    case gameStarted(GameMode)
    case moveCommitted(MoveEvent)
    case selectionRejected(SelectionRejection)
    case promotionOffered
    case gamePaused
    case gameResumed
    case gameEnded(GameEndEvent)
}

nonisolated struct MoveEvent: Hashable, Sendable {
    let move: Move
    let side: PieceColor
    /// Player-relative ownership captured at commit time. `side` alone is not
    /// enough because the player can switch between White and Black.
    let isPlayerMove: Bool
    let pieceKind: PieceKind
    let capturedKind: PieceKind?
    /// The move left the *opponent* of `side` in check.
    let givesCheck: Bool
    /// 1-based index of this move within the game, counting both sides.
    let ply: Int

    init(
        move: Move,
        side: PieceColor,
        pieceKind: PieceKind,
        capturedKind: PieceKind?,
        givesCheck: Bool,
        ply: Int,
        isPlayerMove: Bool? = nil
    ) {
        self.move = move
        self.side = side
        self.isPlayerMove = isPlayerMove ?? (side == .white)
        self.pieceKind = pieceKind
        self.capturedKind = capturedKind
        self.givesCheck = givesCheck
        self.ply = ply
    }

    var isCapture: Bool { capturedKind != nil }
}

/// Why the board refused a touch. The distinctions exist so a coach can say
/// something specific instead of "that does not work".
nonisolated enum SelectionRejection: Hashable, Sendable {
    /// Restfish: the piece is still resting, with this many of your turns to go.
    case restingPiece(Square, remainingTurns: Int)
    case emptySquare(Square)
    case opponentPiece(Square)
    /// The piece is yours and awake, but has nowhere legal to go.
    case pieceHasNoMoves(Square)
    /// `movingKind` is what the player was holding, so a coach can name how
    /// that piece actually moves rather than saying "no".
    case illegalDestination(from: Square, to: Square, movingKind: PieceKind?)
}

nonisolated struct GameEndEvent: Hashable, Sendable {
    let outcome: GameOutcome
    let result: GameResult
    let resigned: Bool
    let moveCount: Int
    let duration: TimeInterval
    /// The live opponent strength at the final move, so result copy can name
    /// the Elo it is teasing without inventing a number.
    let opponentRating: Int?

    init(
        outcome: GameOutcome,
        result: GameResult,
        resigned: Bool,
        moveCount: Int,
        duration: TimeInterval,
        opponentRating: Int? = nil
    ) {
        self.outcome = outcome
        self.result = result
        self.resigned = resigned
        self.moveCount = moveCount
        self.duration = duration
        self.opponentRating = opponentRating
    }

    var playerWon: Bool { result == .win }
    var playerLost: Bool { result == .loss }
}
