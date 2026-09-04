import Foundation
import Testing
@testable import Oddfish

/// The director's rules are almost entirely about *not* speaking. These tests
/// pin the restraint, because that is the part that decides whether a mascot is
/// liked or switched off.
@Suite(.serialized)
@MainActor
struct GuideDirectorTests {
    private static let payloadKey = "oddfish.appStore.payload"

    private func makeStore(chattiness: GuideChattiness = .full, gamesPlayed: Int = 0) -> AppStateStore {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.payloadKey)
        let store = AppStateStore(userDefaults: defaults)
        var settings = store.settings
        settings.guideChattiness = chattiness
        store.saveSettings(settings)
        for _ in 0..<gamesPlayed {
            store.recordCompletedGame(modeID: GameMode.classic.rawValue, result: .loss, duration: 30, moveCount: 10)
        }
        return store
    }

    private func move(
        side: PieceColor = .white,
        kind: PieceKind = .pawn,
        captured: PieceKind? = nil,
        givesCheck: Bool = false,
        ply: Int = 1,
        isPlayerMove: Bool? = nil
    ) -> GameEvent {
        .moveCommitted(MoveEvent(
            move: ChessEngine.legalMoves(in: .starting)[0],
            side: side,
            pieceKind: kind,
            capturedKind: captured,
            givesCheck: givesCheck,
            ply: ply,
            isPlayerMove: isPlayerMove
        ))
    }

    // MARK: - Muting

    @Test func silentMeansSilent() {
        let director = GuideDirector(store: makeStore(chattiness: .off))
        director.handle(.gameStarted(.restfish))
        director.handle(move())
        director.handle(.selectionRejected(.restingPiece(Square("f3")!, remainingTurns: 2)))
        #expect(director.utterance == nil)
    }

    @Test func heStillHasAFaceWhenMuted() {
        let director = GuideDirector(store: makeStore(chattiness: .off))
        director.handle(.gamePaused)
        // Pose is free even when speech is not — muting him should not turn him
        // into a statue.
        #expect(director.expression == .napping)
    }

    @Test func sparseKeepsRulesAndDropsFlavour() {
        let store = makeStore(chattiness: .sparse)
        let director = GuideDirector(store: store)
        director.handle(.gameStarted(.classic))

        director.handle(move(ply: 1))
        #expect(director.utterance == nil, "Flavour should be dropped at .sparse")

        director.handle(.gameStarted(.restfish))
        director.handle(move())
        #expect(director.utterance?.line.id == "teach.restfish", "A rule must still be taught at .sparse")
    }

    // MARK: - Rationing

    @Test func heDoesNotSpeakTwiceInQuickSuccession() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.classic))
        director.handle(move(ply: 1))
        let first = director.utterance
        #expect(first != nil)

        director.handle(move(side: .white, captured: .queen, ply: 3))
        // The second line is inside the minimum gap, so it is dropped rather
        // than queued behind the first.
        #expect(director.utterance?.id == first?.id)
    }

    @Test func aRuleOutranksWhateverIsAlreadyShowing() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.restfish))
        director.handle(move(ply: 1))
        #expect(director.utterance != nil)
        // Teaching ignores the gap and replaces a lower-priority line.
        #expect(director.utterance?.line.id == "teach.restfish")
    }

    @Test func heGetsQuieterTheLongerYouHaveOwnedTheApp() {
        let chatty = GuideDirector(store: makeStore(gamesPlayed: 0))
        chatty.handle(.gameStarted(.classic))
        chatty.handle(move(ply: 1))
        #expect(chatty.utterance != nil, "A new player should hear from him")

        let veteran = GuideDirector(store: makeStore(gamesPlayed: 40))
        veteran.handle(.gameStarted(.classic))
        veteran.handle(move(ply: 1))
        #expect(veteran.utterance == nil, "After 25 games he should be down to rules and endings only")
    }

    // MARK: - Once ever

    @Test func aModeIsExplainedOncePerInstall() {
        let store = makeStore()
        let first = GuideDirector(store: store)
        first.handle(.gameStarted(.rattleFish))
        first.handle(move(ply: 3))
        #expect(first.utterance?.line.id == "teach.rattlefish")
        #expect(store.hasTaught(.rattleFish))

        let second = GuideDirector(store: store)
        second.handle(.gameStarted(.rattleFish))
        second.handle(move(ply: 3))
        #expect(second.utterance == nil, "The rule must not be taught a second time")
    }

    @Test func repeatedlyTappingARestingPieceDoesNotRepeatTheLine() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.restfish))
        let square = Square("f3")!

        director.handle(.selectionRejected(.restingPiece(square, remainingTurns: 2)))
        let spoken = director.utterance
        #expect(spoken != nil)
        director.dismiss()

        // A Restfish player hits this constantly. Saying it every time is the
        // fastest way to make him hated.
        for _ in 0..<6 {
            director.handle(.selectionRejected(.restingPiece(square, remainingTurns: 2)))
        }
        #expect(director.utterance == nil)
    }

    @Test func tryingTheSameIllegalMoveTwiceEarnsOneExplanation() {
        let store = makeStore()
        let director = GuideDirector(store: store)
        director.handle(.gameStarted(.classic))
        let from = Square("c1")!
        let to = Square("c4")!

        director.handle(.selectionRejected(.illegalDestination(from: from, to: to, movingKind: .bishop)))
        #expect(director.utterance == nil, "One mistake is not a misconception")

        director.handle(.selectionRejected(.illegalDestination(from: from, to: to, movingKind: .bishop)))
        #expect(director.utterance?.line.id == "rule.moves.bishop")
        #expect(director.utterance?.line.text.contains("colour") == true)

        // Once ever, across installs of the director.
        director.dismiss()
        let later = GuideDirector(store: store)
        later.handle(.gameStarted(.classic))
        later.handle(.selectionRejected(.illegalDestination(from: from, to: to, movingKind: .bishop)))
        later.handle(.selectionRejected(.illegalDestination(from: from, to: to, movingKind: .bishop)))
        #expect(later.utterance == nil, "The same piece must not be explained twice")
    }

    @Test func anOrdinaryRejectedTapIsNeverSpokenAbout() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.classic))
        director.handle(.selectionRejected(.emptySquare(Square("e5")!)))
        director.handle(.selectionRejected(.opponentPiece(Square("e7")!)))
        // The board already shakes and plays a sound. A third signal is noise.
        #expect(director.utterance == nil)
        #expect(director.expression == .doubtful)
    }

    @Test func heStopsFlinchingAfterTwoLosses() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.classic))
        for _ in 0..<2 {
            director.handle(move(side: .black, captured: .queen, ply: 4))
            #expect(director.expression == .wince)
        }
        director.handle(move(side: .black, captured: .rook, ply: 6))
        #expect(director.expression == .doubtful, "A guide who flinches every time makes losing feel worse")
    }

    @Test func losingAPieceGetsOneSpecificSarcasticQuip() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.classic))

        director.handle(move(side: .black, captured: .knight, ply: 2))

        #expect(director.utterance?.line.id == "capture.lost.knight")
        #expect(director.utterance?.line.text.contains("knight") == true)
    }

    @Test func theCaptureQuipUsesPlayerPerspectiveNotPieceColour() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.classic))

        // A White opponent takes a Black player's rook.
        director.handle(move(side: .white, captured: .rook, ply: 2, isPlayerMove: false))

        #expect(director.utterance?.line.id == "capture.lost.rook")
    }

    // MARK: - The hinge

    @Test func theFirstEndingOffersTheHandicaps() {
        let store = makeStore()
        let director = GuideDirector(store: store)
        director.handle(.gameStarted(.classic))
        director.handle(.gameEnded(GameEndEvent(
            outcome: .checkmate(winner: .black), result: .loss,
            resigned: false, moveCount: 20, duration: 120
        )))

        let moment = director.moment
        #expect(moment?.id == "hinge.loss")
        #expect(moment?.offers == GameMode.hingeOffers)
        #expect(moment?.headline == GuideCopy.hingeLossHeadline)
    }

    @Test func resigningReachesTheSameOffer() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.classic))
        director.handle(.gameEnded(GameEndEvent(
            outcome: .ongoing, result: .loss,
            resigned: true, moveCount: 4, duration: 30
        )))
        // Someone who quits needs this more than someone who played it out.
        #expect(director.moment?.offers.isEmpty == false)
    }

    @Test func winningGetsADifferentlyTonedOffer() {
        let director = GuideDirector(store: makeStore())
        director.handle(.gameStarted(.classic))
        director.handle(.gameEnded(GameEndEvent(
            outcome: .checkmate(winner: .white), result: .win,
            resigned: false, moveCount: 30, duration: 200
        )))
        #expect(director.moment?.headline == GuideCopy.hingeWinHeadline)
    }

    @Test func theHingeHappensOnceAndThenNeverAgain() {
        let store = makeStore()
        let ending = GameEvent.gameEnded(GameEndEvent(
            outcome: .checkmate(winner: .black), result: .loss,
            resigned: false, moveCount: 20, duration: 120
        ))

        let first = GuideDirector(store: store)
        first.handle(.gameStarted(.classic))
        first.handle(ending)
        #expect(first.moment != nil)

        let second = GuideDirector(store: store)
        second.handle(.gameStarted(.classic))
        second.handle(ending)
        #expect(second.moment == nil)
        // The ordinary result line takes over from then on.
        #expect(second.utterance != nil)
    }

    @Test func aMutedGuideNeverTakesOverTheResultScreen() {
        let director = GuideDirector(store: makeStore(chattiness: .off))
        director.handle(.gameStarted(.classic))
        director.handle(.gameEnded(GameEndEvent(
            outcome: .checkmate(winner: .black), result: .loss,
            resigned: false, moveCount: 20, duration: 120
        )))
        #expect(director.moment == nil)
        #expect(director.utterance == nil)
    }

    // MARK: - The two timers

    @Test func aLongIntroductionEventuallyOffersAWayOut() async {
        let store = makeStore()
        store.advanceOnboarding(to: .bossGameInProgress)
        let director = GuideDirector(store: store)
        director.introductionPatience = .milliseconds(120)

        let session = GameSession(mode: .classic)
        director.attach(to: session)
        // Attaching during the introduction now presents the boss moment, which
        // a real player answers long before the eight-minute escape hatch.
        #expect(director.moment?.id == GuideMoment.introduction.id)
        director.dismissMoment()
        #expect(director.moment == nil)

        try? await Task.sleep(for: .milliseconds(400))
        // Being stranded in a losing position you cannot see the end of is the
        // one thing worse than losing.
        #expect(director.moment?.id == "hinge.escape")
        #expect(director.moment?.declineTitle == "Keep playing")
        director.detach()
    }

    @Test func thereIsNoEscapeHatchOutsideTheIntroduction() async {
        let store = makeStore()
        store.advanceOnboarding(to: .completed)
        let director = GuideDirector(store: store)
        director.introductionPatience = .milliseconds(120)

        let session = GameSession(mode: .classic)
        director.attach(to: session)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(director.moment == nil, "An ordinary game must never offer to end itself")
        director.detach()
    }

    @Test func sittingOnYourTurnEventuallyGetsANudge() async {
        let director = GuideDirector(store: makeStore())
        director.idlePatience = .milliseconds(120)
        director.handle(.gameStarted(.classic))
        // The board coming back to the player is what starts the clock.
        director.handle(move(side: .black, ply: 2))

        try? await Task.sleep(for: .milliseconds(400))
        #expect(director.utterance?.line.id == "ambient.idle")
        director.detach()
    }

    @Test func touchingTheBoardCancelsTheNudge() async {
        let director = GuideDirector(store: makeStore())
        director.idlePatience = .milliseconds(250)
        director.handle(.gameStarted(.classic))
        director.handle(move(side: .black, ply: 2))

        try? await Task.sleep(for: .milliseconds(80))
        // Even a rejected tap means they are still there.
        director.handle(.selectionRejected(.emptySquare(Square("e5")!)))
        try? await Task.sleep(for: .milliseconds(400))
        #expect(director.utterance == nil, "He nudged someone who was clearly still playing")
        director.detach()
    }

    // MARK: - Copy claims

    @Test func everyHandicapPitchSaysWhatChangesForTheOpponent() {
        for mode in GameMode.hingeOffers {
            let copy = GuideCopy.hingePitch(for: mode)
            #expect(!copy.pitch.isEmpty)
            #expect(!copy.whatChanges.isEmpty)
        }
    }

    @Test func aWinNamesTheRealOpponentRating() {
        let line = GuideCopy.variantWin(.rattleFish, opponentRating: 1_250)
        #expect(line.text.contains("1250 Elo"))
        #expect(GuideMoment.hinge(result: .win, opponentRating: 1_250).headline.contains("1250 Elo"))
    }

    @Test func everyLineFitsInABubble() {
        var lines: [GuideLine] = [
            GuideCopy.bossIntro, GuideCopy.bossIntroFollow, GuideCopy.firstMove,
            GuideCopy.bigCapture, GuideCopy.firstCheckAgainstYou,
            GuideCopy.idleNudge, GuideCopy.escapeHatch, GuideCopy.ordinaryDraw
        ]
        lines += GameMode.allCases.compactMap { GuideCopy.teaching(for: $0) }
        lines += PieceKind.allCases.map { GuideCopy.movesLike($0) }
        lines += PieceKind.allCases.map { GuideCopy.pieceLost($0) }
        lines += GameMode.allCases.map { GuideCopy.variantWin($0) }
        lines += GameMode.allCases.map { GuideCopy.variantLoss($0) }

        for line in lines {
            // Two lines in a bubble on a phone. Past this it starts covering
            // the board it is supposed to be talking about.
            #expect(line.text.count <= 96, "Too long for a bubble: \(line.id) — \(line.text)")
            #expect(!line.text.isEmpty)
        }
    }

    /// The detail screen prints the rule summary as its headline and this
    /// underneath it. For most of the catalogue those were the same sentence.
    @Test func noModeExplainsItselfTwiceOnItsDetailScreen() {
        for mode in GameMode.allCases {
            let subtitle = GuideCopy.detailSubtitle(for: mode)
            #expect(!subtitle.isEmpty, "\(mode.title) has no second line")
            #expect(
                subtitle != mode.ruleSummary,
                "\(mode.title) prints its rule summary as both lines"
            )
        }
    }

    @Test func lineIdentifiersAreUnique() {
        var lines: [GuideLine] = [
            GuideCopy.bossIntro, GuideCopy.bossIntroFollow, GuideCopy.firstMove,
            GuideCopy.bigCapture, GuideCopy.firstCheckAgainstYou,
            GuideCopy.idleNudge, GuideCopy.escapeHatch, GuideCopy.ordinaryDraw
        ]
        lines += GameMode.allCases.compactMap { GuideCopy.teaching(for: $0) }
        lines += PieceKind.allCases.map { GuideCopy.movesLike($0) }
        lines += PieceKind.allCases.map { GuideCopy.pieceLost($0) }
        let ids = lines.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate ids break once-ever tracking")
    }
}
