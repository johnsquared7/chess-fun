import Foundation
import Testing
@testable import Oddfish

struct AnalysisClassificationTests {
    private func line(rank: Int, move: Move, score: AnalysisScore) -> AnalysisLine {
        AnalysisLine(
            rank: rank,
            depth: 12,
            selectiveDepth: 18,
            move: move,
            score: score,
            principalVariation: [move],
            elapsedMilliseconds: 20,
            nodes: 100,
            nodesPerSecond: 5_000,
            tablebaseHits: 0,
            hashFull: 1
        )
    }

    @Test func centipawnToleranceClassifiesANearEqualMoveAsBest() throws {
        let moves = ChessEngine.legalMoves(in: .starting)
        let best = try #require(moves.first { StockfishOpponent.uciString(for: $0) == "e2e4" })
        let played = try #require(moves.first { StockfishOpponent.uciString(for: $0) == "d2d4" })
        let analysis = PositionAnalysis(position: .starting, lines: [
            line(rank: 2, move: played, score: .centipawns(18)),
            line(rank: 1, move: best, score: .centipawns(35)),
        ])

        let strict = try #require(analysis.classification(for: played, toleranceCentipawns: 15))
        let tolerant = try #require(analysis.classification(for: played, toleranceCentipawns: 20))

        #expect(strict.centipawnLoss == 17)
        #expect(!strict.isBest)
        #expect(tolerant.isBest)
        #expect(analysis.bestMove == best)
        #expect(analysis.topFive.map(\.rank) == [1, 2])
        #expect(analysis.gimmickAnalysis(for: played, toleranceCentipawns: 20)?.marksAsBest(played) == true)
    }

    @Test func mateScoresDoNotPretendToHaveACentipawnTolerance() throws {
        let moves = ChessEngine.legalMoves(in: .starting)
        let best = try #require(moves.first)
        let other = try #require(moves.dropFirst().first)
        let analysis = PositionAnalysis(position: .starting, lines: [
            line(rank: 1, move: best, score: .mate(plies: 3)),
            line(rank: 2, move: other, score: .mate(plies: 5)),
        ])

        let result = try #require(analysis.classification(for: other, toleranceCentipawns: 500))
        #expect(!result.isBest)
        #expect(result.centipawnLoss == nil)
    }

    @Test func anUnanalyzedMoveIsLeftUnclassified() throws {
        let moves = ChessEngine.legalMoves(in: .starting)
        let best = try #require(moves.first)
        let missing = try #require(moves.dropFirst().first)
        let analysis = PositionAnalysis(position: .starting, lines: [
            line(rank: 1, move: best, score: .centipawns(20)),
        ])

        #expect(analysis.classification(for: missing, toleranceCentipawns: 25) == nil)
    }
}

@MainActor
struct AnalysisSessionTests {
    private struct HangingAnalysisOpponent: ChessOpponent, ChessAnalysisService {
        let name = "Analyzer"

        func bestMove(for request: OpponentRequest) async -> Move? {
            request.allowedMoves.first
        }

        func analysisUpdates(for request: AnalysisRequest) async -> AsyncStream<PositionAnalysis> {
            AsyncStream { continuation in
                let lines = request.allowedMoves.enumerated().map { index, move in
                    AnalysisLine(
                        rank: index + 1,
                        depth: 10,
                        selectiveDepth: 12,
                        move: move,
                        score: .centipawns(100 - index * 10),
                        principalVariation: [move],
                        elapsedMilliseconds: 10,
                        nodes: 100,
                        nodesPerSecond: 10_000,
                        tablebaseHits: 0,
                        hashFull: 0
                    )
                }
                continuation.yield(PositionAnalysis(position: request.position, lines: lines))
                // Deliberately stay open. A commit must consume this cached
                // value and cancel the stream, never await its completion.
            }
        }

        func cancelAnalysis() async {}
    }

    private func waitForAnalysis(
        _ game: GameSession,
        timeout: Duration = .seconds(2)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if game.latestAnalysis != nil { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test func committingAMoveUsesTheCacheAndNeverWaitsForAnalysis() async throws {
        let game = GameSession(
            mode: .classic,
            settings: AppSettings(bestMoveToleranceCentipawns: 25, evaluationEnabled: true),
            opponent: { HangingAnalysisOpponent() }
        )
        #expect(await waitForAnalysis(game))

        let chosen = try #require(game.legalMoves.dropFirst().first)
        let started = ContinuousClock.now
        #expect(game.attemptMove(from: chosen.from, to: chosen.to))
        let elapsed = ContinuousClock.now - started

        #expect(elapsed < .milliseconds(100), "A synchronous commit took \(elapsed)")
        #expect(game.lastMoveClassification?.playedMove == chosen)
        #expect(game.lastMoveClassification?.isBest == true)
        #expect(game.latestAnalysis == nil)
        game.exit()
    }
}

extension StockfishEngineTests {
    @Test func structuredMultiPVDeliversFiveRankedLegalLines() async throws {
        let opponent = await OpponentProvider.shared()
        _ = try #require(opponent as? StockfishOpponent, "Stockfish is not available")
        let analysisService = try #require(opponent as? any ChessAnalysisService)
        let legal = ChessEngine.legalMoves(in: .starting)
        let updates = await analysisService.analysisUpdates(for: AnalysisRequest(
            position: .starting,
            allowedMoves: legal,
            targetDepth: 8,
            maximumTime: .seconds(2),
            multiPV: 5
        ))

        var final: PositionAnalysis?
        for await snapshot in updates { final = snapshot }
        let result = try #require(final)

        #expect(result.lines.count == 5)
        #expect(result.lines.map(\.rank) == [1, 2, 3, 4, 5])
        #expect(Set(result.lines.map(\.move)).count == 5)
        #expect(result.lines.allSatisfy { legal.contains($0.move) })
        #expect(result.lines.allSatisfy { $0.principalVariation.first == $0.move })
        #expect(result.depth > 0)
    }

    @Test func opponentThinkingPreemptsALongAnalysisSearch() async throws {
        let opponent = await OpponentProvider.shared()
        _ = try #require(opponent as? StockfishOpponent, "Stockfish is not available")
        let analysisService = try #require(opponent as? any ChessAnalysisService)
        let legal = ChessEngine.legalMoves(in: .starting)
        let updates = await analysisService.analysisUpdates(for: AnalysisRequest(
            position: .starting,
            allowedMoves: legal,
            targetDepth: 40,
            maximumTime: .seconds(5),
            multiPV: nil
        ))
        let consumer = Task {
            for await _ in updates {}
        }
        try? await Task.sleep(for: .milliseconds(100))

        let started = ContinuousClock.now
        let move = await opponent.bestMove(for: OpponentRequest(
            position: .starting,
            allowedMoves: legal,
            rating: .default,
            thinkingTime: .milliseconds(300)
        ))
        let elapsed = ContinuousClock.now - started
        _ = await consumer.value

        #expect(move.map(legal.contains) == true)
        #expect(elapsed < .seconds(2), "Opponent search waited behind analysis for \(elapsed)")
    }
}

struct AnalysisSettingsTests {
    @Test func toleranceDefaultsAndClampsAcrossPersistence() throws {
        var settings = AppSettings(bestMoveToleranceCentipawns: 900)
        #expect(settings.bestMoveToleranceCentipawns == 500)
        settings.bestMoveToleranceCentipawns = -20
        #expect(settings.bestMoveToleranceCentipawns == 0)

        settings.bestMoveToleranceCentipawns = 40
        let roundTrip = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )
        #expect(roundTrip.bestMoveToleranceCentipawns == 40)
    }
}
