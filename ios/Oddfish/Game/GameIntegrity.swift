import Foundation

/// Every non-move action a player can take during a game.
///
/// Keeping the complete audit now means later reward tiers can ask what happened
/// without trying to infer it from a board that may have been undone or reset.
nonisolated enum GameControl: String, Codable, CaseIterable, Hashable, Sendable {
    case pause
    case resume
    case undo
    case redo
    case restart
    case resign
    case exit
    case sideChange
    case analysis
    case settingChange
}

nonisolated struct GameIntegrity: Codable, Hashable, Sendable {
    private(set) var useCounts: [GameControl: Int] = [:]

    mutating func record(_ control: GameControl) {
        useCounts[control, default: 0] += 1
    }

    func count(for control: GameControl) -> Int {
        useCounts[control, default: 0]
    }

    var usedControls: Set<GameControl> { Set(useCounts.keys) }

    /// Stage 6 can consume this directly when crowns become persistent.
    /// Undo/redo is the strongest aid; analysis or changing a live setting is
    /// the lighter aid. Ordinary lifecycle controls do not lower the tier.
    var maximumCrownTier: Int {
        if count(for: .undo) > 0 || count(for: .redo) > 0 { return 1 }
        if count(for: .analysis) > 0 || count(for: .settingChange) > 0 { return 2 }
        return 3
    }
}
