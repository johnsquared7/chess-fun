import Foundation

nonisolated enum GimmickParameterKey {
    static let amount = "amount"
    static let tolerance = "tolerance"
    static let cycle = "cycle"
    static let chance = "chance"
    static let hardMode = "hard-mode"
}

nonisolated private func configuredInt(
    _ key: String,
    definitions: [GimmickParameterDefinition],
    parameters: GimmickParameters
) -> Int {
    guard let definition = definitions.first(where: { $0.id == key }) else { return 0 }
    return Int(parameters.value(for: definition).rounded())
}

nonisolated private func adjusted(
    _ rating: OpponentRating,
    by amount: Int,
    bounds: ClosedRange<OpponentRating>
) -> OpponentRating {
    rating.adjusted(by: amount).clamped(to: bounds)
}

nonisolated struct RattleFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.amount, title: "Elo lost", range: 50...500, step: 50, defaultValue: 100),
        GimmickParameterDefinition(id: GimmickParameterKey.tolerance, title: "Best-move tolerance", range: 0...100, step: 5, defaultValue: 10)
    ]
    var requiresPlayerAnalysis: Bool { true }

    func rating(after ply: GimmickPly, currentRating: OpponentRating, parameters: GimmickParameters) -> OpponentRating {
        guard ply.movingPiece.color == ply.playerColor,
              ply.analysis?.marksAsBest(ply.move) == true else { return currentRating }
        return adjusted(currentRating, by: -configuredInt(GimmickParameterKey.amount, definitions: parameterDefinitions, parameters: parameters), bounds: ratingBounds)
    }
}

nonisolated struct FlinchFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.amount, title: "Elo lost", range: 100...1_000, step: 100, defaultValue: 300)
    ]

    func rating(after ply: GimmickPly, currentRating: OpponentRating, parameters: GimmickParameters) -> OpponentRating {
        guard ply.movingPiece.color == ply.playerColor, ply.givesCheck else { return currentRating }
        return adjusted(currentRating, by: -configuredInt(GimmickParameterKey.amount, definitions: parameterDefinitions, parameters: parameters), bounds: ratingBounds)
    }
}

nonisolated struct FadeFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.amount, title: "Elo lost per move", range: 10...200, step: 10, defaultValue: 50)
    ]

    func rating(after ply: GimmickPly, currentRating: OpponentRating, parameters: GimmickParameters) -> OpponentRating {
        guard ply.movingPiece.color != ply.playerColor else { return currentRating }
        return adjusted(currentRating, by: -configuredInt(GimmickParameterKey.amount, definitions: parameterDefinitions, parameters: parameters), bounds: ratingBounds)
    }
}

nonisolated struct MopeFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.amount, title: "Elo lost per piece", range: 50...500, step: 50, defaultValue: 200)
    ]

    func rating(after ply: GimmickPly, currentRating: OpponentRating, parameters: GimmickParameters) -> OpponentRating {
        guard ply.movingPiece.color == ply.playerColor, ply.wasCapture else { return currentRating }
        return adjusted(currentRating, by: -configuredInt(GimmickParameterKey.amount, definitions: parameterDefinitions, parameters: parameters), bounds: ratingBounds)
    }
}

nonisolated struct GluttonFishRule: GimmickRule {
    let startingRating = OpponentRating.minimum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.amount, title: "Elo gained", range: 100...2_000, step: 100, defaultValue: 1_000),
        GimmickParameterDefinition(id: GimmickParameterKey.hardMode, title: "Prioritize threats", range: 0...1, defaultValue: 0)
    ]

    func rating(after ply: GimmickPly, currentRating: OpponentRating, parameters: GimmickParameters) -> OpponentRating {
        guard ply.movingPiece.color != ply.playerColor, ply.wasCapture || ply.givesCheck else { return currentRating }
        return adjusted(currentRating, by: configuredInt(GimmickParameterKey.amount, definitions: parameterDefinitions, parameters: parameters), bounds: ratingBounds)
    }

    func allowedEngineMoves(in position: Position, candidates: [Move], context: GimmickEngineContext, parameters: GimmickParameters) -> [Move] {
        guard configuredInt(GimmickParameterKey.hardMode, definitions: parameterDefinitions, parameters: parameters) == 1 else { return candidates }
        let forcing = candidates.filter { move in
            guard let next = ChessEngine.apply(move, to: position) else { return false }
            return move.isCapture || ChessEngine.isInCheck(next.sideToMove, in: next)
        }
        return forcing.isEmpty ? candidates : forcing
    }
}

