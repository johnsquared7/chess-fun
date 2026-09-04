import Foundation
import Testing
@testable import Oddfish

struct Stage6CrownRuleTests {
    @Test func everyModeDeclaresAStableScoreContract() {
        #expect(GameMode.allCases.allSatisfy { !$0.crownRule.scoreDescription.isEmpty })

        let fullStrength: Set<GameMode> = [
            .rattleFish, .flinchFish, .fadeFish, .mopeFish, .tempoFish, .fumbleFish, .restfish
        ]
        let zeroStrength: Set<GameMode> = [.gluttonFish, .babyFish, .comebackFish, .lastStandFish]
        for mode in GameMode.allCases {
            if fullStrength.contains(mode) {
                #expect(mode.crownRule.requiredStartingRating == .maximum)
            } else if zeroStrength.contains(mode) {
                #expect(mode.crownRule.requiredStartingRating == .minimum)
            } else {
                #expect(mode.crownRule.requiredStartingRating == nil)
            }
        }
    }

    @Test func eachParameterModeScoresTheValueThatMadeTheGameHarder() {
        let cases: [(GameMode, String, Double, CrownScoreMetric, Int, Bool)] = [
            (.rattleFish, GimmickParameterKey.amount, 50, .eloLostPerBestMove, 50, false),
            (.flinchFish, GimmickParameterKey.amount, 200, .eloLostPerCheck, 200, false),
            (.fadeFish, GimmickParameterKey.amount, 20, .eloLostPerEngineMove, 20, false),
            (.mopeFish, GimmickParameterKey.amount, 100, .eloLostPerPiece, 100, false),
            (.gluttonFish, GimmickParameterKey.amount, 1_500, .eloGainedPerThreat, 1_500, true),
            (.babyFish, GimmickParameterKey.amount, 250, .eloGainedPerEngineMove, 250, true),
            (.tempoFish, GimmickParameterKey.cycle, 9, .bonusInterval, 9, true),
            (.fumbleFish, GimmickParameterKey.chance, 2, .blunderChance, 2, false),
            (.comebackFish, GimmickParameterKey.amount, 300, .eloGainedPerMaterialPoint, 300, true),
            (.lastStandFish, GimmickParameterKey.amount, 350, .eloGainedPerPiece, 350, true)
        ]

        for (mode, key, value, metric, expected, higherIsBetter) in cases {
            let score = mode.crownScore(
                startingRating: mode.gimmickRule.startingRating,
                parameters: GimmickParameters(values: [key: value])
            )
            #expect(score.metric == metric)
            #expect(score.value == expected)
            #expect(score.higherIsBetter == higherIsBetter)
        }
    }

    @Test func crownTiersFollowIntegrityAndEligibilityBoundaries() {
        let clean = GameIntegrity()
        var assisted = GameIntegrity()
        assisted.record(.analysis)
        var changed = GameIntegrity()
        changed.record(.settingChange)
        var rewound = GameIntegrity()
        rewound.record(.undo)

        #expect(GameMode.rattleFish.crownAward(
            wonByCheckmate: true,
            startingRating: .maximum,
            parameters: .init(),
            integrity: clean
        )?.tier == 3)
        #expect(GameMode.rattleFish.crownAward(
            wonByCheckmate: true,
            startingRating: .maximum,
            parameters: .init(),
            integrity: assisted
        )?.tier == 2)
        #expect(GameMode.rattleFish.crownAward(
            wonByCheckmate: true,
            startingRating: .maximum,
            parameters: .init(),
            integrity: changed
        )?.tier == 2)
        #expect(GameMode.rattleFish.crownAward(
            wonByCheckmate: true,
            startingRating: .maximum,
            parameters: .init(),
            integrity: rewound
        )?.tier == 1)
        #expect(GameMode.rattleFish.crownAward(
            wonByCheckmate: true,
            startingRating: OpponentRating(3_500),
            parameters: .init(),
            integrity: clean
        ) == nil)
        #expect(GameMode.rattleFish.crownAward(
            wonByCheckmate: false,
            startingRating: .maximum,
            parameters: .init(),
            integrity: clean
        ) == nil)
        #expect(GameMode.rattleFish.crownAward(
            wonByCheckmate: true,
            startingRating: .maximum,
            parameters: .init(),
            integrity: clean,
            isImported: true
        ) == nil)
    }

    @Test func integrityTierOutranksLighterAssistanceAndIgnoresLifecycle() {
        // The tier is the worst aid used, not an average: undo and redo keep
        // their penalty even when the player also used lighter assistance, and
        // ordinary lifecycle controls never lower a clean game.
        var rewoundAndAssisted = GameIntegrity()
        rewoundAndAssisted.record(.undo)
        rewoundAndAssisted.record(.analysis)
        #expect(rewoundAndAssisted.maximumCrownTier == 1)

        var replayedAndAssisted = GameIntegrity()
        replayedAndAssisted.record(.redo)
        replayedAndAssisted.record(.settingChange)
        #expect(replayedAndAssisted.maximumCrownTier == 1)

        var lightlyAssisted = GameIntegrity()
        lightlyAssisted.record(.analysis)
        lightlyAssisted.record(.settingChange)
        #expect(lightlyAssisted.maximumCrownTier == 2)

        var lifecycleOnly = GameIntegrity()
        for control in [GameControl.pause, .resume, .restart, .sideChange, .exit, .resign] {
            lifecycleOnly.record(control)
        }
        #expect(lifecycleOnly.maximumCrownTier == 3)
        #expect(lifecycleOnly.usedControls == Set([.pause, .resume, .restart, .sideChange, .exit, .resign]))
        #expect(GameIntegrity().maximumCrownTier == 3)
    }

    @Test func gluttonFishSeparatesNormalAndHardPersonalBests() {
        let normal = GimmickParameters(values: [GimmickParameterKey.hardMode: 0])
        let hard = GimmickParameters(values: [GimmickParameterKey.hardMode: 1])
        #expect(GameMode.gluttonFish.personalBestVariant(parameters: normal) == "standard")
        #expect(GameMode.gluttonFish.personalBestVariant(parameters: hard) == "hard")
        #expect(GameMode.babyFish.personalBestVariant(parameters: normal) == nil)
    }
}

