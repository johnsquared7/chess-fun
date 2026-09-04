import Foundation
import Testing
@testable import Oddfish

struct Stage5GimmickRuleTests {
    private func context(
        playerColor: PieceColor = .white,
        lastPlayerMove: Move? = nil,
        sample: UInt64 = 1
    ) -> GimmickEngineContext {
        GimmickEngineContext(playerColor: playerColor, lastPlayerMove: lastPlayerMove, randomSample: sample, engineTurn: 0)
    }

    private func ply(
        movingColor: PieceColor,
        capture: Bool = false,
        check: Bool = false,
        analysis: GimmickMoveAnalysis? = nil
    ) -> GimmickPly {
        let move = Move(from: Square("e2")!, to: Square("e4")!, flags: capture ? .capture : [])
        return GimmickPly(
            move: move,
            movingPiece: Piece(color: movingColor, kind: .pawn),
            positionBefore: .starting,
            positionAfter: .starting,
            ply: 1,
            wasCapture: capture,
            givesCheck: check,
            analysis: analysis,
            playerColor: .white
        )
    }

    private func line(rank: Int, move: Move, score: AnalysisScore) -> AnalysisLine {
        AnalysisLine(
            rank: rank,
            depth: 12,
            selectiveDepth: 16,
            move: move,
            score: score,
            principalVariation: [move],
            elapsedMilliseconds: 10,
            nodes: 100,
            nodesPerSecond: 10_000,
            tablebaseHits: 0,
            hashFull: 0
        )
    }

    @Test func unpublishedModesUseCleanIdentifiers() {
        #expect(GameMode.restfish.rawValue == "restfish")
        #expect(GameMode.tempoFish.rawValue == "tempofish")
        #expect(GameMode.flinchFish.rawValue == "flinchfish")
        #expect(GameMode.allCases.count == 29)
        #expect(GameMode.restfish.category == .constraints)
        #expect(GameModeCategory.allCases.flatMap(\.modes).count == GameMode.allCases.count)
    }

    @Test func decreasingAndIncreasingRatingsUseCommittedPlyFacts() {
        let best = ply(movingColor: .white, analysis: GimmickMoveAnalysis(bestMove: Move(from: Square("e2")!, to: Square("e4")!)))
        #expect(RattleFishRule().rating(after: best, currentRating: .maximum, parameters: .init()) == OpponentRating(3_500))
        #expect(FlinchFishRule().rating(after: ply(movingColor: .white, check: true), currentRating: .maximum, parameters: .init()) == OpponentRating(3_300))
        #expect(FadeFishRule().rating(after: ply(movingColor: .black), currentRating: .maximum, parameters: .init()) == OpponentRating(3_550))
        #expect(MopeFishRule().rating(after: ply(movingColor: .white, capture: true), currentRating: .maximum, parameters: .init()) == OpponentRating(3_400))
        #expect(GluttonFishRule().rating(after: ply(movingColor: .black, check: true), currentRating: .minimum, parameters: .init()) == OpponentRating(1_000))
        #expect(BabyFishRule().rating(after: ply(movingColor: .black), currentRating: .minimum, parameters: .init()) == OpponentRating(100))
    }

    @Test func mimicfishCopiesPieceFamiliesAndFallsBackSafely() throws {
        let position = try #require(Position(fen: "1n2k3/8/8/8/8/8/3B4/4K3 b - - 0 1"))
        let playerMove = Move(from: Square("c1")!, to: Square("d2")!)
        let candidates = ChessEngine.legalMoves(in: position)
        let filtered = MimicFishRule().allowedEngineMoves(
            in: position,
            candidates: candidates,
            context: context(lastPlayerMove: playerMove),
            parameters: .init()
        )
        #expect(!filtered.isEmpty)
        #expect(filtered.allSatisfy { position.piece(at: $0.from)?.kind == .knight })

        let missing = MimicFishRule().allowedEngineMoves(
            in: position,
            candidates: candidates,
            context: context(lastPlayerMove: nil),
            parameters: .init()
        )
        #expect(missing == candidates)
    }

