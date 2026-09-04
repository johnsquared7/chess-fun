import Foundation

/// The public think-time choices from Oddfish's analysis control surface.
/// `noCap` deliberately maps to `nil`: Stockfish then searches to the selected
/// depth without a hidden movetime limit.
nonisolated public enum AnalysisTimeLimit: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case oneSecond
    case threeSeconds
    case fiveSeconds
    case tenSeconds
    case twentySeconds
    case fortyFiveSeconds
    case ninetySeconds
    case noCap

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .oneSecond: "1 second"
        case .threeSeconds: "3 seconds"
        case .fiveSeconds: "5 seconds"
        case .tenSeconds: "10 seconds"
        case .twentySeconds: "20 seconds"
        case .fortyFiveSeconds: "45 seconds"
        case .ninetySeconds: "1 min 30 sec"
        case .noCap: "No cap"
        }
    }

    var shortTitle: String {
        switch self {
        case .oneSecond: "1s"
        case .threeSeconds: "3s"
        case .fiveSeconds: "5s"
        case .tenSeconds: "10s"
        case .twentySeconds: "20s"
        case .fortyFiveSeconds: "45s"
        case .ninetySeconds: "1m 30s"
        case .noCap: "No cap"
        }
    }

    var duration: Duration? {
        switch self {
        case .oneSecond: .seconds(1)
        case .threeSeconds: .seconds(3)
        case .fiveSeconds: .seconds(5)
        case .tenSeconds: .seconds(10)
        case .twentySeconds: .seconds(20)
        case .fortyFiveSeconds: .seconds(45)
        case .ninetySeconds: .seconds(90)
        case .noCap: nil
        }
    }
}

/// Settings that affect the presentation of a game, rather than its rules.
///
/// The type is deliberately independent from SwiftUI and from the chess
/// engine so it can be persisted and used by previews and tests.
nonisolated public struct AppSettings: Codable, Hashable, Sendable {
    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    public var showLegalMoves: Bool
    public var autoQueen: Bool
    /// The side used when a new game is created. The active session owns its
    /// own copy so changing sides can restart cleanly without mutating a board.
    public var playAsBlack: Bool
    /// Sparse by design: a mode with no saved override uses its rule's declared
    /// starting rating.
    public var modeRatings: [String: OpponentRating]
    /// Sparse values for each mode's own controls.
    var modeParameters: [String: GimmickParameters]
    /// How far a move may trail Stockfish's first line and still count as best.
    public var bestMoveToleranceCentipawns: Int {
        didSet {
            bestMoveToleranceCentipawns = min(max(bestMoveToleranceCentipawns, 0), 500)
        }
    }
    public var guideChattiness: GuideChattiness
    /// Master switch for player-visible engine assistance. It defaults off so
    /// a new game can still qualify for the three-crown integrity tier.
    public var evaluationEnabled: Bool
    public var analysisDepth: Int {
        didSet {
            analysisDepth = min(max((analysisDepth / 2) * 2, 10), 28)
        }
    }
    public var analysisTimeLimit: AnalysisTimeLimit
    public var showEvaluationBar: Bool
    public var showMoveRanks: Bool
    public var showMoveAnalysis: Bool
    /// Runs one hidden predictive line on the player's turn when the visible
    /// evaluation layer is off. The search also warms Stockfish's shared TT.
    public var ponderEnabled: Bool

    // MARK: Appearance
    public var boardThemeID: String
    public var pieceSet: PieceSet
    public var pieceStyle: PieceStyle
    public var showsCoordinates: Bool
    public var highlightsLastMove: Bool

    public init(
        soundEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        showLegalMoves: Bool = true,
        autoQueen: Bool = false,
        playAsBlack: Bool = false,
        modeRatings: [String: OpponentRating] = [:],
        bestMoveToleranceCentipawns: Int = 25,
        guideChattiness: GuideChattiness = .full,
        evaluationEnabled: Bool = false,
        analysisDepth: Int = 14,
        analysisTimeLimit: AnalysisTimeLimit = .oneSecond,
        showEvaluationBar: Bool = true,
        showMoveRanks: Bool = true,
        showMoveAnalysis: Bool = true,
        ponderEnabled: Bool = false,
        boardThemeID: String = AppSettings.defaultBoardThemeID,
        pieceSet: PieceSet = .caliente,
        pieceStyle: PieceStyle = .carved,
        showsCoordinates: Bool = true,
        highlightsLastMove: Bool = true
    ) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.showLegalMoves = showLegalMoves
        self.autoQueen = autoQueen
        self.playAsBlack = playAsBlack
        self.modeRatings = modeRatings
        self.modeParameters = [:]
        self.bestMoveToleranceCentipawns = min(max(bestMoveToleranceCentipawns, 0), 500)
        self.guideChattiness = guideChattiness
        self.evaluationEnabled = evaluationEnabled
        self.analysisDepth = min(max((analysisDepth / 2) * 2, 10), 28)
        self.analysisTimeLimit = analysisTimeLimit
        self.showEvaluationBar = showEvaluationBar
        self.showMoveRanks = showMoveRanks
        self.showMoveAnalysis = showMoveAnalysis
        self.ponderEnabled = ponderEnabled
        self.boardThemeID = boardThemeID
        self.pieceSet = pieceSet
        self.pieceStyle = pieceStyle
        self.showsCoordinates = showsCoordinates
        self.highlightsLastMove = highlightsLastMove
    }

    /// A default *argument* is part of the public interface, so it cannot name
    /// the internal `BoardTheme`. The value still comes from the theme itself,
    /// so the two cannot drift apart.
    public static let defaultBoardThemeID: String = BoardTheme.midnight.id

    public static let `default` = AppSettings()

    /// Resolved rather than stored, so an invalid identifier lands on the default.
    var boardTheme: BoardTheme { BoardTheme.theme(id: boardThemeID) }

    public var boardDecoration: BoardDecoration {
        BoardDecoration(
            showsCoordinates: showsCoordinates,
            highlightsLastMove: highlightsLastMove
        )
    }

    func rating(for mode: GameMode, default defaultRating: OpponentRating = .default) -> OpponentRating {
        modeRatings[mode.rawValue] ?? defaultRating
    }

    mutating func setRating(_ rating: OpponentRating, for mode: GameMode) {
        modeRatings[mode.rawValue] = rating
    }

    func parameters(for mode: GameMode, default defaultParameters: GimmickParameters) -> GimmickParameters {
        modeParameters[mode.rawValue] ?? defaultParameters
    }

    mutating func setParameter(_ value: Double, definition: GimmickParameterDefinition, for mode: GameMode) {
        var parameters = modeParameters[mode.rawValue] ?? GimmickParameters()
        parameters[definition.id] = min(max(value, definition.range.lowerBound), definition.range.upperBound)
        modeParameters[mode.rawValue] = parameters
    }

    var playerColor: PieceColor { playAsBlack ? .black : .white }
}
