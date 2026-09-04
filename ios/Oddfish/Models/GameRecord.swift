import Foundation

/// The outcome stored in history. It intentionally does not reference the
/// chess engine's outcome type, allowing history to outlive engine changes.
nonisolated public enum GameResult: String, Codable, Hashable, Sendable, CaseIterable {
    case win
    case loss
    case draw
    case abandoned
    case unknown

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case Self.win.rawValue: self = .win
        case Self.loss.rawValue: self = .loss
        case Self.draw.rawValue: self = .draw
        case Self.abandoned.rawValue: self = .abandoned
        default: self = .unknown
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try? container.decode(String.self)
        self.init(rawValue: value ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated public enum GameRecordOrigin: String, Codable, Hashable, Sendable {
    case played
    case imported
}

/// A compact, immutable summary of one completed game.
nonisolated public struct GameRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let modeID: String
    public let result: GameResult
    public let duration: TimeInterval
    public let moveCount: Int
    public let date: Date
    /// Standard Algebraic Notation for played and imported records.
    public let notation: String?
    public let startingFEN: String?
    public let playerColorID: String
    public let startingRating: Int?
    public let endingRating: Int?
    public let origin: GameRecordOrigin
    let award: CrownAward?
    let personalBestVariant: String?
    let parameterValues: [String: Double]

    public init(
        id: UUID = UUID(),
        modeID: String,
        result: GameResult,
        duration: TimeInterval,
        moveCount: Int,
        date: Date = Date(),
        notation: String? = nil,
        startingFEN: String? = nil,
        playerColorID: String = "white",
        startingRating: Int? = nil,
        endingRating: Int? = nil,
        origin: GameRecordOrigin = .played,
        award: CrownAward? = nil,
        personalBestVariant: String? = nil,
        parameterValues: [String: Double] = [:]
    ) {
        self.id = id
        self.modeID = modeID
        self.result = result
        self.duration = max(0, duration)
        self.moveCount = max(0, moveCount)
        self.date = date
        self.notation = notation
        self.startingFEN = startingFEN
        self.playerColorID = playerColorID
        self.startingRating = startingRating
        self.endingRating = endingRating
        self.origin = origin
        self.award = origin == .imported ? nil : award
        self.personalBestVariant = personalBestVariant
        self.parameterValues = parameterValues
    }

    /// Convenience for callers that receive a result from a text boundary.
    public init(
        id: UUID = UUID(),
        modeID: String,
        result: String,
        duration: TimeInterval,
        moveCount: Int,
        date: Date = Date(),
        notation: String? = nil,
        startingFEN: String? = nil,
        playerColorID: String = "white",
        startingRating: Int? = nil,
        endingRating: Int? = nil,
        origin: GameRecordOrigin = .played,
        award: CrownAward? = nil,
        personalBestVariant: String? = nil,
        parameterValues: [String: Double] = [:]
    ) {
        self.init(
            id: id,
            modeID: modeID,
            result: GameResult(rawValue: result),
            duration: duration,
            moveCount: moveCount,
            date: date,
            notation: notation,
            startingFEN: startingFEN,
            playerColorID: playerColorID,
            startingRating: startingRating,
            endingRating: endingRating,
            origin: origin,
            award: award,
            personalBestVariant: personalBestVariant,
            parameterValues: parameterValues
        )
    }

    public var isImported: Bool { origin == .imported }
    public var crownTier: Int? { award?.tier }
    var score: CrownScore? { award?.score }
    var playerColor: PieceColor { PieceColor(rawValue: playerColorID) ?? .white }
    var startingPosition: Position { startingFEN.flatMap(Position.init(fen:)) ?? .starting }
    var parameters: GimmickParameters { GimmickParameters(values: parameterValues) }
    var personalBestID: String {
        [modeID, personalBestVariant].compactMap { $0 }.joined(separator: ":")
    }

}

/// Aggregate counters shown on the home and history screens.
nonisolated public struct PlayerStats: Codable, Hashable, Sendable {
    public private(set) var gamesPlayed: Int
    public private(set) var wins: Int
    public private(set) var losses: Int
    public private(set) var draws: Int

    public init(gamesPlayed: Int = 0, wins: Int = 0, losses: Int = 0, draws: Int = 0) {
        self.gamesPlayed = max(0, gamesPlayed)
        self.wins = max(0, wins)
        self.losses = max(0, losses)
        self.draws = max(0, draws)
    }

    public var winRate: Double {
        guard gamesPlayed > 0 else { return 0 }
        return Double(wins) / Double(gamesPlayed)
    }

    mutating func record(_ result: GameResult) {
        gamesPlayed += 1
        switch result {
        case .win: wins += 1
        case .loss: losses += 1
        case .draw: draws += 1
        case .abandoned, .unknown: break
        }
    }

}