    @Test func strangeArmiesChangeOnlyTheOpponentBackRank() {
        let holyWhite = ChapelFishRule().startingPosition(playerColor: .white)
        let cavalryBlack = StableFishRule().startingPosition(playerColor: .black)
        #expect(holyWhite.piece(at: Square("a8")!)?.kind == .bishop)
        #expect(holyWhite.piece(at: Square("a1")!)?.kind == .rook)
        #expect(cavalryBlack.piece(at: Square("a1")!)?.kind == .knight)
        #expect(cavalryBlack.piece(at: Square("a8")!)?.kind == .rook)
        #expect(cavalryBlack.sideToMove == .white)
    }

    @Test func throneFishCapturesButDoesNotWander() throws {
        let quietPosition = try #require(Position(fen: "7k/8/8/8/8/8/4p3/4K3 w - - 0 1"))
        let quietMoves = VariantRules.legalMoves(in: quietPosition, state: .init(), configuration: .throneFish)
        #expect(quietMoves.count == 1)
        #expect(quietMoves.first?.to == Square("e2")!)
        #expect(quietMoves.first?.isCapture == true)

        let checked = try #require(Position(fen: "4r2k/8/8/8/8/8/R7/4K3 w - - 0 1"))
        let evasions = VariantRules.legalMoves(in: checked, state: .init(), configuration: .throneFish)
        #expect(!evasions.isEmpty)
        #expect(evasions.allSatisfy { checked.piece(at: $0.from)?.kind != .king })
        #expect(evasions.allSatisfy { !$0.isCastle })
    }

    @Test func analysisModesSelectTheirSpecifiedRankedLine() throws {
        let moves = ChessEngine.legalMoves(in: .starting)
        let first = try #require(moves.first)
        let second = try #require(moves.dropFirst().first)
        let third = try #require(moves.dropFirst(2).first)
        let analysis = PositionAnalysis(position: .starting, lines: [
            line(rank: 1, move: first, score: .centipawns(80)),
            line(rank: 2, move: second, score: .centipawns(-5)),
            line(rank: 3, move: third, score: .centipawns(-140))
        ])
        #expect(LevelFishRule().selectEngineMove(from: analysis, context: context(), parameters: .init()) == second)
        #expect(FumbleFishRule().selectEngineMove(from: analysis, context: context(sample: 4), parameters: .init()) == third)
        #expect(FumbleFishRule().selectEngineMove(from: analysis, context: context(sample: 5), parameters: .init()) == first)
        #expect(DwindleFishRule().selectEngineMove(from: analysis, context: context(sample: 1), parameters: .init()) == first)
        #expect(DwindleFishRule().selectEngineMove(from: analysis, context: context(sample: 2), parameters: .init()) == second)
        #expect(DwindleFishRule().selectEngineMove(from: analysis, context: context(sample: 4), parameters: .init()) == third)
    }

    @Test func tempofishGrantsOnlyTheConfiguredNormalTurn() {
        let rule = TempoFishRule()
        let ordinary = ply(movingColor: .white)
        #expect(!rule.grantsBonusMove(after: ordinary, completedPlayerTurns: 4, parameters: .init()))
        #expect(rule.grantsBonusMove(after: ordinary, completedPlayerTurns: 5, parameters: .init()))
        #expect(!rule.grantsBonusMove(after: ply(movingColor: .white, check: true), completedPlayerTurns: 5, parameters: .init()))
    }
}

@MainActor
struct Stage5GimmickSessionTests {
    private struct FirstAllowedOpponent: ChessOpponent {
        let name = "Test Fish"
        func bestMove(for request: OpponentRequest) async -> Move? { request.allowedMoves.first }
    }

    private struct RankedOpponent: ChessOpponent, ChessAnalysisService {
        let name = "Ranked Fish"

        func bestMove(for request: OpponentRequest) async -> Move? { request.allowedMoves.first }

        func analysisUpdates(for request: AnalysisRequest) async -> AsyncStream<PositionAnalysis> {
            AsyncStream { continuation in
                let lines = request.allowedMoves.enumerated().map { index, move in
                    AnalysisLine(
                        rank: index + 1,
                        depth: 12,
                        selectiveDepth: 14,
                        move: move,
                        score: .centipawns(index == 1 ? 0 : 100 + index),
                        principalVariation: [move],
                        elapsedMilliseconds: 5,
                        nodes: 100,
                        nodesPerSecond: 20_000,
                        tablebaseHits: 0,
                        hashFull: 0
                    )
                }
                continuation.yield(PositionAnalysis(position: request.position, lines: lines))
                continuation.finish()
            }
        }

