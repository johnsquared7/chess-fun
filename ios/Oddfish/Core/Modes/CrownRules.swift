import Foundation

/// The value a mode treats as its leaderboard score.
nonisolated public enum CrownScoreMetric: String, Codable, Hashable, Sendable {
    case opponentElo
    case eloLostPerBestMove
    case eloLostPerCheck
    case eloLostPerEngineMove
    case eloLostPerPiece
    case eloGainedPerThreat
    case eloGainedPerEngineMove
    case eloGainedPerMaterialPoint
    case eloGainedPerPiece
    case bonusInterval
    case blunderChance

    var higherIsBetter: Bool {
        switch self {
        case .eloLostPerBestMove, .eloLostPerCheck, .eloLostPerEngineMove,
             .eloLostPerPiece, .blunderChance:
            false
        case .opponentElo, .eloGainedPerThreat, .eloGainedPerEngineMove,
             .eloGainedPerMaterialPoint, .eloGainedPerPiece, .bonusInterval:
            true
        }
    }

    var label: String {
        switch self {
        case .opponentElo: "Elo beaten"
        case .eloLostPerBestMove: "Elo lost per best move"
        case .eloLostPerCheck: "Elo lost per check"
        case .eloLostPerEngineMove: "Elo lost per engine move"
        case .eloLostPerPiece: "Elo lost per piece"
        case .eloGainedPerThreat: "Elo gained per capture or check"
        case .eloGainedPerEngineMove: "Elo gained per engine move"
        case .eloGainedPerMaterialPoint: "Elo gained per point behind"
        case .eloGainedPerPiece: "Elo gained per piece"
        case .bonusInterval: "Bonus interval"
        case .blunderChance: "Blunder chance"
        }
    }

    func formatted(value: Int) -> String {
        switch self {
        case .opponentElo:
            "\(value) Elo"
        case .eloLostPerBestMove, .eloLostPerCheck, .eloLostPerEngineMove,
             .eloLostPerPiece, .eloGainedPerThreat, .eloGainedPerEngineMove,
             .eloGainedPerMaterialPoint, .eloGainedPerPiece:
            "\(value) Elo"
        case .bonusInterval:
            "Every \(value) turns"
        case .blunderChance:
            "\(value)%"
        }
    }
}

nonisolated public struct CrownScore: Codable, Hashable, Sendable {
    let value: Int
    let metric: CrownScoreMetric

    var higherIsBetter: Bool { metric.higherIsBetter }
    var formatted: String { metric.formatted(value: value) }

    func isBetter(than other: CrownScore) -> Bool {
        guard metric == other.metric else { return false }
        return higherIsBetter ? value > other.value : value < other.value
    }
}

nonisolated public struct CrownAward: Codable, Hashable, Sendable {
    let tier: Int
    let score: CrownScore

    init(tier: Int, score: CrownScore) {
        self.tier = min(max(tier, 1), 3)
        self.score = score
    }
}

/// A mode's immutable competitive contract. The named gimmicks mirror the
/// reference site's checkmate, starting-Elo, and score rules. Oddfish's three
/// original variants use the Classic contract: any starting Elo, scored by the
/// opponent Elo beaten.
nonisolated struct CrownRule: Hashable, Sendable {
    let requiredStartingRating: OpponentRating?
    let metric: CrownScoreMetric

    var startingRequirementText: String {
        if let requiredStartingRating {
            "Start at exactly \(requiredStartingRating.rawValue) Elo"
        } else {
            "Any starting Elo counts"
        }
    }

    var scoreDescription: String {
        let direction = metric.higherIsBetter ? "higher is better" : "lower is better"
        return "\(metric.label) · \(direction)"
    }

    func accepts(_ rating: OpponentRating) -> Bool {
        requiredStartingRating == nil || requiredStartingRating == rating
    }
}