nonisolated struct BabyFishRule: GimmickRule {
    let startingRating = OpponentRating.minimum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.amount, title: "Elo gained per move", range: 50...500, step: 50, defaultValue: 100)
    ]

    func rating(after ply: GimmickPly, currentRating: OpponentRating, parameters: GimmickParameters) -> OpponentRating {
        guard ply.movingPiece.color != ply.playerColor else { return currentRating }
        return adjusted(currentRating, by: configuredInt(GimmickParameterKey.amount, definitions: parameterDefinitions, parameters: parameters), bounds: ratingBounds)
    }
}

nonisolated struct TempoFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    let canGrantBonusMoves = true
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.cycle, title: "Bonus every", range: 2...12, defaultValue: 5)
    ]

    func grantsBonusMove(after ply: GimmickPly, completedPlayerTurns: Int, parameters: GimmickParameters) -> Bool {
        guard ply.movingPiece.color == ply.playerColor, !ply.givesCheck else { return false }
        let cycle = configuredInt(GimmickParameterKey.cycle, definitions: parameterDefinitions, parameters: parameters)
        return cycle > 0 && completedPlayerTurns.isMultiple(of: cycle)
    }
}

/// The piece family the player's last move belongs to. Bishops and knights
/// share one drawer, which is what keeps MimicFish and ContraryFish exact
/// opposites: if moving a bishop only banned bishops, the obvious contrary
/// answer would be a knight.
nonisolated private func movedFamily(in position: Position, lastPlayerMove: Move?) -> Set<PieceKind>? {
    guard let lastPlayerMove else { return nil }
    // A promotion leaves a queen on the destination square, but the piece the
    // player actually moved was a pawn — read that.
    let movedKind = lastPlayerMove.promotion != nil
        ? PieceKind.pawn
        : position.piece(at: lastPlayerMove.to)?.kind
    guard let movedKind else { return nil }
    return movedKind == .bishop || movedKind == .knight ? [.bishop, .knight] : [movedKind]
}

nonisolated struct MimicFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func allowedEngineMoves(in position: Position, candidates: [Move], context: GimmickEngineContext, parameters: GimmickParameters) -> [Move] {
        guard let family = movedFamily(in: position, lastPlayerMove: context.lastPlayerMove) else { return candidates }
        let matching = candidates.filter { move in
            guard let piece = position.piece(at: move.from) else { return false }
            return family.contains(piece.kind)
        }
        return matching.isEmpty ? candidates : matching
    }
}

nonisolated struct ChapelFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func startingPosition(playerColor: PieceColor) -> Position {
        let fen = playerColor == .white
            ? "bbbbkbbb/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1"
            : "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/BBBBKBBB w kq - 0 1"
        return Position(fen: fen) ?? .starting
    }
}

nonisolated struct StableFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func startingPosition(playerColor: PieceColor) -> Position {
        let fen = playerColor == .white
            ? "nnnnknnn/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1"
            : "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/NNNNKNNN w kq - 0 1"
        return Position(fen: fen) ?? .starting
    }
}

nonisolated struct ThroneFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
}

nonisolated struct LevelFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    var requiresEngineAnalysis: Bool { true }

    func selectEngineMove(from analysis: PositionAnalysis, context: GimmickEngineContext, parameters: GimmickParameters) -> Move? {
        analysis.lines.min { drawDistance($0.score) < drawDistance($1.score) }?.move
    }

    private func drawDistance(_ score: AnalysisScore) -> Int {
        switch score {
        case .centipawns(let value): abs(value)
        case .mate(let plies): 100_000 - min(abs(plies), 10_000)
        case .tablebase(let distance): distance == 0 ? 0 : 90_000 - min(abs(distance), 10_000)
        }
    }
}

nonisolated struct FumbleFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.chance, title: "Blunder chance", range: 0...100, defaultValue: 5)
    ]
    var requiresEngineAnalysis: Bool { true }

    func selectEngineMove(from analysis: PositionAnalysis, context: GimmickEngineContext, parameters: GimmickParameters) -> Move? {
        let chance = configuredInt(GimmickParameterKey.chance, definitions: parameterDefinitions, parameters: parameters)
        let shouldBlunder = Int(context.randomSample % 100) < chance
        return shouldBlunder ? analysis.lines.max(by: { $0.rank < $1.rank })?.move : analysis.bestMove
    }
}

