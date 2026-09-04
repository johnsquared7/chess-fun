import Foundation
import Testing
@testable import Oddfish

struct Stage4EvaluationModelTests {
    private func line(rank: Int, move: Move, score: AnalysisScore) -> AnalysisLine {
        AnalysisLine(
            rank: rank,
            depth: 18,
            selectiveDepth: 24,
            move: move,
            score: score,
            principalVariation: [move],
            elapsedMilliseconds: 40,
            nodes: 400,
            nodesPerSecond: 10_000,
            tablebaseHits: 0,
            hashFull: 2
        )
    }

    @Test func allFiveMoveQualitiesHaveStableBoundaries() throws {
        let moves = ChessEngine.legalMoves(in: .starting)
        let best = try #require(moves.first)
        let played = try #require(moves.dropFirst().first)

        let bestAnalysis = PositionAnalysis(position: .starting, lines: [
            line(rank: 1, move: best, score: .centipawns(100))
        ])
        #expect(bestAnalysis.classification(for: best, toleranceCentipawns: 0)?.quality == .best)

        for (loss, expected) in [
            (50, MoveQuality.good),
            (51, .inaccuracy),
            (101, .mistake),
            (201, .blunder),
        ] {
            let analysis = PositionAnalysis(position: .starting, lines: [
                line(rank: 1, move: best, score: .centipawns(100)),
                line(rank: 2, move: played, score: .centipawns(100 - loss)),
            ])
            #expect(analysis.classification(for: played, toleranceCentipawns: 0)?.quality == expected)
        }
    }

    @Test func mateAndTablebaseScoresPinTheEvaluationTide() {
        #expect(AnalysisScore.mate(plies: 3).playerEvaluationFraction == 0.98)
        #expect(AnalysisScore.mate(plies: -3).playerEvaluationFraction == 0.02)
        #expect(AnalysisScore.tablebase(distance: 8).playerEvaluationFraction == 0.98)
        #expect(AnalysisScore.tablebase(distance: 0).playerEvaluationFraction == 0.5)
        #expect(AnalysisScore.centipawns(0).playerEvaluationFraction == 0.5)
    }

    @Test func analysisPreferencesClampAndRoundTrip() throws {
        var settings = AppSettings(
            evaluationEnabled: true,
            analysisDepth: 99,
            analysisTimeLimit: .noCap,
            showEvaluationBar: false,
            showMoveRanks: false,
            showMoveAnalysis: false,
            ponderEnabled: true
        )
        #expect(settings.analysisDepth == 28)
        settings.analysisDepth = 11
        #expect(settings.analysisDepth == 10)

        let restored = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(restored == settings)
        #expect(restored.analysisTimeLimit.duration == nil)
    }
}

@MainActor
struct Stage4EvaluationSessionTests {
    private actor RecordingAnalysisOpponent: ChessOpponent, ChessAnalysisService {
        nonisolated let name = "Recorder"
        private var requests: [AnalysisRequest] = []

        func bestMove(for request: OpponentRequest) async -> Move? {
            request.allowedMoves.first
        }

        func analysisUpdates(for request: AnalysisRequest) async -> AsyncStream<PositionAnalysis> {
            requests.append(request)
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        func cancelAnalysis() async {}

        func lastRequest() -> AnalysisRequest? { requests.last }
    }

    private func waitForRequest(
        from opponent: RecordingAnalysisOpponent,
        timeout: Duration = .seconds(2)
    ) async -> AnalysisRequest? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let request = await opponent.lastRequest() { return request }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await opponent.lastRequest()
    }

    @Test func visibleEvaluationUsesSelectedDepthNoCapAndAllRootMoves() async throws {
        let opponent = RecordingAnalysisOpponent()
        let session = GameSession(
            mode: .classic,
            settings: AppSettings(
                evaluationEnabled: true,
                analysisDepth: 22,
                analysisTimeLimit: .noCap
            ),
            opponent: { opponent }
        )

        let request = try #require(await waitForRequest(from: opponent))
        #expect(request.targetDepth == 22)
        #expect(request.maximumTime == nil)
        #expect(request.multiPV == nil)
        #expect(request.requestedLineCount == session.legalMoves.count)
        #expect(session.integrity.count(for: .analysis) == 1)
        #expect(session.integrity.maximumCrownTier == 2)
        session.exit()
    }