extension GameMode {
    nonisolated var crownRule: CrownRule {
        switch self {
        case .rattleFish:
            CrownRule(requiredStartingRating: .maximum, metric: .eloLostPerBestMove)
        case .flinchFish:
            CrownRule(requiredStartingRating: .maximum, metric: .eloLostPerCheck)
        case .fadeFish:
            CrownRule(requiredStartingRating: .maximum, metric: .eloLostPerEngineMove)
        case .mopeFish:
            CrownRule(requiredStartingRating: .maximum, metric: .eloLostPerPiece)
        case .gluttonFish:
            CrownRule(requiredStartingRating: .minimum, metric: .eloGainedPerThreat)
        case .babyFish:
            CrownRule(requiredStartingRating: .minimum, metric: .eloGainedPerEngineMove)
        case .comebackFish:
            CrownRule(requiredStartingRating: .minimum, metric: .eloGainedPerMaterialPoint)
        case .lastStandFish:
            CrownRule(requiredStartingRating: .minimum, metric: .eloGainedPerPiece)
        case .tempoFish:
            CrownRule(requiredStartingRating: .maximum, metric: .bonusInterval)
        case .fumbleFish:
            CrownRule(requiredStartingRating: .maximum, metric: .blunderChance)
        // Restfish has no tunable value to score, so a crown is scored by the
        // Elo it was won against like the rest of its group — but it is only
        // awarded from the top of the dial. Every Restfish crown therefore
        // carries the same 3600, which makes the crown a pass mark rather than
        // a ranking. That is the deliberate contract, not an oversight.
        case .restfish:
            CrownRule(requiredStartingRating: .maximum, metric: .opponentElo)
        case .classic, .levelFish, .mimicFish, .dwindleFish,
             .throneFish, .chapelFish, .stableFish,
             .fortressFish, .royalFish, .pacifish, .piranhaFish, .moodSwingFish,
             .pawnFish, .revengeFish, .contraryFish, .comboFish,
             .upstreamFish, .shuffleFish:
            CrownRule(requiredStartingRating: nil, metric: .opponentElo)
        }
    }

    nonisolated func crownScore(
        startingRating: OpponentRating,
        parameters: GimmickParameters
    ) -> CrownScore {
        let rule = crownRule
        let value: Int
        switch rule.metric {
        case .opponentElo:
            value = startingRating.rawValue
        case .eloLostPerBestMove, .eloLostPerCheck, .eloLostPerEngineMove,
             .eloLostPerPiece, .eloGainedPerThreat, .eloGainedPerEngineMove,
             .eloGainedPerMaterialPoint, .eloGainedPerPiece:
            value = parameterValue(GimmickParameterKey.amount, parameters: parameters)
        case .bonusInterval:
            value = parameterValue(GimmickParameterKey.cycle, parameters: parameters)
        case .blunderChance:
            value = parameterValue(GimmickParameterKey.chance, parameters: parameters)
        }
        return CrownScore(value: value, metric: rule.metric)
    }

    nonisolated func crownAward(
        wonByCheckmate: Bool,
        startingRating: OpponentRating,
        parameters: GimmickParameters,
        integrity: GameIntegrity,
        isImported: Bool = false
    ) -> CrownAward? {
        guard wonByCheckmate, !isImported, crownRule.accepts(startingRating) else { return nil }
        return CrownAward(
            tier: integrity.maximumCrownTier,
            score: crownScore(startingRating: startingRating, parameters: parameters)
        )
    }

    nonisolated func personalBestVariant(parameters: GimmickParameters) -> String? {
        guard self == .gluttonFish,
              let definition = gimmickRule.parameterDefinitions.first(where: { $0.id == GimmickParameterKey.hardMode }) else {
            return nil
        }
        return parameters.value(for: definition) >= 0.5 ? "hard" : "standard"
    }

    private nonisolated func parameterValue(_ key: String, parameters: GimmickParameters) -> Int {
        guard let definition = gimmickRule.parameterDefinitions.first(where: { $0.id == key }) else { return 0 }
        return Int(parameters.value(for: definition).rounded())
    }
}