nonisolated struct DwindleFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    var requiresEngineAnalysis: Bool { true }

    func selectEngineMove(from analysis: PositionAnalysis, context: GimmickEngineContext, parameters: GimmickParameters) -> Move? {
        guard !analysis.lines.isEmpty else { return nil }
        let index = min(context.randomSample.trailingZeroBitCount, analysis.lines.count - 1)
        return analysis.lines[index].move
    }
}

// MARK: - First themed pack

/// Rooks keep their corners, so unlike ChapelFish and StableFish this army has
/// not lost the right to castle. The rank is blocked at move one and clears
/// into a genuine option later, which is the whole point of the mode.
nonisolated struct FortressFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func startingPosition(playerColor: PieceColor) -> Position {
        let fen = playerColor == .white
            ? "rrrrkrrr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
            : "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RRRRKRRR w KQkq - 0 1"
        return Position(fen: fen) ?? .starting
    }
}

nonisolated struct RoyalFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func startingPosition(playerColor: PieceColor) -> Position {
        let fen = playerColor == .white
            ? "qqqqkqqq/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1"
            : "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/QQQQKQQQ w kq - 0 1"
        return Position(fen: fen) ?? .starting
    }
}

/// Quiet moves only, while any quiet move exists. The fallback is what keeps
/// this a preference rather than an illegal-move generator: a position whose
/// every legal reply is a capture still gets played.
nonisolated struct PacifishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func allowedEngineMoves(in position: Position, candidates: [Move], context: GimmickEngineContext, parameters: GimmickParameters) -> [Move] {
        let quiet = candidates.filter { !$0.isCapture }
        return quiet.isEmpty ? candidates : quiet
    }
}

nonisolated struct PiranhaFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func allowedEngineMoves(in position: Position, candidates: [Move], context: GimmickEngineContext, parameters: GimmickParameters) -> [Move] {
        let captures = candidates.filter(\.isCapture)
        return captures.isEmpty ? candidates : captures
    }
}

/// A rubber band, not a ratchet.
///
/// The rating tracks the material gap rather than accumulating per capture, so
/// winning a piece back relaxes it again. Expressing that as the change in
/// deficit across the ply — instead of an absolute mapping — keeps the rule
/// relative like every other one here, so a player who raises the starting Elo
/// in Settings does not have it snapped away on the first move. Promotions move
/// the gap too, and are handled by the same arithmetic.
nonisolated struct ComebackFishRule: GimmickRule {
    let startingRating = OpponentRating.minimum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.amount, title: "Elo per point behind", range: 50...500, step: 50, defaultValue: 250)
    ]

    func rating(after ply: GimmickPly, currentRating: OpponentRating, parameters: GimmickParameters) -> OpponentRating {
        let before = deficit(in: ply.positionBefore, playerColor: ply.playerColor)
        let after = deficit(in: ply.positionAfter, playerColor: ply.playerColor)
        guard after != before else { return currentRating }
        let perPoint = configuredInt(GimmickParameterKey.amount, definitions: parameterDefinitions, parameters: parameters)
        return adjusted(currentRating, by: (after - before) * perPoint, bounds: ratingBounds)
    }

    /// How far behind the opponent is, in whole pawns. A lead of its own is
    /// worth nothing: this fish is only fed by yours.
    private func deficit(in position: Position, playerColor: PieceColor) -> Int {
        max(0, position.materialBalance(for: playerColor))
    }
}

/// Deliberately deterministic. FumbleFish hides its miss behind a dice roll;
/// this one announces the pattern and dares the player to count turns.
nonisolated struct MoodSwingFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    var requiresEngineAnalysis: Bool { true }

    func selectEngineMove(from analysis: PositionAnalysis, context: GimmickEngineContext, parameters: GimmickParameters) -> Move? {
        context.engineTurn.isMultiple(of: 2)
            ? analysis.bestMove
            : analysis.lines.max(by: { $0.rank < $1.rank })?.move
    }
}

// MARK: - Second wave

/// The weakest army in the catalogue and the only one that cannot develop: at
/// move one every back-rank pawn is blocked by the pawn in front of it, and the
/// rank clears only as those pawns advance. There are no rooks, so castling is
/// not offered.
nonisolated struct PawnFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func startingPosition(playerColor: PieceColor) -> Position {
        let fen = playerColor == .white
            ? "ppppkppp/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1"
            : "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/PPPPKPPP w kq - 0 1"
        return Position(fen: fen) ?? .starting
    }
}

