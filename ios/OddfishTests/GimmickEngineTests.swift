import Foundation
import Testing
@testable import Oddfish

struct ContinuousRatingTests {
    @Test func ratingsClampInsteadOfWrapping() {
        #expect(OpponentRating(-1) == .minimum)
        #expect(OpponentRating(3_601) == .maximum)
        #expect(OpponentRating.maximum.adjusted(by: Int.max) == .maximum)
        #expect(OpponentRating.minimum.adjusted(by: Int.min) == .minimum)
    }

    @Test func stockfishUsesThreeExplicitBands() {
        #expect(OpponentRating(0).engineBand == .skillLevel(0))
        #expect(OpponentRating(1_319).engineBand == .skillLevel(0))
        #expect(OpponentRating(1_320).engineBand == .calibratedElo(1_320))
        #expect(OpponentRating(3_190).engineBand == .calibratedElo(3_190))
        #expect(OpponentRating(3_191).engineBand == .fullStrength)
        #expect(OpponentRating(3_600).engineBand == .fullStrength)
    }

    @Test func endsOfTheDialProduceDifferentSearches() {
        let weakest = ChessBot.Configuration(rating: .minimum)
        let strongest = ChessBot.Configuration(rating: .maximum)

        #expect(weakest.depth < strongest.depth)
        #expect(weakest.variationWindow > strongest.variationWindow)
        #expect(OpponentRating.minimum.thinkingTime == .milliseconds(50))
        #expect(OpponentRating.maximum.thinkingTime == .milliseconds(2_000))
        #expect(OpponentPreset.gentle.rating.thinkingTime == .milliseconds(200))
        #expect(OpponentPreset.balanced.rating.thinkingTime == .milliseconds(500))
        #expect(OpponentPreset.sharp.rating.thinkingTime == .milliseconds(1_000))
    }
}

@MainActor
struct GimmickRuleSessionTests {
    private struct BestMovePenaltyRule: GimmickRule {
        let startingRating: OpponentRating
        let startingPosition = Position(fen: "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")!
        let parameterDefinitions = [GimmickParameterDefinition(
            id: "penalty",
            title: "Best-move penalty",
            range: 0...500,
            step: 10,
            defaultValue: 100
        )]
        let defaultParameters = GimmickParameters(values: ["penalty": 100])

        var ratingBounds: ClosedRange<OpponentRating> { .minimum ... OpponentRating(500) }

        func rating(
            after ply: GimmickPly,
            currentRating: OpponentRating,
            parameters: GimmickParameters
        ) -> OpponentRating {
            guard ply.analysis?.marksAsBest(ply.move) == true else { return currentRating }
            return currentRating.adjusted(by: -Int(parameters["penalty"] ?? 0))
        }

        func allowedEngineMoves(
            in position: Position,
            candidates: [Move],
            context: GimmickEngineContext,
            parameters: GimmickParameters
        ) -> [Move] {
            candidates.filter { $0.from == Square("e8")! }
        }
    }

    @Test func bestMoveRuleChangesTheObservedRatingAfterARealPly() {
        let rule = BestMovePenaltyRule(startingRating: OpponentRating(150))
        let session = GameSession(
            mode: .classic,
            rule: rule,
            analysisForMove: { _, move in GimmickMoveAnalysis(bestMove: move) }
        )

        #expect(session.position == rule.startingPosition)
        #expect(session.currentRating == OpponentRating(150))
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(session.currentRating == OpponentRating(50))
        #expect(!session.engineAllowedMoves.isEmpty)
        #expect(session.engineAllowedMoves.allSatisfy { $0.from == Square("e8")! })
        session.exit()
    }

    @Test func aRuleTransitionClampsAtItsLowerBound() {
        let session = GameSession(
            mode: .classic,
            rule: BestMovePenaltyRule(startingRating: OpponentRating(50)),
            analysisForMove: { _, move in GimmickMoveAnalysis(bestMove: move) }
        )

        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(session.currentRating == .minimum)
        session.exit()
    }

    @Test func restartRestoresTheRuleBoardAndStartingRating() {
        let rule = BestMovePenaltyRule(startingRating: OpponentRating(150))
        let session = GameSession(
            mode: .classic,
            rule: rule,
            analysisForMove: { _, move in GimmickMoveAnalysis(bestMove: move) }
        )
        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))

        session.restart()

        #expect(session.position == rule.startingPosition)
        #expect(session.currentRating == OpponentRating(150))
        #expect(session.moveHistory.isEmpty)
        session.exit()
    }
}