@MainActor
struct Stage6SessionAwardTests {
    private struct BlackMateRule: GimmickRule {
        let startingPosition = Position(fen: "r5k1/8/8/8/8/8/5PPP/6K1 b - - 0 1")!
    }

    private struct FirstAllowedOpponent: ChessOpponent {
        let name = "Test Fish"
        func bestMove(for request: OpponentRequest) async -> Move? { request.allowedMoves.first }
    }

    @Test func aLiveCheckmatePersistsItsCrownScoreAndReplay() throws {
        var recorded: GameRecord?
        let session = GameSession(
            mode: .classic,
            rating: OpponentRating(1_900),
            rule: BlackMateRule(),
            playerColor: .black,
            opponent: { FirstAllowedOpponent() },
            onRecord: { recorded = $0 }
        )
        let mate = try #require(session.legalMoves.first { move in
            guard let next = ChessEngine.apply(move, to: session.position) else { return false }
            return ChessEngine.outcome(for: next, history: [session.position]) == .checkmate(winner: .black)
        })

        #expect(session.attemptMove(from: mate.from, to: mate.to))
        let finished = try #require(recorded)
        #expect(finished.crownTier == 3)
        #expect(finished.score == CrownScore(value: 1_900, metric: .opponentElo))
        #expect(finished.startingFEN == BlackMateRule().startingPosition.fen)
        #expect(finished.playerColor == .black)
        #expect(try GameReplay(record: finished).plies.count == 1)
        #expect(session.completionRecord == finished)
    }

    @Test func visibleAnalysisLowersThePersistedAwardToTwoCrowns() throws {
        var settings = AppSettings.default
        settings.evaluationEnabled = true
        let session = GameSession(
            mode: .classic,
            rule: BlackMateRule(),
            playerColor: .black,
            settings: settings,
            opponent: { FirstAllowedOpponent() }
        )
        let mate = try #require(session.legalMoves.first { move in
            guard let next = ChessEngine.apply(move, to: session.position) else { return false }
            return ChessEngine.outcome(for: next, history: [session.position]) == .checkmate(winner: .black)
        })

        #expect(session.attemptMove(from: mate.from, to: mate.to))
        #expect(session.completionRecord?.crownTier == 2)
    }
}

struct Stage6NotationAndPGNTests {
    @Test func sanAndCoordinatesRoundTripTheSameMoves() throws {
        let coordinateReplay = try GameReplay(
            notation: "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6",
            startingPosition: .starting,
            mode: .classic,
            playerColor: .white,
            parameters: .init()
        )
        #expect(coordinateReplay.sanMoves == ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"])

        let sanReplay = try GameReplay(
            notation: coordinateReplay.sanMoves.joined(separator: " "),
            startingPosition: .starting,
            mode: .classic,
            playerColor: .white,
            parameters: .init()
        )
        #expect(sanReplay.plies.map(\.move) == coordinateReplay.plies.map(\.move))
        #expect(sanReplay.positions.last == coordinateReplay.positions.last)
    }

