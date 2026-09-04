import Foundation

/// A score copied from Stockfish's structured callback. Scores are expressed
/// from the side-to-move's point of view in the analyzed root position.
nonisolated enum AnalysisScore: Codable, Hashable, Sendable {
    case centipawns(Int)
    case mate(plies: Int)
    case tablebase(distance: Int)

    var centipawns: Int? {
        guard case .centipawns(let value) = self else { return nil }
        return value
    }

    /// Player-relative fill for the Stage 4 tide. Ordinary scores ease toward
    /// the ends; forced mate and tablebase wins pin there explicitly.
    var playerEvaluationFraction: Double {
        switch self {
        case .centipawns(let value):
            return 0.5 + 0.46 * tanh(Double(value) / 600)
        case .mate(let plies):
            return plies >= 0 ? 0.98 : 0.02
        case .tablebase(let distance):
            if distance == 0 { return 0.5 }
            return distance > 0 ? 0.98 : 0.02
        }
    }
}

/// One ranked root move and its principal variation.
nonisolated struct AnalysisLine: Codable, Hashable, Sendable, Identifiable {
    var id: Int { rank }

    let rank: Int
    let depth: Int
    let selectiveDepth: Int
    let move: Move
    let score: AnalysisScore
    let principalVariation: [Move]
    let elapsedMilliseconds: UInt64
    let nodes: UInt64
    let nodesPerSecond: UInt64
    let tablebaseHits: UInt64
    let hashFull: Int
}

/// A coherent MultiPV snapshot for one immutable root position.
nonisolated struct PositionAnalysis: Codable, Hashable, Sendable {
    let position: Position
    let lines: [AnalysisLine]

    init(position: Position, lines: [AnalysisLine]) {
        self.position = position
        self.lines = lines.sorted { $0.rank < $1.rank }
    }

    var depth: Int { lines.map(\.depth).min() ?? 0 }
    var bestMove: Move? { lines.first(where: { $0.rank == 1 })?.move }
    var topFive: [AnalysisLine] { Array(lines.prefix(5)) }

    /// Classifies a move entirely from an already-delivered snapshot. There is
    /// deliberately no async fallback here: a move commit must never wait for
    /// Stockfish to catch up.
    func classification(
        for move: Move,
        toleranceCentipawns: Int
    ) -> MoveClassification? {
        guard let best = lines.first(where: { $0.rank == 1 }),
              let played = lines.first(where: { $0.move == move }) else {
            return nil
        }

        let tolerance = max(0, toleranceCentipawns)
        let loss: Int?
        let isBest: Bool
        if move == best.move {
            loss = 0
            isBest = true
        } else if let bestCP = best.score.centipawns,
                  let playedCP = played.score.centipawns {
            let measuredLoss = max(0, bestCP - playedCP)
            loss = measuredLoss
            isBest = measuredLoss <= tolerance
        } else {
            // Centipawn tolerance has no honest mapping across mate/tablebase
            // scores. Those moves are best only when Stockfish ranked them #1.
            loss = nil
            isBest = false
        }

        return MoveClassification(
            playedMove: move,
            bestMove: best.move,
            rank: played.rank,
            bestScore: best.score,
            playedScore: played.score,
            centipawnLoss: loss,
            toleranceCentipawns: tolerance,
            isBest: isBest
        )
    }

    func gimmickAnalysis(
        for move: Move,
        toleranceCentipawns: Int
    ) -> GimmickMoveAnalysis? {
        guard let classification = classification(
            for: move,
            toleranceCentipawns: toleranceCentipawns
        ) else { return nil }
        return GimmickMoveAnalysis(
            bestMove: classification.bestMove,
            playedMove: classification.playedMove,
            bestScoreCentipawns: classification.bestScore.centipawns,
            playedScoreCentipawns: classification.playedScore.centipawns,
            centipawnTolerance: classification.toleranceCentipawns
        )
    }
}

nonisolated struct MoveClassification: Codable, Hashable, Sendable {
    let playedMove: Move
    let bestMove: Move
    let rank: Int
    let bestScore: AnalysisScore
    let playedScore: AnalysisScore
    let centipawnLoss: Int?
    let toleranceCentipawns: Int
    let isBest: Bool

    var quality: MoveQuality {
        if isBest { return .best }
        if let centipawnLoss {
            switch centipawnLoss {
            case ...50: return .good
            case ...100: return .inaccuracy
            case ...200: return .mistake
            default: return .blunder
            }
        }

        // Mate and tablebase scores have no honest centipawn conversion. Rank
        // is still a stable engine fact and gives the review layer a useful,
        // conservative fallback without inventing precision.
        switch rank {
        case ...2: return .good
        case 3: return .inaccuracy
        case 4...5: return .mistake
        default: return .blunder
        }
    }
}

nonisolated enum MoveQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case best
    case good
    case inaccuracy
    case mistake
    case blunder

    var title: String { rawValue.capitalized }
}

nonisolated struct AnalysisRequest: Hashable, Sendable {
    let position: Position
    let allowedMoves: [Move]
    let targetDepth: Int
    /// Nil means depth-only analysis with no movetime cap.
    let maximumTime: Duration?
    /// Nil requests every allowed root move. This is how classification can
    /// score an arbitrary committed move while consumers display only `topFive`.
    let multiPV: Int?

    init(
        position: Position,
        allowedMoves: [Move],
        targetDepth: Int = 14,
        maximumTime: Duration? = .seconds(1),
        multiPV: Int? = nil
    ) {
        self.position = position
        self.allowedMoves = allowedMoves
        self.targetDepth = min(max(targetDepth, 1), 64)
        self.maximumTime = maximumTime.map { max($0, .milliseconds(50)) }
        self.multiPV = multiPV.map { min(max($0, 1), 256) }
    }

    var requestedLineCount: Int {
        min(multiPV ?? allowedMoves.count, allowedMoves.count)
    }
}

/// Optional capability of an opponent backed by an analysis engine. Returning
/// a stream makes depth-by-depth updates useful to Stage 4 without exposing the
/// engine callback or forcing the game session to await a result.
nonisolated protocol ChessAnalysisService: Sendable {
    func analysisUpdates(for request: AnalysisRequest) async -> AsyncStream<PositionAnalysis>
    func cancelAnalysis() async
}