        func cancelAnalysis() async {}
    }

    @Test func tempofishConsecutiveMoveRunsThroughTheSessionTimeline() async throws {
        let parameters = GimmickParameters(values: [GimmickParameterKey.cycle: 2])
        let session = GameSession(
            mode: .tempoFish,
            parameters: parameters,
            gameSeed: 7,
            opponent: { FirstAllowedOpponent() }
        )
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))

        let deadline = ContinuousClock.now + .seconds(2)
        while !session.isPlayerTurn, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.isPlayerTurn)

        let second = try #require(session.legalMoves.first { move in
            guard let next = ChessEngine.apply(move, to: session.position) else { return false }
            return !ChessEngine.isInCheck(next.sideToMove, in: next)
        })
        #expect(session.attemptMove(from: second.from, to: second.to))
        #expect(session.isBonusMove)
        #expect(session.isPlayerTurn)

        let bonus = try #require(session.legalMoves.first)
        #expect(session.attemptMove(from: bonus.from, to: bonus.to))
        #expect(!session.isBonusMove)
        #expect(!session.isPlayerTurn)
        session.exit()
    }

    /// `GameReplay` rebuilds a finished game from its recorded notation — with
    /// the bonus-side flips applied by hand, because no position can remember
    /// them. If that reconstruction drifted from the live session, every
    /// exported TempoFish game would replay a different board than the one that
    /// was played. The recorded notation must rebuild the exact board history.
    @Test func tempofishReplayRebuildsTheBoardsTheSessionPlayed() async throws {
        let parameters = GimmickParameters(values: [GimmickParameterKey.cycle: 2])
        let session = GameSession(
            mode: .tempoFish,
            parameters: parameters,
            gameSeed: 7,
            opponent: { FirstAllowedOpponent() }
        )
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))

        var deadline = ContinuousClock.now + .seconds(2)
        while !session.isPlayerTurn, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let second = try #require(session.legalMoves.first { move in
            guard let next = ChessEngine.apply(move, to: session.position) else { return false }
            return !ChessEngine.isInCheck(next.sideToMove, in: next)
        })
        #expect(session.attemptMove(from: second.from, to: second.to))
        #expect(session.isBonusMove)

        let bonus = try #require(session.legalMoves.first)
        #expect(session.attemptMove(from: bonus.from, to: bonus.to))

        deadline = ContinuousClock.now + .seconds(2)
        while session.moveHistory.count < 4, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.moveHistory.count == 4)

        let replay = try GameReplay(
            notation: session.moveHistory.map { ChessNotation.uci($0) }.joined(separator: " "),
            startingPosition: session.gameStartingPosition,
            mode: .tempoFish,
            playerColor: .white,
            parameters: parameters
        )
        #expect(replay.positions == session.positionHistory + [session.position])
        session.exit()
    }

    @Test func modeParametersRoundTripWithoutAffectingOtherModes() throws {
        let definition = try #require(TempoFishRule().parameterDefinitions.first)
        var settings = AppSettings.default
        settings.setParameter(7, definition: definition, for: .tempoFish)
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.parameters(for: .tempoFish, default: .init()).value(for: definition) == 7)
        #expect(restored.parameters(for: .mimicFish, default: .init())[definition.id] == nil)
    }

    @Test func levelfishUsesRankedAnalysisInsteadOfTheOpponentsOrdinaryBestMove() async throws {
        let session = GameSession(mode: .levelFish, opponent: { RankedOpponent() })
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        let expected = try #require(session.engineAllowedMoves.dropFirst().first)

        let deadline = ContinuousClock.now + .seconds(3)
        while session.moveHistory.count < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.lastMove == expected)
        session.exit()
    }

    @Test func rattlefishRunsHiddenWholeRootAnalysisWithoutSpendingIntegrity() async throws {
        let session = GameSession(mode: .rattleFish, opponent: { RankedOpponent() })
        let deadline = ContinuousClock.now + .seconds(2)
        while session.latestAnalysis == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let best = try #require(session.latestAnalysis?.bestMove)
        #expect(session.integrity.maximumCrownTier == 3)
        #expect(session.attemptMove(from: best.from, to: best.to))
        #expect(session.currentRating == OpponentRating(3_500))
        #expect(session.integrity.maximumCrownTier == 3)
        session.exit()
    }
}
