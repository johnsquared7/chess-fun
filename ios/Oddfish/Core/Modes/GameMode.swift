import SwiftUI

enum GameMode: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case classic
    case rattleFish = "rattlefish"
    case flinchFish = "flinchfish"
    case fadeFish = "fadefish"
    case mopeFish = "mopefish"
    case gluttonFish = "gluttonfish"
    case babyFish = "babyfish"
    case fumbleFish = "fumblefish"
    case dwindleFish = "dwindlefish"
    case tempoFish = "tempofish"
    case levelFish = "levelfish"
    case mimicFish = "mimicfish"
    case throneFish = "thronefish"
    case chapelFish = "chapelfish"
    case stableFish = "stablefish"
    case restfish
    case fortressFish = "fortressfish"
    case royalFish = "royalfish"
    case pacifish
    case piranhaFish = "piranhafish"
    case comebackFish = "comebackfish"
    case moodSwingFish = "moodswingfish"
    case pawnFish = "pawnfish"
    case revengeFish = "revengefish"
    case contraryFish = "contraryfish"
    case comboFish = "combofish"
    case lastStandFish = "laststandfish"
    case upstreamFish = "upstreamfish"
    case shuffleFish = "shufflefish"

    nonisolated var id: String { rawValue }

    /// The three distinct, beginner-readable variants Gil offers after the
    /// first boss game.
    nonisolated static let hingeOffers: [GameMode] = [.rattleFish, .fumbleFish, .restfish]

    /// The complete starter set. These modes are permanently playable without
    /// a purchase so the first-run story and a useful slice of the catalogue
    /// never depend on the App Store being reachable.
    nonisolated static let freeModes: Set<GameMode> = [
        .classic, .rattleFish, .fumbleFish, .restfish, .gluttonFish, .chapelFish
    ]

    nonisolated var isFree: Bool { Self.freeModes.contains(self) }
    nonisolated var requiresFullUnlock: Bool { !isFree }

    nonisolated var title: String {
        switch self {
        case .classic: "Classic"
        case .rattleFish: "RattleFish"
        case .flinchFish: "FlinchFish"
        case .fadeFish: "FadeFish"
        case .mopeFish: "MopeFish"
        case .gluttonFish: "GluttonFish"
        case .babyFish: "BabyFish"
        case .fumbleFish: "FumbleFish"
        case .dwindleFish: "DwindleFish"
        case .tempoFish: "TempoFish"
        case .levelFish: "LevelFish"
        case .mimicFish: "MimicFish"
        case .throneFish: "ThroneFish"
        case .chapelFish: "ChapelFish"
        case .stableFish: "StableFish"
        case .restfish: "Restfish"
        case .fortressFish: "FortressFish"
        case .royalFish: "RoyalFish"
        case .pacifish: "Pacifish"
        case .piranhaFish: "PiranhaFish"
        case .comebackFish: "ComebackFish"
        case .moodSwingFish: "MoodSwingFish"
        case .pawnFish: "PawnFish"
        case .revengeFish: "RevengeFish"
        case .contraryFish: "ContraryFish"
        case .comboFish: "ComboFish"
        case .lastStandFish: "LastStandFish"
        case .upstreamFish: "UpstreamFish"
        case .shuffleFish: "ShuffleFish"
        }
    }

    nonisolated var shortTitle: String { title.uppercased() }

    /// The title split at its camel-case seams. `MoodSwingFish` gives
    /// `["Mood", "Swing", "Fish"]`; `Restfish` gives what it already reads
    /// as. Spoken spelling is never changed — only where a line may break.
    nonisolated var titleWords: [String] {
        var words: [String] = []
        var current = ""
        for character in title {
            if character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            if let previous = current.last, previous.isLowercase, character.isUppercase {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// Everything before the family word: "Mood Swing", "Glutton", "Throne".
    /// A one-word name keeps all of itself here.
    nonisolated var titleLead: String {
        let words = titleWords
        guard words.count > 1 else { return title }
        return words.dropLast().joined(separator: " ")
    }

    /// The word the name ends on — "Fish" for every compound name in the
    /// catalogue, empty for the one-word names (Restfish, Pacifish, Classic).
    ///
    /// Catalogue tiles give this its own line whether a mode fills it or not.
    /// That is what makes the row line up: the lead word of every card shares a
    /// baseline, and a three-word name can no longer shove its neighbours'
    /// taglines out of alignment.
    nonisolated var titleFamily: String {
        let words = titleWords
        guard words.count > 1, let last = words.last else { return "" }
        return last
    }

    nonisolated var tagline: String {
        switch self {
        case .classic: "The clear-water baseline"
        case .rattleFish: "Good moves get under its skin"
        case .flinchFish: "Check it. Shake it."
        case .fadeFish: "Weaker with every reply"
        case .mopeFish: "Every loss hurts"
        case .gluttonFish: "Feed it and it grows"
        case .babyFish: "Learning one move at a time"
        case .fumbleFish: "Brilliant, until it isn't"
        case .dwindleFish: "Strength by coin toss"
        case .tempoFish: "Every fifth turn, move twice"
        case .levelFish: "Always steering for level"
        case .mimicFish: "It copies your piece"
        case .throneFish: "The king would rather not"
        case .chapelFish: "A back rank of bishops"
        case .stableFish: "A back rank of knights"
        case .restfish: "Rest, then strike"
        case .fortressFish: "Seven towers. Zero subtlety."
        case .royalFish: "The court is overcrowded."
        case .pacifish: "Violence is a last resort."
        case .piranhaFish: "If it can bite, it must."
        case .comebackFish: "Your lead feeds it."
        case .moodSwingFish: "Genius. Disaster. Repeat."
        case .pawnFish: "A back rank of pawns"
        case .revengeFish: "It always takes it back."
        case .contraryFish: "Never the piece you moved"
        case .comboFish: "Capture, then go again"
        case .lastStandFish: "Cornered, and improving"
        case .upstreamFish: "Forward only. No regrets."
        case .shuffleFish: "The back rank drew lots"
        }
    }

    nonisolated var ruleSummary: String {
        switch self {
        case .classic: "Standard chess, with room to learn and plan."
        case .rattleFish: "It loses 100 Elo whenever you find a best move."
        case .flinchFish: "It loses 300 Elo whenever you give check."
        case .fadeFish: "It loses 50 Elo after every move it makes."
        case .mopeFish: "It loses 200 Elo whenever you capture one of its pieces."
        case .gluttonFish: "It starts at 0 Elo and gains 1000 when it captures or checks."
        case .babyFish: "It starts at 0 Elo and gains 100 after each move it makes."
        case .fumbleFish: "It plays at full strength, with a 5% chance of the worst move."
        case .dwindleFish: "It chooses the first, second, third-best move with halving odds."
        case .tempoFish: "At full strength, you earn an extra move every fifth turn."
        case .levelFish: "It chooses the line whose evaluation is closest to 0.00."
        case .mimicFish: "It answers with the piece type you just moved when it can."
        case .throneFish: "Kings cannot move without capturing unless check leaves no alternative."
        case .chapelFish: "Its back rank is bishops, except for the king."
        case .stableFish: "Its back rank is knights, except for the king."
        case .restfish: "A moved piece rests for your next two turns."
        case .fortressFish: "Its back rank is rooks, except for the king."
        case .royalFish: "Its back rank is queens, except for the king."
        case .pacifish: "It avoids captures whenever a quiet legal move exists."
        case .piranhaFish: "It must capture whenever a legal capture exists."
        case .comebackFish: "Its Elo rises for every point of material it falls behind."
        case .moodSwingFish: "It alternates between its best and worst analysed move."
        case .pawnFish: "Its back rank is pawns, except for the king."
        case .revengeFish: "It must recapture on the square you took from, whenever that is legal."
        case .contraryFish: "It answers with a piece type other than the one you just moved."
        case .comboFish: "A capture that gives no check earns you another move."
        case .lastStandFish: "It starts at 0 Elo and gains 200 whenever you take one of its pieces."
        case .upstreamFish: "No piece but a king may move back toward its own back rank."
        case .shuffleFish: "Its back-rank pieces are shuffled at the start, and it cannot castle."
        }
    }

    nonisolated var inGameCue: String {
        switch self {
        case .classic: "No twists. Just the board and your next idea."
        case .rattleFish: "Best moves make the live rating fall."
        case .flinchFish: "Checks make the live rating fall."
        case .fadeFish: "Every engine reply costs it rating."
        case .mopeFish: "Captures make the live rating fall."
        case .gluttonFish: "Its captures and checks add rating fast."
        case .babyFish: "Its live rating rises after every reply."
        case .fumbleFish: "Most moves are full-strength; the rare miss is real."
        case .dwindleFish: "Each lower-ranked move is half as likely as the one above it."
        case .tempoFish: "Your bonus-move counter advances after each normal turn."
        case .levelFish: "It prefers the continuation nearest an equal score."
        case .mimicFish: "Bishops and knights count as the same copying family."
        case .throneFish: "Castling is disabled; captures are never lazy."
        case .chapelFish: "Only the opponent's back rank changes."
        case .stableFish: "Only the opponent's back rank changes."
        case .restfish: "Resting pieces cannot be selected, unless that is the only way out of check."
        case .fortressFish: "Only the opponent's back rank changes; it can still castle."
        case .royalFish: "Only the opponent's back rank changes."
        case .pacifish: "It takes only once every quiet move is gone."
        case .piranhaFish: "Any capture you leave on the board, it has to take."
        case .comebackFish: "Its live rating tracks the material you are ahead by."
        case .moodSwingFish: "It opens on its best move, then its worst, then repeats."
        case .pawnFish: "Only the opponent's back rank changes; it has no rook to castle with."
        case .revengeFish: "The square you captured on is the square it answers."
        case .contraryFish: "Bishops and knights count as one family, so both are ruled out together."
        case .comboFish: "A capture with check pays nothing, and a bonus move cannot earn another."
        case .lastStandFish: "Every piece you take feeds it. Checkmate is cheaper than a trade."
        case .upstreamFish: "Both armies are bound by it, and check evasions stay legal."
        case .shuffleFish: "Only the opponent's back rank is scrambled, and a restart keeps the same one."
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .classic: "crown"
        case .rattleFish: "arrow.down.right"
        case .flinchFish: "exclamationmark.bubble.fill"
        case .fadeFish: "battery.25percent"
        case .mopeFish: "drop.fill"
        case .gluttonFish: "fork.knife"
        case .babyFish: "teddybear.fill"
        case .fumbleFish: "dice.fill"
        case .dwindleFish: "chart.bar.xaxis"
        case .tempoFish: "forward.end.fill"
        case .levelFish: "equal.circle.fill"
        case .mimicFish: "rectangle.on.rectangle"
        case .throneFish: "bed.double.fill"
        case .chapelFish: "diamond.fill"
        case .stableFish: "hare.fill"
        case .restfish: "tortoise"
        case .fortressFish: "building.2.fill"
        case .royalFish: "crown.fill"
        case .pacifish: "peacesign"
        case .piranhaFish: "mouth.fill"
        case .comebackFish: "chart.line.uptrend.xyaxis"
        case .moodSwingFish: "theatermasks.fill"
        case .pawnFish: "circle.grid.3x3.fill"
        case .revengeFish: "arrow.uturn.backward"
        case .contraryFish: "arrow.left.arrow.right"
        case .comboFish: "bolt.fill"
        case .lastStandFish: "shield.fill"
        case .upstreamFish: "arrow.up.to.line"
        case .shuffleFish: "shuffle"
        }
    }

    var tint: Color {
        switch category {
        case .baseline: OddfishTheme.ivory
        case .weakening: OddfishTheme.coral
        case .growing: OddfishTheme.seaGlass
        case .chance: Color(red: 0.82, green: 0.70, blue: 1.0)
        case .constraints: Color(red: 0.48, green: 0.78, blue: 1.0)
        case .armies: OddfishTheme.Guide.body
        }
    }

    nonisolated var configuration: ModeConfiguration {
        switch self {
        case .restfish: .restfish
        case .throneFish: .throneFish
        case .upstreamFish: .upstreamFish
        default: .classic
        }
    }

    nonisolated var gimmickRule: any GimmickRule {
        switch self {
        case .rattleFish: RattleFishRule()
        case .flinchFish: FlinchFishRule()
        case .fadeFish: FadeFishRule()
        case .mopeFish: MopeFishRule()
        case .gluttonFish: GluttonFishRule()
        case .babyFish: BabyFishRule()
        case .fumbleFish: FumbleFishRule()
        case .dwindleFish: DwindleFishRule()
        case .tempoFish: TempoFishRule()
        case .levelFish: LevelFishRule()
        case .mimicFish: MimicFishRule()
        case .throneFish: ThroneFishRule()
        case .chapelFish: ChapelFishRule()
        case .stableFish: StableFishRule()
        case .fortressFish: FortressFishRule()
        case .royalFish: RoyalFishRule()
        case .pacifish: PacifishRule()
        case .piranhaFish: PiranhaFishRule()
        case .comebackFish: ComebackFishRule()
        case .moodSwingFish: MoodSwingFishRule()
        case .pawnFish: PawnFishRule()
        case .revengeFish: RevengeFishRule()
        case .contraryFish: ContraryFishRule()
        case .comboFish: ComboFishRule()
        case .lastStandFish: LastStandFishRule()
        case .upstreamFish: UpstreamFishRule()
        case .shuffleFish: ShuffleFishRule()
        case .classic, .restfish: ExistingModeGimmickRule()
        }
    }

    nonisolated var category: GameModeCategory {
        switch self {
        case .classic: .baseline
        case .rattleFish, .flinchFish, .fadeFish, .mopeFish: .weakening
        case .gluttonFish, .babyFish, .comebackFish, .lastStandFish: .growing
        case .fumbleFish, .dwindleFish, .moodSwingFish: .chance
        case .tempoFish, .levelFish, .mimicFish, .throneFish, .restfish,
             .pacifish, .piranhaFish, .revengeFish, .contraryFish,
             .comboFish, .upstreamFish: .constraints
        case .chapelFish, .stableFish, .fortressFish, .royalFish,
             .pawnFish, .shuffleFish: .armies
        }
    }
}

nonisolated enum GameModeCategory: String, CaseIterable, Identifiable {
    case baseline, weakening, growing, chance, constraints, armies

    var id: String { rawValue }
    var title: String {
        switch self {
        case .baseline: "Classic"
        case .weakening: "Bruise its ego"
        case .growing: "Feed the monster"
        case .chance: "Blame the dice"
        case .constraints: "Bend the rules"
        case .armies: "Perfectly normal armies"
        }
    }
    var subtitle: String {
        switch self {
        case .baseline: "Standard chess"
        case .weakening: "Good moves make its Elo worse"
        case .growing: "Starts harmless. Allegedly."
        case .chance: "Skill, with plausible deniability"
        case .constraints: "Chess, but one rule had ideas"
        case .armies: "The back rank has gone peculiar"
        }
    }
    var modes: [GameMode] {
        let inCategory = GameMode.allCases.filter { $0.category == self }
        // The free (unlocked) mode leads its row so it is always first —
        // e.g. Restfish fronts the constraints row instead of sitting fifth.
        // Stable within each group: locked modes keep their catalogue order.
        return inCategory.filter(\.isFree) + inCategory.filter { !$0.isFree }
    }
}

nonisolated struct ModeConfiguration: Codable, Hashable, Sendable {
    enum Rule: String, Codable, Hashable, Sendable {
        case standard
        case restingPiece
        case reluctantKing
        case forwardOnly
    }

    let rule: Rule
    let restTurns: Int
    static let classic = ModeConfiguration(rule: .standard, restTurns: 0)
    static let restfish = ModeConfiguration(rule: .restingPiece, restTurns: 2)
    static let throneFish = ModeConfiguration(rule: .reluctantKing, restTurns: 0)
    static let upstreamFish = ModeConfiguration(rule: .forwardOnly, restTurns: 0)

}