/// PiranhaFish demands any capture; this one demands a particular square. The
/// fallback is what keeps it a preference rather than an illegal-move
/// generator: when no legal recapture exists, the whole candidate list stands.
nonisolated struct RevengeFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func allowedEngineMoves(in position: Position, candidates: [Move], context: GimmickEngineContext, parameters: GimmickParameters) -> [Move] {
        guard let lastPlayerMove = context.lastPlayerMove, lastPlayerMove.isCapture else { return candidates }
        // An en-passant capture leaves the capturing pawn on `to` even though
        // the piece it took stood elsewhere, and `to` is still the square the
        // answer has to come to.
        let recaptures = candidates.filter { $0.isCapture && $0.to == lastPlayerMove.to }
        return recaptures.isEmpty ? candidates : recaptures
    }
}

/// MimicFish read backwards, sharing its notion of a piece family so the two
/// modes stay opposites rather than near-neighbours.
nonisolated struct ContraryFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func allowedEngineMoves(in position: Position, candidates: [Move], context: GimmickEngineContext, parameters: GimmickParameters) -> [Move] {
        guard let family = movedFamily(in: position, lastPlayerMove: context.lastPlayerMove) else { return candidates }
        let differing = candidates.filter { move in
            guard let piece = position.piece(at: move.from) else { return false }
            return !family.contains(piece.kind)
        }
        return differing.isEmpty ? candidates : differing
    }
}

/// One extra move, not a chain. The session refuses to let a bonus move earn
/// another, which is the only thing standing between this mode and a player who
/// captures their way through an entire army in one turn.
nonisolated struct ComboFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
    let canGrantBonusMoves = true

    func grantsBonusMove(after ply: GimmickPly, completedPlayerTurns: Int, parameters: GimmickParameters) -> Bool {
        ply.movingPiece.color == ply.playerColor && ply.wasCapture && !ply.givesCheck
    }
}

/// MopeFish inverted: the same event, the opposite sign, read from the bottom
/// of the dial instead of the top. Every trade you win makes the next one
/// harder, so the cheap path to a crown is a checkmate with the army intact.
nonisolated struct LastStandFishRule: GimmickRule {
    let startingRating = OpponentRating.minimum
    let parameterDefinitions = [
        GimmickParameterDefinition(id: GimmickParameterKey.amount, title: "Elo gained per piece", range: 50...500, step: 50, defaultValue: 200)
    ]

    func rating(after ply: GimmickPly, currentRating: OpponentRating, parameters: GimmickParameters) -> OpponentRating {
        guard ply.movingPiece.color == ply.playerColor, ply.wasCapture else { return currentRating }
        return adjusted(currentRating, by: configuredInt(GimmickParameterKey.amount, definitions: parameterDefinitions, parameters: parameters), bounds: ratingBounds)
    }
}

/// The board rule lives in `VariantRules`, because like Restfish it binds both
/// armies rather than handicapping one. This type exists so the mode still owns
/// a rating and has somewhere to grow parameters later.
nonisolated struct UpstreamFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum
}

/// The one mode whose board is generated rather than written down, which is why
/// it takes the game's seed: a restart and a resumed snapshot have to rebuild
/// the same back rank, not roll a new one.
nonisolated struct ShuffleFishRule: GimmickRule {
    let startingRating = OpponentRating.maximum

    func startingPosition(playerColor: PieceColor) -> Position {
        startingPosition(playerColor: playerColor, seed: 0)
    }

    func startingPosition(playerColor: PieceColor, seed: UInt64) -> Position {
        let rank = Self.shuffledBackRank(seed: seed)
        let fen = playerColor == .white
            ? "\(rank)/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1"
            : "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/\(rank.uppercased()) w kq - 0 1"
        return Position(fen: fen) ?? .starting
    }

    /// Seven pieces permuted by a seeded Fisher-Yates and reassembled around a
    /// king that never leaves the e-file. Castling is not offered, because the
    /// rooks are rarely where the right would assume they are.
    static func shuffledBackRank(seed: UInt64) -> String {
        var pieces: [Character] = ["r", "n", "b", "q", "b", "n", "r"]
        var state = seed
        for index in stride(from: pieces.count - 1, to: 0, by: -1) {
            pieces.swapAt(index, Int(next(&state) % UInt64(index + 1)))
        }
        pieces.insert("k", at: 4)
        return String(pieces)
    }

    /// SplitMix64. The session's own sampling is a different hash for a
    /// different job; this one only has to be stable and well spread.
    private static func next(_ state: inout UInt64) -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
