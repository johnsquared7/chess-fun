import Foundation

/// An unfinished game, small enough to write on every move.
///
/// `ARCHITECTURE.md` promised this from the start and it was never built, so a
/// phone call in the middle of a game silently threw it away. Everything here is
/// state a position cannot reconstruct on its own: the live rating, Restfish
/// rest counters, the bonus-move flag, the integrity audit the crown tier
/// depends on, and the seed that makes a gimmick's randomness repeatable.
nonisolated struct GameSnapshot: Codable, Hashable, Sendable {
    /// Bumped whenever the meaning of a field changes. A snapshot from a
    /// different version is discarded rather than misread — losing one game in
    /// progress is a far better outcome than restoring a corrupted one.
    static let currentVersion = 1

    let version: Int
    let modeID: String
    let playerColor: PieceColor
    let startingRating: OpponentRating
    let currentRating: OpponentRating
    let parameters: GimmickParameters
    let startingParameters: GimmickParameters
    let gameSeed: UInt64

    /// Boards are stored as FEN so a change to `Position`'s layout cannot
    /// silently reinterpret an old payload.
    let startingFEN: String
    let currentFEN: String
    let historyFENs: [String]
    let moveHistory: [Move]

    let variantState: VariantState
    let completedPlayerTurns: Int
    let completedEngineTurns: Int
    let isBonusMove: Bool
    let integrity: GameIntegrity
    let elapsed: TimeInterval
    let savedAt: Date

    init(
        modeID: String,
        playerColor: PieceColor,
        startingRating: OpponentRating,
        currentRating: OpponentRating,
        parameters: GimmickParameters,
        startingParameters: GimmickParameters,
        gameSeed: UInt64,
        startingFEN: String,
        currentFEN: String,
        historyFENs: [String],
        moveHistory: [Move],
        variantState: VariantState,
        completedPlayerTurns: Int,
        completedEngineTurns: Int,
        isBonusMove: Bool,
        integrity: GameIntegrity,
        elapsed: TimeInterval,
        savedAt: Date = Date()
    ) {
        self.version = Self.currentVersion
        self.modeID = modeID
        self.playerColor = playerColor
        self.startingRating = startingRating
        self.currentRating = currentRating
        self.parameters = parameters
        self.startingParameters = startingParameters
        self.gameSeed = gameSeed
        self.startingFEN = startingFEN
        self.currentFEN = currentFEN
        self.historyFENs = historyFENs
        self.moveHistory = moveHistory
        self.variantState = variantState
        self.completedPlayerTurns = completedPlayerTurns
        self.completedEngineTurns = completedEngineTurns
        self.isBonusMove = isBonusMove
        self.integrity = integrity
        self.elapsed = elapsed
        self.savedAt = savedAt
    }

    var mode: GameMode? { GameMode(rawValue: modeID) }
    var position: Position? { Position(fen: currentFEN) }
    var startingPosition: Position? { Position(fen: startingFEN) }
    var positionHistory: [Position] { historyFENs.compactMap { Position(fen: $0) } }

    /// Whether this snapshot is worth offering back to the player.
    ///
    /// A game nobody has moved in is not worth restoring — it is identical to
    /// starting fresh, and offering it would be noise on every launch.
    var isResumable: Bool {
        guard version == Self.currentVersion,
              mode != nil,
              position != nil,
              startingPosition != nil,
              !moveHistory.isEmpty,
              historyFENs.count == moveHistory.count else { return false }
        return true
    }
}
