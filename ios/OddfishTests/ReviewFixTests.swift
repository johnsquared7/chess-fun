import Foundation
import Testing
@testable import Oddfish

/// Regression cover for the defects found in the Stage 1–6 review. Each test
/// fails against the code as it stood before its fix.
struct ReviewFixTests {

    // MARK: - A bonus move can land on a stalemate

    /// Grants a bonus after every player move, so the stalemate case is
    /// reachable without depending on TempoFish's cycle parameter.
    private struct AlwaysBonusRule: GimmickRule {
        let startingPosition: Position
        func grantsBonusMove(
            after ply: GimmickPly,
            completedPlayerTurns: Int,
            parameters: GimmickParameters
        ) -> Bool { true }
    }

    /// White: Kh1, Pb2. Black: Kh8, Qg3, pawns a3/a4/b3.
    ///
    /// The king has no square (Qg3 covers g1, g2 and h2) and b2 is blocked, so
    /// White's only legal move is bxa3 — after which the pawn on a3 is blocked
    /// by a4 and White has no move at all. Handing White a bonus move there
    /// produces a stalemate on a board the outcome check has already passed.
    private static let bonusStalemateFEN = "7k/8/8/8/p7/pp4q1/1P6/7K w - - 0 1"

    @Test @MainActor func aBonusMoveThatStalematesEndsTheGame() throws {
        let start = try #require(Position(fen: Self.bonusStalemateFEN))
        let onlyMove = try #require(ChessEngine.legalMoves(in: start).first)
        #expect(ChessEngine.legalMoves(in: start).count == 1, "Fixture should offer exactly one move")

        let session = GameSession(
            mode: .classic,
            rule: AlwaysBonusRule(startingPosition: start)
        )
        #expect(session.attemptMove(from: onlyMove.from, to: onlyMove.to))

        // The bonus flipped the board back to White, who now has nothing to play.
        #expect(session.legalMoves.isEmpty)
        #expect(
            session.outcome.isTerminal,
            "A bonus move onto a stalemate left the game running with no legal move"
        )
    }

    // MARK: - MimicFish and promotion

    @Test func mimicFishCopiesThePawnNotThePromotedQueen() throws {
        let rule = MimicFishRule()
        // Player has just promoted a7-a8=Q. The square holds a queen; the piece
        // they moved was a pawn.
        // White queen a8 (just promoted), white king e1; black king h4, black
        // pawn b2. Black is not in check and has both king and pawn moves, so a
        // queen-copy and a pawn-copy give visibly different move sets.
        let position = try #require(Position(fen: "Q7/8/8/8/7k/8/1p6/4K3 b - - 0 1"))
        let promotion = Move(
            from: try #require(Square("a7")),
            to: try #require(Square("a8")),
            promotion: .queen,
            flags: []
        )
        let candidates = ChessEngine.legalMoves(in: position)
        let context = GimmickEngineContext(
            playerColor: .white,
            lastPlayerMove: promotion,
            randomSample: 0,
            engineTurn: 1
        )

        let allowed = rule.allowedEngineMoves(
            in: position,
            candidates: candidates,
            context: context,
            parameters: GimmickParameters()
        )

        // Black's pawn on b2 is the only pawn; a queen-copy would exclude it.
        let movedKinds = Set(allowed.compactMap { position.piece(at: $0.from)?.kind })
        #expect(movedKinds == [.pawn], "Expected the engine to copy the pawn, got \(movedKinds)")
    }

    // MARK: - The bottom of the dial has to be weak

    @Test func ratingsBelowTheCalibratedFloorAreActuallyWeakened() {
        // Stockfish's weakest skill setting still plays around 1320, so without
        // extra weakening GluttonFish's "starving" opening and BabyFish's
        // "total beginner" opening are both club strength.
        #expect(OpponentRating.minimum.uncalibratedRandomness > 0.5)
        #expect(OpponentRating(660).uncalibratedRandomness > 0)
        #expect(OpponentRating.lowestCalibrated.uncalibratedRandomness == 0)
        #expect(OpponentRating.maximum.uncalibratedRandomness == 0)

        // Monotonic: a lower rating is never less random than a higher one.
        let samples = stride(from: 0, through: 1_320, by: 120).map {
            OpponentRating($0).uncalibratedRandomness
        }
        #expect(samples == samples.sorted(by: >))
    }

    @Test func theTwoIncreasingEloModesStartBelowTheCalibratedFloor() {
        #expect(GluttonFishRule().startingRating == .minimum)
        #expect(BabyFishRule().startingRating == .minimum)
        #expect(GluttonFishRule().startingRating.uncalibratedRandomness > 0.5)
    }

    @Test func everyOtherModeDefaultsToFullStrength() {
        #expect(OpponentRating.default == .maximum)
        #expect(OpponentPreset.balanced.rating == OpponentRating(2_200))

        let growingModes: Set<GameMode> = [.gluttonFish, .babyFish, .comebackFish, .lastStandFish]
        for mode in GameMode.allCases where !growingModes.contains(mode) {
            #expect(mode.gimmickRule.startingRating == .maximum, "\(mode.title) did not default to full strength")
        }
    }

    // MARK: - Moments that arrive mid-game must not throw the game away

    @Test func keepPlayingDoesNotRestartTheGame() {
        // The escape hatch appears *during* the introduction game. Its decline
        // button says "Keep playing"; restarting is the opposite of that.
        #expect(GuideMoment.escapeHatch.declineAction == .dismiss)
        #expect(GuideMoment.introduction.declineAction == .dismiss)
        // The hinge arrives after a game has ended, so a fresh board is correct.
        #expect(GuideMoment.hinge(result: .loss).declineAction == .restart)
    }

    @Test func aMomentWithNoOffersStillHasAWayOut() {
        #expect(GuideMoment.introduction.offers.isEmpty)
        #expect(!GuideMoment.introduction.declineTitle.isEmpty)
    }

    // MARK: - The introduction must not expire on a timer

    @Test @MainActor func theBossIntroductionIsAPersistentMoment() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "oddfish.appStore.payload")
        let store = AppStateStore(userDefaults: defaults)
        store.advanceOnboarding(to: .bossGameInProgress)

        let director = GuideDirector(store: store)
        director.handle(.gameStarted(.classic))

        // A bubble is dismissed on a timer sized to its own text; a cold launch
        // carrying 107 MB of networks can outlast it.
        #expect(director.moment?.id == GuideMoment.introduction.id)
        #expect(director.utterance == nil, "The introduction should not be a timed bubble")
    }

    @Test @MainActor func theBossIntroductionIsShownOnlyOnce() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "oddfish.appStore.payload")
        let store = AppStateStore(userDefaults: defaults)
        store.advanceOnboarding(to: .bossGameInProgress)

        let first = GuideDirector(store: store)
        first.handle(.gameStarted(.classic))
        #expect(first.moment != nil)

        let second = GuideDirector(store: store)
        second.handle(.gameStarted(.classic))
        #expect(second.moment == nil)
    }

    @Test @MainActor func aMutedGuideNeverTakesOverTheFirstGame() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "oddfish.appStore.payload")
        let store = AppStateStore(userDefaults: defaults)
        var settings = store.settings
        settings.guideChattiness = .off
        store.saveSettings(settings)
        store.advanceOnboarding(to: .bossGameInProgress)

        let director = GuideDirector(store: store)
        director.handle(.gameStarted(.classic))
        #expect(director.moment == nil)
    }
}
