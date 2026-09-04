import Foundation

/// One numeric control owned by a gimmick. The catalogue can render these
/// without learning a concrete rule type.
nonisolated struct GimmickParameterDefinition: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double

    init(
        id: String,
        title: String,
        range: ClosedRange<Double>,
        step: Double = 1,
        defaultValue: Double
    ) {
        self.id = id
        self.title = title
        self.range = range
        self.step = max(0.000_001, step)
        self.defaultValue = min(max(defaultValue, range.lowerBound), range.upperBound)
    }
}

/// Type-erased parameter values let every rule travel through `GameSession`
/// while each concrete mode still defines its own keys and defaults.
nonisolated struct GimmickParameters: Codable, Hashable, Sendable {
    private var values: [String: Double]

    init(values: [String: Double] = [:]) {
        self.values = values
    }

    subscript(_ key: String) -> Double? {
        get { values[key] }
        set { values[key] = newValue }
    }

    func value(for definition: GimmickParameterDefinition) -> Double {
        min(max(values[definition.id] ?? definition.defaultValue, definition.range.lowerBound), definition.range.upperBound)
    }

    /// A stable snapshot for completed games and PGN tags. Gameplay still reads
    /// through `value(for:)`, which applies each rule's current bounds.
    var storedValues: [String: Double] { values }
}

/// The analysis facts a rating rule may use. Stage 2 will produce these without
/// delaying a commit; Stage 1 defines the stable input boundary now.
nonisolated struct GimmickMoveAnalysis: Codable, Hashable, Sendable {
    let bestMove: Move?
    let playedMove: Move?
    let bestScoreCentipawns: Int?
    let playedScoreCentipawns: Int?
    let centipawnTolerance: Int

    init(
        bestMove: Move? = nil,
        playedMove: Move? = nil,
        bestScoreCentipawns: Int? = nil,
        playedScoreCentipawns: Int? = nil,
        centipawnTolerance: Int = 0
    ) {
        self.bestMove = bestMove
        self.playedMove = playedMove
        self.bestScoreCentipawns = bestScoreCentipawns
        self.playedScoreCentipawns = playedScoreCentipawns
        self.centipawnTolerance = max(0, centipawnTolerance)
    }

    func marksAsBest(_ move: Move) -> Bool {
        if bestMove == move { return true }
        guard playedMove == move,
              let bestScoreCentipawns,
              let playedScoreCentipawns else { return false }
        return max(0, bestScoreCentipawns - playedScoreCentipawns) <= centipawnTolerance
    }
}

/// Immutable facts for a committed ply. Rules receive the board on both sides
/// of the move so capture, check, FEN, and analysis-driven mechanics do not need
/// to reach back into mutable session state.
nonisolated struct GimmickPly: Hashable, Sendable {
    let move: Move
    let movingPiece: Piece
    let positionBefore: Position
    let positionAfter: Position
    let ply: Int
    let wasCapture: Bool
    let givesCheck: Bool
    let analysis: GimmickMoveAnalysis?
    let playerColor: PieceColor
}

/// Stable facts available while a gimmick chooses an engine root move. The
/// random sample is derived by the session from the game seed and position, so
/// undoing to the same board produces the same choice.
nonisolated struct GimmickEngineContext: Hashable, Sendable {
    let playerColor: PieceColor
    let lastPlayerMove: Move?
    let randomSample: UInt64
    let engineTurn: Int
}

/// The complete gameplay boundary for one gimmick mode.
///
/// A new rating-based mode can live in one concrete rule: it owns its initial
/// board and rating, clamps, transition, engine move filter, and tunable values.
nonisolated protocol GimmickRule: Sendable {
    var startingRating: OpponentRating { get }
    var ratingBounds: ClosedRange<OpponentRating> { get }
    var startingPosition: Position { get }
    var parameterDefinitions: [GimmickParameterDefinition] { get }
    var defaultParameters: GimmickParameters { get }
    var requiresPlayerAnalysis: Bool { get }
    var requiresEngineAnalysis: Bool { get }

    func startingPosition(playerColor: PieceColor) -> Position

    /// A mode whose board is generated rather than written down receives the
    /// game's seed, so a restart and a resumed snapshot rebuild the same board
    /// instead of a new one.
    func startingPosition(playerColor: PieceColor, seed: UInt64) -> Position

    func rating(
        after ply: GimmickPly,
        currentRating: OpponentRating,
        parameters: GimmickParameters
    ) -> OpponentRating

    /// Filters the already legal, variant-aware root moves offered to the
    /// opponent. A rule cannot use this hook to manufacture a move.
    func allowedEngineMoves(
        in position: Position,
        candidates: [Move],
        context: GimmickEngineContext,
        parameters: GimmickParameters
    ) -> [Move]

    /// Selects from a coherent, ranked Stockfish snapshot. Returning nil uses
    /// the ordinary opponent path as a safe fallback.
    func selectEngineMove(
        from analysis: PositionAnalysis,
        context: GimmickEngineContext,
        parameters: GimmickParameters
    ) -> Move?

    /// TempoFish and ComboFish are the rules that can keep the player on move.
    ///
    /// Only those two can ever answer true. Replay skips its per-ply
    /// terminal-position scan for every other rule, which is what keeps
    /// opening a finished game instant.
    var canGrantBonusMoves: Bool { get }
    func grantsBonusMove(
        after ply: GimmickPly,
        completedPlayerTurns: Int,
        parameters: GimmickParameters
    ) -> Bool
}

extension GimmickRule {
    nonisolated var startingRating: OpponentRating { .maximum }
    nonisolated var ratingBounds: ClosedRange<OpponentRating> { .minimum ... .maximum }
    nonisolated var startingPosition: Position { .starting }
    nonisolated var parameterDefinitions: [GimmickParameterDefinition] { [] }
    nonisolated var defaultParameters: GimmickParameters { GimmickParameters() }
    nonisolated var requiresPlayerAnalysis: Bool { false }
    nonisolated var requiresEngineAnalysis: Bool { false }
    nonisolated var canGrantBonusMoves: Bool { false }

    nonisolated func startingPosition(playerColor: PieceColor) -> Position { startingPosition }

    nonisolated func startingPosition(playerColor: PieceColor, seed: UInt64) -> Position {
        startingPosition(playerColor: playerColor)
    }

    nonisolated func rating(
        after ply: GimmickPly,
        currentRating: OpponentRating,
        parameters: GimmickParameters
    ) -> OpponentRating {
        currentRating
    }

    nonisolated func allowedEngineMoves(
        in position: Position,
        candidates: [Move],
        context: GimmickEngineContext,
        parameters: GimmickParameters
    ) -> [Move] {
        candidates
    }

    nonisolated func selectEngineMove(
        from analysis: PositionAnalysis,
        context: GimmickEngineContext,
        parameters: GimmickParameters
    ) -> Move? {
        nil
    }

    nonisolated func grantsBonusMove(
        after ply: GimmickPly,
        completedPlayerTurns: Int,
        parameters: GimmickParameters
    ) -> Bool {
        false
    }
}

/// Existing modes keep their current board rules while adopting the gimmick
/// boundary. Their ratings are static until their catalogue replacements land.
nonisolated struct ExistingModeGimmickRule: GimmickRule {
}