    @Test func hiddenPonderRequestsOneLineWithoutSpendingAnalysisIntegrity() async throws {
        let opponent = RecordingAnalysisOpponent()
        let session = GameSession(
            mode: .classic,
            settings: AppSettings(evaluationEnabled: false, ponderEnabled: true),
            opponent: { opponent }
        )

        let request = try #require(await waitForRequest(from: opponent))
        #expect(request.multiPV == 1)
        #expect(request.requestedLineCount == 1)
        #expect(session.integrity.count(for: .analysis) == 0)
        #expect(session.integrity.maximumCrownTier == 3)
        session.exit()
    }

    @Test func enablingEvaluationDuringEngineBootIsRemembered() async throws {
        let opponent = RecordingAnalysisOpponent()
        let session = GameSession(
            mode: .classic,
            settings: .default,
            opponent: {
                try? await Task.sleep(for: .milliseconds(300))
                return opponent
            }
        )
        var updated = AppSettings.default
        updated.evaluationEnabled = true
        session.applySettings(updated)

        let request = try #require(await waitForRequest(from: opponent))
        #expect(request.multiPV == nil)
        #expect(session.integrity.count(for: .analysis) == 1)
        session.exit()
    }

    @Test func changingAnalysisSettingsAfterACommitLowersIntegrityButNeverBlocksTheMove() throws {
        let session = GameSession(mode: .classic)
        let move = try #require(session.legalMoves.first)
        let started = ContinuousClock.now
        #expect(session.attemptMove(from: move.from, to: move.to))
        #expect(ContinuousClock.now - started < .milliseconds(100))

        var updated = AppSettings.default
        updated.analysisDepth = 20
        session.applySettings(updated)
        #expect(session.integrity.count(for: .settingChange) == 1)
        #expect(session.integrity.maximumCrownTier == 2)
        session.exit()
    }
}

extension StockfishEngineTests {
    @MainActor
    @Test func aLiveSessionStartsAnalysisWhenEvaluationIsEnabledAfterLaunch() async {
        let session = GameSession(
            mode: .classic,
            settings: .default,
            opponent: { await OpponentProvider.shared() }
        )
        var updated = AppSettings.default
        updated.evaluationEnabled = true
        session.applySettings(updated)

        let deadline = ContinuousClock.now + .seconds(8)
        while session.latestAnalysis == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.latestAnalysis != nil)
        #expect(session.evaluationScore != nil)
        session.exit()
    }

    @MainActor
    @Test func aLiveSessionRestartsAnalysisAfterEvaluationIsHiddenAndShown() async {
        let session = GameSession(
            mode: .classic,
            settings: AppSettings(evaluationEnabled: true),
            opponent: { await OpponentProvider.shared() }
        )
        let firstDeadline = ContinuousClock.now + .seconds(5)
        while session.latestAnalysis == nil, ContinuousClock.now < firstDeadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.latestAnalysis != nil)

        var hidden = AppSettings.default
        hidden.evaluationEnabled = false
        session.applySettings(hidden)
        #expect(session.latestAnalysis == nil)

        var shown = hidden
        shown.evaluationEnabled = true
        session.applySettings(shown)
        let secondDeadline = ContinuousClock.now + .seconds(5)
        while session.latestAnalysis == nil, ContinuousClock.now < secondDeadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(session.latestAnalysis != nil)
        session.exit()
    }

    @Test func oneSecondWholeRootAnalysisDeliversAUsableSnapshot() async throws {
        let opponent = await OpponentProvider.shared()
        let analysisService = try #require(opponent as? any ChessAnalysisService)
        let legal = ChessEngine.legalMoves(in: .starting)
        let updates = await analysisService.analysisUpdates(for: AnalysisRequest(
            position: .starting,
            allowedMoves: legal,
            targetDepth: 14,
            maximumTime: .seconds(1),
            multiPV: nil
        ))

        var final: PositionAnalysis?
        for await snapshot in updates { final = snapshot }
        #expect(final != nil)
        #expect(final?.lines.count == legal.count)
    }

    @Test func depthOnlyAnalysisHasNoMovetimeCapAndStillCompletes() async throws {
        let opponent = await OpponentProvider.shared()
        let analysisService = try #require(opponent as? any ChessAnalysisService)
        let legal = ChessEngine.legalMoves(in: .starting)
        let updates = await analysisService.analysisUpdates(for: AnalysisRequest(
            position: .starting,
            allowedMoves: legal,
            targetDepth: 6,
            maximumTime: nil,
            multiPV: 1
        ))

        var final: PositionAnalysis?
        for await snapshot in updates { final = snapshot }
        #expect(final?.depth == 6)
        #expect(final?.lines.count == 1)
    }
}
