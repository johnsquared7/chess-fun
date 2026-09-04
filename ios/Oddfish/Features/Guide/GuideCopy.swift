import Foundation

/// Everything Gil ever says, in one reviewable place.
///
/// House rules for this file:
/// - One sentence where one will do. This appears in a small bubble over a
///   chess board on a phone.
/// - Never "Great job!". Praise that could have been written before the game
///   started is worse than silence, because it teaches the player that nothing
///   he says is about them.
/// - Every claim about the opponent must be checkable against the code. Gil's
///   credibility is the whole product, and it is spent the first time he says
///   something a player can disprove.
nonisolated struct GuideLine: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    let expression: GilExpression

    init(_ id: String, _ text: String, _ expression: GilExpression = .talking) {
        self.id = id
        self.text = text
        self.expression = expression
    }
}

nonisolated enum GuideCopy {
    // MARK: - Meeting the boss

    static let bossIntro = GuideLine(
        "intro.boss",
        "That's Stockfish. No hobbies, no friends, and an upsetting amount of chess.",
        .sly
    )

    static let bossIntroFollow = GuideLine(
        "intro.boss.follow",
        "Play anyway. Confidence is cheaper than accuracy.",
        .talking
    )

    // MARK: - The first game

    static let firstMove = GuideLine(
        "first.move",
        "One move in. Stockfish remains annoyingly calm.",
        .talking
    )

    static let bigCapture = GuideLine(
        "capture.big",
        "That was an expensive piece. Try not to look this surprised.",
        .cheer
    )

    /// One quip per lost piece kind. The facts come from the committed move;
    /// the sarcasm never guesses what disappeared.
    static func pieceLost(_ kind: PieceKind) -> GuideLine {
        let text: String = switch kind {
        case .pawn: "A pawn has left us. Brief service. Modest pension."
        case .knight: "There goes the knight. Apparently the L stood for Leaving."
        case .bishop: "Bishop down. It finally found a diagonal it couldn't sermon its way out of."
        case .rook: "The rook is gone. Lovely castle. Shame about the security."
        case .queen: "Your queen is gone. Tiny detail. Barely the most powerful piece."
        case .king: "The king got captured, which is impressively illegal even for us."
        }
        return GuideLine("capture.lost.\(kind.rawValue)", text, .wince)
    }

    static let firstCheckAgainstYou = GuideLine(
        "check.against.player",
        "Check. Move the king, block it, or take the attacker. Yes, it is making demands already.",
        .surprised
    )

    // MARK: - The hinge
    //
    // Every claim below follows the executable rule object. Gil describes what
    // changed; he never pretends the engine agreed to play badly.

    static let hingeLossHeadline = "So close. Apart from the checkmate."
    static let hingeLossSub = "That was full-strength Stockfish. Warm as a parking meter, but slightly better at chess."

    static let hingeWinHeadline = "You won. That's mildly suspicious."
    static let hingeWinSub = "A five-year-old probably could too. A terrifying five-year-old, but still."

    static let hingeDrawHeadline = "A draw. Nobody gets to be smug."
    static let hingeDrawSub = "Stockfish couldn't finish you off. Awkward for both of you."

    static let hingeTurn = "Fine. Let's give the machine a personality defect."

    static func hingeHeadline(for result: GameResult, opponentRating: Int?) -> String {
        if result == .win, let opponentRating {
            return "You beat \(opponentRating) Elo. Try to look surprised."
        }
        return switch result {
        case .win: hingeWinHeadline
        case .draw: hingeDrawHeadline
        default: hingeLossHeadline
        }
    }

    static func hingeSubline(for result: GameResult, opponentRating: Int?) -> String {
        if result == .win, opponentRating != nil {
            return "A five-year-old probably could too. A terrifying five-year-old, but still."
        }
        return switch result {
        case .win: hingeWinSub
        case .draw: hingeDrawSub
        default: hingeLossSub
        }
    }

    /// The second line on each card is the point of the whole screen: it turns a
    /// vague promise into something the player can verify.
    static func hingePitch(for mode: GameMode) -> (pitch: String, whatChanges: String) {
        switch mode {
        case .restfish:
            ("Move a piece and it immediately needs a little lie-down.",
             "Two-turn naps for both sides. Apparently chess is exhausting.")
        case .rattleFish:
            ("Find a best move and it loses 100 Elo.",
             "Play well and watch the machine develop feelings.")
        case .fumbleFish:
            ("Usually brilliant. Occasionally catastrophic.",
             "Five-percent chance it chooses the worst line. Relatable.")
        case .classic:
            ("Plain chess, no twists.",
             "No handicap. Just you and it.")
        default:
            (mode.tagline + ".", mode.ruleSummary)
        }
    }

    /// The mode detail screen already prints the rule summary as its headline,
    /// so the line underneath has to add something. `hingePitch` hands back
    /// that same summary for any mode without a bespoke pitch, which is how
    /// most of the catalogue came to say one sentence twice. Those modes say
    /// their in-game cue instead.
    static func detailSubtitle(for mode: GameMode) -> String {
        let whatChanges = hingePitch(for: mode).whatChanges
        return whatChanges == mode.ruleSummary ? mode.inGameCue : whatChanges
    }

    static let hingeDecline = "No gimmicks. Very brave."

    // MARK: - Teaching a mode, once ever

    static func teaching(for mode: GameMode) -> GuideLine? {
        switch mode {
        case .classic:
            nil
        case .restfish:
            GuideLine("teach.restfish", "That piece is resting now — two of your turns. Its pieces rest too.", .talking)
        case .rattleFish:
            GuideLine("teach.rattlefish", "Find one of Stockfish's best moves and I shave 100 points off its rating.", .sly)
        case .flinchFish:
            GuideLine("teach.flinchfish", "Every check rattles 300 points out of its live rating.", .surprised)
        case .fadeFish:
            GuideLine("teach.fadefish", "Every reply costs it 50 rating points. Survive long enough and you'll feel it.", .talking)
        case .mopeFish:
            GuideLine("teach.mopefish", "Take one of its pieces and its rating drops by 200.", .wince)
        case .gluttonFish:
            GuideLine("teach.gluttonfish", "It starts at zero, then gains 1000 whenever it captures or checks.", .surprised)
        case .babyFish:
            GuideLine("teach.babyfish", "It starts at zero and learns 100 rating points with every move.", .talking)
        case .fumbleFish:
            GuideLine("teach.fumblefish", "It is full-strength until a five-percent roll makes it choose the bottom line.", .sly)
        case .dwindleFish:
            GuideLine("teach.dwindlefish", "Best move half the time; every lower rank is half as likely again.", .talking)
        case .tempoFish:
            GuideLine("teach.tempofish", "Every fifth normal turn, you move twice — unless your first move gives check.", .cheer)
        case .levelFish:
            GuideLine("teach.levelfish", "It chooses the line closest to an even evaluation, whichever side is ahead.", .talking)
        case .mimicFish:
            GuideLine("teach.mimicfish", "It copies the piece you moved; bishops and knights share a drawer.", .sly)
        case .throneFish:
            GuideLine("teach.thronefish", "Kings capture, but otherwise move only when check leaves no other answer.", .talking)
        case .chapelFish:
            GuideLine("teach.chapelfish", "Its back rank is seven bishops and a king. Yours stays ordinary.", .surprised)
        case .stableFish:
            GuideLine("teach.stablefish", "Its back rank is seven knights and a king. Mind the forks.", .surprised)
        case .fortressFish:
            GuideLine("teach.fortressfish", "Seven rooks and a king. Every open file belongs to it, not you.", .surprised)
        case .royalFish:
            GuideLine("teach.royalfish", "Seven queens and a king. I did check the rules. Twice.", .surprised)
        case .pacifish:
            GuideLine("teach.pacifish", "It takes only when it has no quiet move left. Hang things with confidence.", .sly)
        case .piranhaFish:
            GuideLine("teach.piranhafish", "If any capture is legal, it must play one. Leave bait and watch.", .sly)
        case .comebackFish:
            GuideLine("teach.comebackfish", "It gains 250 rating for every point of material you go ahead by.", .wince)
        case .moodSwingFish:
            GuideLine("teach.moodswingfish", "Best move, then worst move, then best again. Count its turns.", .talking)
        case .pawnFish:
            GuideLine("teach.pawnfish", "Fifteen pawns and a king. Nothing to develop, nowhere to castle, and it knows.", .surprised)
        case .revengeFish:
            GuideLine("teach.revengefish", "Take something and it takes that square straight back, if it legally can. Choose what you offer.", .sly)
        case .contraryFish:
            GuideLine("teach.contraryfish", "It refuses to answer with the piece you just moved. Bishops and knights count as one family.", .talking)
        case .comboFish:
            GuideLine("teach.combofish", "Capture without giving check and you move again. Once — the free move earns nothing.", .cheer)
        case .lastStandFish:
            GuideLine("teach.laststandfish", "It starts at zero and gains 200 for every piece you take. Trading is how you lose this one.", .wince)
        case .upstreamFish:
            GuideLine("teach.upstreamfish", "Nothing but a king may retreat — yours or its. Getting out of check still comes first.", .talking)
        case .shuffleFish:
            GuideLine("teach.shufflefish", "Its back rank was shuffled before you arrived. No castling, and no opening book worth a thing.", .sly)
        }
    }

    static let restingPieceBlocked = { (remaining: Int) in
        GuideLine(
            "consequence.resting",
            "Still napping. \(remaining) more turn\(remaining == 1 ? "" : "s"). Very demanding work, standing there.",
            .talking
        )
    }

    /// One line per piece kind, once ever, after the player has tried the same
    /// illegal move twice in a row.
    static func movesLike(_ kind: PieceKind) -> GuideLine {
        let text: String = switch kind {
        case .pawn: "Pawns only walk forward — they capture on the diagonal."
        case .knight: "Knights go two squares one way, one the other. Nothing blocks them."
        case .bishop: "Bishops never leave their own colour."
        case .rook: "Rooks travel in straight lines, as far as the board is clear."
        case .queen: "The queen moves like a rook and a bishop at once."
        case .king: "The king moves one square, and never into check."
        }
        return GuideLine("rule.moves.\(kind.rawValue)", text, .talking)
    }

    // MARK: - Endings

    static func variantWin(_ mode: GameMode, opponentRating: Int? = nil) -> GuideLine {
        let text = if let opponentRating {
            "You beat \(opponentRating) Elo. A five-year-old could probably do it too. A terrifying one."
        } else {
            "You won. A five-year-old could probably do that too. A terrifying one."
        }
        return GuideLine("end.win.\(mode.rawValue)", text, .cheer)
    }

    static func variantLoss(_ mode: GameMode, resigned: Bool = false) -> GuideLine {
        let text = resigned
            ? "So close. Emotionally, at least. The board was less convinced."
            : "So close. Apart from the checkmate, which was a fairly large detail."
        return GuideLine("end.loss.\(mode.rawValue)", text, .wince)
    }

    static let ordinaryDraw = GuideLine("end.draw", "A draw. Neither of you found the door. Beautiful.", .idle)

    // MARK: - Odds and ends

    static let idleNudge = GuideLine(
        "ambient.idle",
        "Take your time. It's only judging you at several million positions per second.",
        .idle
    )

    static let escapeHatch = GuideLine(
        "ambient.escape",
        "This one's going long. Want to skip to the fun part?",
        .sly
    )

    static func homeGreeting(gamesPlayed: Int) -> String {
        switch gamesPlayed {
        case 0: "New here? Start with Classic so we can establish whose fault this is."
        case 1...4: "Back already? Pick a fish and make it someone else's problem."
        default: "Choose a fish. They're all terrible in very specific ways."
        }
    }
}