    @Test func notationHandlesCastlingPromotionAndCheckSuffixes() throws {
        let castle = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!
        let castleMove = try #require(ChessEngine.legalMoves(in: castle).first { $0.flags.contains(.castleKingside) })
        #expect(ChessNotation.san(for: castleMove, in: castle) == "O-O")

        let promotion = Position(fen: "7k/P7/8/8/8/8/8/7K w - - 0 1")!
        let promotionMove = try #require(ChessEngine.legalMoves(in: promotion).first {
            $0.to == Square("a8")! && $0.promotion == .queen
        })
        #expect(ChessNotation.san(for: promotionMove, in: promotion).hasPrefix("a8=Q"))
    }

    @Test func tempoFishReplayPreservesTheConsecutivePlayerTurn() throws {
        let replay = try GameReplay(
            notation: "e4 e5 Nf3 Bc4",
            startingPosition: .starting,
            mode: .tempoFish,
            playerColor: .white,
            parameters: GimmickParameters(values: [GimmickParameterKey.cycle: 2])
        )
        #expect(replay.plies.count == 4)
        #expect(replay.plies[2].positionAfter.sideToMove == .white)
        #expect(replay.plies[3].positionBefore.sideToMove == .white)
        #expect(replay.plies[3].positionAfter.sideToMove == .black)
    }

    @Test func exportedPGNRoundTripsButImportsNeverKeepCrowns() throws {
        let record = GameRecord(
            modeID: GameMode.classic.rawValue,
            result: .win,
            duration: 91,
            moveCount: 6,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            notation: "e4 e5 Nf3 Nc6 Bb5 a6",
            startingFEN: Position.starting.fen,
            playerColorID: PieceColor.white.rawValue,
            startingRating: 1_800,
            endingRating: 1_800,
            award: CrownAward(tier: 3, score: CrownScore(value: 1_800, metric: .opponentElo))
        )

        let pgn = PGNCodec.export(record)
        #expect(pgn.contains("[OddfishCrowns \"3\"]"))
        #expect(pgn.contains("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0"))

        let imported = try PGNCodec.importRecord(from: pgn)
        #expect(imported.isImported)
        #expect(imported.crownTier == nil)
        #expect(imported.score == nil)
        #expect(imported.result == .win)
        #expect(imported.moveCount == 6)
        let importedReplay = try GameReplay(record: imported)
        let originalReplay = try GameReplay(record: record)
        #expect(importedReplay.positions.last == originalReplay.positions.last)
    }

    @Test func externalPGNCommentsVariationsAndMoveNumbersAreIgnored() throws {
        let pgn = """
        [Event "Example"]
        [Result "1/2-1/2"]

        1. e4 {main line} e5 2. Nf3 (2. Bc4?!) Nc6 $1 1/2-1/2
        """
        let imported = try PGNCodec.importRecord(from: pgn)
        #expect(imported.result == .draw)
        #expect(imported.notation == "e4 e5 Nf3 Nc6")
        #expect(imported.moveCount == 4)
    }

    @Test func malformedPGNReportsTheExactBadPly() {
        #expect(throws: PGNError.invalidMove("Qa9", ply: 2)) {
            try PGNCodec.importRecord(from: "1. e4 Qa9 1-0")
        }
    }

}

@Suite(.serialized)
@MainActor
struct Stage6PersonalBestTests {
    private func makeDefaults() -> UserDefaults {
        let name = "oddfish.stage6.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    private func record(
        score: Int,
        metric: CrownScoreMetric,
        crowns: Int,
        variant: String? = nil,
        imported: Bool = false
    ) -> GameRecord {
        GameRecord(
            modeID: GameMode.gluttonFish.rawValue,
            result: .win,
            duration: 1,
            moveCount: 1,
            origin: imported ? .imported : .played,
            award: CrownAward(tier: crowns, score: CrownScore(value: score, metric: metric)),
            personalBestVariant: variant
        )
    }

    @Test func personalBestsUseScoreDirectionThenCrownsAsTieBreak() throws {
        let store = AppStateStore(userDefaults: makeDefaults())
        store.recordCompletedGame(record(score: 1_000, metric: .eloGainedPerThreat, crowns: 3, variant: "standard"))
        store.recordCompletedGame(record(score: 1_500, metric: .eloGainedPerThreat, crowns: 1, variant: "standard"))
        store.recordCompletedGame(record(score: 1_500, metric: .eloGainedPerThreat, crowns: 2, variant: "standard"))
        store.recordCompletedGame(record(score: 2_000, metric: .eloGainedPerThreat, crowns: 3, variant: "standard", imported: true))
        store.recordCompletedGame(record(score: 1_200, metric: .eloGainedPerThreat, crowns: 3, variant: "hard"))

        let bests = store.personalBests(for: .gluttonFish)
        #expect(bests.count == 2)
        #expect(bests.first { $0.personalBestVariant == "standard" }?.score?.value == 1_500)
        #expect(bests.first { $0.personalBestVariant == "standard" }?.crownTier == 2)
        #expect(bests.first { $0.personalBestVariant == "hard" }?.score?.value == 1_200)
        #expect(store.stats.gamesPlayed == 4)
    }

    @Test func importedGamesDoNotChangeLocalStatsOrPersonalBests() throws {
        let store = AppStateStore(userDefaults: makeDefaults())
        let imported = try PGNCodec.importRecord(from: "1. e4 e5 2. Nf3 Nc6 1-0")
        store.importGame(imported)

        #expect(store.history.count == 1)
        #expect(store.history[0].isImported)
        #expect(store.stats.gamesPlayed == 0)
        #expect(store.personalBest(for: .classic) == nil)
    }
}
