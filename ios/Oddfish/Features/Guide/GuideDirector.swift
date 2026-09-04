import Foundation
import Observation

/// How much Gil talks. Three levels rather than a switch, because "he annoys me"
/// and "I never want to see him" are different complaints with different fixes.
nonisolated public enum GuideChattiness: String, Codable, CaseIterable, Hashable, Sendable {
    /// Everything, subject to the rate limits below.
    case full
    /// Only rules and big moments. No flavour, no encouragement.
    case sparse
    /// Silent. He is still drawn, he just never speaks.
    case off

    public var title: String {
        switch self {
        case .full: "Chatty"
        case .sparse: "Only when it matters"
        case .off: "Silent"
        }
    }
}

/// What Gil is currently saying, if anything.
nonisolated struct GuideUtterance: Equatable, Sendable, Identifiable {
    let line: GuideLine
    let priority: GuidePriority
    var id: String { line.id }
}

/// Nothing is ever queued.
///
/// A queue turns one interruption into three, and three consecutive bubbles is
/// exactly where a mascot stops being a companion and becomes something the
/// player wants to switch off. A higher priority replaces what is showing; a
/// lower one is dropped on the floor and forgotten.
nonisolated enum GuidePriority: Int, Comparable, Sendable {
    case ambient = 20
    case encourage = 40
    /// You are blocked and need to know why.
    case consequence = 60
    /// A mode's rule, the first time it bites.
    case teaching = 80
    case moment = 100

    static func < (lhs: GuidePriority, rhs: GuidePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Decides what Gil does about everything that happens in a game.
///
/// The governing rule, and the one that keeps him likeable:
/// **pose is free, speech is scarce.** He may react with his face and his body
/// to absolutely anything, as often as it happens. Text is rationed hard — by a
/// minimum gap, by a per-game ceiling that shrinks the longer the app has been
/// installed, and by once-ever flags for anything that teaches.
@MainActor
@Observable
final class GuideDirector {
    /// The line currently on screen, if any.
    private(set) var utterance: GuideUtterance?
    /// What Gil's face is doing. Changes far more often than `utterance`.
    private(set) var expression: GilExpression = .idle
    /// The three body bars, used to show a mode's rule on the character itself.
    private(set) var barLevels: [Double] = [0.80, 0.92, 0.84]
    /// A full-screen beat, if one is owed. The game screen hands its result
    /// overlay over while this is set.
    private(set) var moment: GuideMoment?

    private let store: AppStateStore
    private var mode: GameMode = .classic
    private var lastSpokeAt: ContinuousClock.Instant?
    private var spokenThisGame = 0
    private var winceCount = 0
    private var saidThisSession: Set<String> = []
    private var lastRejection: (square: Square, at: ContinuousClock.Instant)?
    private var dismissTask: Task<Void, Never>?
    private var poseResetTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var escapeHatchTask: Task<Void, Never>?

    /// How long the introduction may run before Gil offers a way out.
    /// Settable so tests do not have to wait eight minutes for it.
    var introductionPatience: Duration = .seconds(8 * 60)
    /// How long the player may sit on their own turn before he says something.
    var idlePatience: Duration = .seconds(50)

    /// The shortest gap between two lines. Long enough that a second bubble
    /// never lands while the first is still being read.
    private let minimumGap: Duration = .seconds(12)

    init(store: AppStateStore) {
        self.store = store
    }

    // MARK: - Session lifecycle

    /// Attaches to a game. Safe to call again on restart.
    func attach(to session: GameSession) {
        mode = session.mode
        spokenThisGame = 0
        winceCount = 0
        lastRejection = nil
        clearBubble()
        expression = .idle
        barLevels = Self.defaultBars
        session.onEvent = { [weak self] event in
            self?.handle(event)
        }
        startEscapeHatchIfIntroducing()
        // Anything that happened before we attached — `.gameStarted` is emitted
        // inside `GameSession.init`, before any caller can assign `onEvent`.
        for event in session.eventLog { handle(event) }
    }

    func detach() {
        clearBubble()
        poseResetTask?.cancel()
        poseResetTask = nil
        idleTask?.cancel()
        idleTask = nil
        escapeHatchTask?.cancel()
        escapeHatchTask = nil
    }

    /// The introduction is the one game a player can get stranded in: they are
    /// losing to a full-strength engine and may not know that resigning is the
    /// intended path. After a while Gil offers the exit himself.
    private func startEscapeHatchIfIntroducing() {
        escapeHatchTask?.cancel()
        guard store.onboardingStage == .bossGameInProgress,
              store.settings.guideChattiness != .off,
              !store.hasSeenBeat(GuideMoment.escapeHatch.id) else { return }

        let patience = introductionPatience
        escapeHatchTask = Task { [weak self] in
            try? await Task.sleep(for: patience)
            guard !Task.isCancelled else { return }
            self?.offerEscapeHatch()
        }
    }

    private func offerEscapeHatch() {
        // Never on top of something else, and never after the game is already
        // over — the hinge covers that case.
        guard moment == nil, store.onboardingStage == .bossGameInProgress else { return }
        store.markBeatSeen(GuideMoment.escapeHatch.id)
        clearBubble()
        setPose(.sly)
        moment = .escapeHatch
    }

    /// Restarted every time the board comes back to the player.
    private func startIdleTimer() {
        idleTask?.cancel()
        guard store.settings.guideChattiness == .full else { return }
        let patience = idlePatience
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: patience)
            guard !Task.isCancelled else { return }
            self?.speakIdleNudge()
        }
    }

    private func speakIdleNudge() {
        guard moment == nil else { return }
        speak(GuideCopy.idleNudge, priority: .ambient, onceThisSession: true)
    }

    // MARK: - Events

    func handle(_ event: GameEvent) {
        switch event {
        case .gameStarted(let startedMode):
            mode = startedMode
            barLevels = Self.defaultBars
            setPose(.idle)
            // He introduces the boss once, and only during the introduction —
            // arriving on a normal game with an unprompted line is the fastest
            // way to make a guide feel like an obstacle.
            // A persistent moment, not a timed bubble: this is the line the
            // whole product rests on and it must not expire while a cold launch
            // is still settling.
            if store.onboardingStage == .bossGameInProgress,
               store.settings.guideChattiness != .off,
               !store.hasSeenBeat(GuideMoment.introduction.id),
               moment == nil {
                store.markBeatSeen(GuideMoment.introduction.id)
                setPose(.sly)
                moment = .introduction
            }

        case .moveCommitted(let move):
            handleMove(move)

        case .selectionRejected(let reason):
            handleRejection(reason)

        case .promotionOffered:
            // A sheet already owns the screen; a bubble underneath it would be
            // talking to nobody.
            setPose(.cheer, thenIdleAfter: .seconds(2))

        case .gamePaused:
            setPose(.napping)

        case .gameResumed:
            setPose(.idle)

        case .gameEnded(let ending):
            handleEnding(ending)
        }
    }

    private func handleMove(_ move: MoveEvent) {
        idleTask?.cancel()
        if !move.isPlayerMove { startIdleTimer() }

        if move.isPlayerMove {
            if let captured = move.capturedKind {
                setPose(.cheer, thenIdleAfter: .seconds(2))
                if captured == .queen || captured == .rook {
                    speak(GuideCopy.bigCapture, priority: .encourage, onceThisSession: true)
                }
            } else if move.ply == 1 {
                setPose(.talking, thenIdleAfter: .seconds(2))
                speak(GuideCopy.firstMove, priority: .ambient, onceThisSession: true)
            }
            if mode == .restfish {
                barLevels = [1, 1, 0.12]
            }
            teachIfNeeded()
        } else {
            if move.givesCheck {
                setPose(.surprised, thenIdleAfter: .seconds(2))
                // Only while the player is new. Telling an experienced player
                // that they are in check is noise.
                if store.stats.gamesPlayed < 3 {
                    speak(GuideCopy.firstCheckAgainstYou, priority: .consequence, onceThisSession: true)
                }
            }
            if let captured = move.capturedKind {
                // Two jokes at most. Gil notices material leaving the board,
                // but does not spend the rest of the game reading the obituary.
                winceCount += 1
                if winceCount <= 2 {
                    setPose(.wince, thenIdleAfter: .seconds(2))
                    speak(
                        GuideCopy.pieceLost(captured),
                        priority: .encourage,
                        onceThisSession: true,
                        ignoringGap: true
                    )
                } else {
                    setPose(.doubtful, thenIdleAfter: .seconds(1))
                }
            }
        }
    }

    private func handleRejection(_ reason: SelectionRejection) {
        // Any touch at all means they are still here.
        idleTask?.cancel()
        switch reason {
        case .restingPiece(let square, let remaining):
            barLevels = remaining >= 2 ? [1, 1, 0.12] : [1, 0.12, 0.12]
            setPose(.talking, thenIdleAfter: .seconds(2))
            // The single most important anti-annoyance rule in the app: a
            // A Restfish player hits this constantly, and a line every time would
            // make him unbearable within one game.
            let now = ContinuousClock.now
            let isRepeat = lastRejection.map { $0.square == square && now - $0.at < .seconds(20) } ?? false
            lastRejection = (square, now)
            if !isRepeat {
                speak(
                    GuideCopy.restingPieceBlocked(remaining),
                    priority: .consequence,
                    onceThisSession: true
                )
            }

        case .illegalDestination(let from, _, let movingKind):
            // Twice from the same square means the player has a wrong idea about
            // that piece, which is worth one sentence — once, ever.
            let now = ContinuousClock.now
            let isRepeat = lastRejection.map { $0.square == from && now - $0.at < .seconds(6) } ?? false
            lastRejection = (from, now)
            setPose(.doubtful, thenIdleAfter: .seconds(1))
            if isRepeat, let kind = movingKind {
                speak(GuideCopy.movesLike(kind), priority: .teaching, onceEver: true)
            }

        case .emptySquare, .opponentPiece, .pieceHasNoMoves:
            // The board already shakes and plays an invalid cue. A third
            // simultaneous signal is noise.
            setPose(.doubtful, thenIdleAfter: .seconds(1))
        }
    }

    private func handleEnding(_ ending: GameEndEvent) {
        clearBubble()
        idleTask?.cancel()
        escapeHatchTask?.cancel()

        // The hinge: the first time a game ends, Gil offers the variants as
        // handicaps rather than letting the player conclude they are bad at
        // chess. Once ever, and never while he is muted.
        let hinge = GuideMoment.hinge(result: ending.result, opponentRating: ending.opponentRating)
        if store.settings.guideChattiness != .off, !store.hasSeenBeat(hinge.id),
           !store.hasSeenBeat("hinge.shown") {
            store.markBeatSeen(hinge.id)
            store.markBeatSeen("hinge.shown")
            store.advanceOnboarding(to: .completed)
            setPose(ending.result == .win ? .cheer : .wince)
            moment = hinge
            return
        }

        // A result screen is a stopping point rather than an interruption, so
        // the gap and the per-game ceiling are both waived here.
        switch ending.result {
        case .win:
            setPose(.cheer)
            force(GuideCopy.variantWin(mode, opponentRating: ending.opponentRating))
        case .loss:
            setPose(.wince)
            force(GuideCopy.variantLoss(mode, resigned: ending.resigned))
        default:
            setPose(.idle)
            force(GuideCopy.ordinaryDraw)
        }
    }

    private func teachIfNeeded() {
        guard let line = GuideCopy.teaching(for: mode), !store.hasTaught(mode) else { return }
        store.markModeTaught(mode)
        speak(line, priority: .teaching, ignoringGap: true)
    }

    // MARK: - Speaking

    /// How many lines Gil is allowed in one game.
    ///
    /// This shrinks with how long the app has been installed, which is the most
    /// direct answer to the way mascots actually fail: they are charming on day
    /// one and intolerable by game ten. By then he is down to rules and endings.
    private var perGameCeiling: Int {
        switch store.stats.gamesPlayed {
        case 0...2: 4
        case 3...9: 2
        case 10...24: 1
        default: 0
        }
    }

    private func speak(
        _ line: GuideLine,
        priority: GuidePriority,
        onceThisSession: Bool = false,
        onceEver: Bool = false,
        ignoringGap: Bool = false
    ) {
        let chattiness = store.settings.guideChattiness
        guard chattiness != .off else { return }
        // `.sparse` keeps the things a player would miss and drops the rest.
        if chattiness == .sparse, priority < .teaching { return }

        if onceEver {
            guard !store.hasSeenBeat(line.id) else { return }
        }
        if onceThisSession || onceEver {
            guard !saidThisSession.contains(line.id) else { return }
        }

        // Teaching and moments are worth interrupting for; nothing else is.
        if priority < .teaching {
            guard spokenThisGame < perGameCeiling else { return }
            if !ignoringGap, let lastSpokeAt, ContinuousClock.now - lastSpokeAt < minimumGap { return }
        }
        if let current = utterance, current.priority > priority { return }

        commit(GuideUtterance(line: line, priority: priority))
        if onceEver { store.markBeatSeen(line.id) }
        saidThisSession.insert(line.id)
        spokenThisGame += 1
        lastSpokeAt = ContinuousClock.now
    }

    /// Says something regardless of the rationing. Only endings and moments.
    private func force(_ line: GuideLine) {
        guard store.settings.guideChattiness != .off else { return }
        commit(GuideUtterance(line: line, priority: .moment))
    }

    private func commit(_ new: GuideUtterance) {
        utterance = new
        expression = new.line.expression
        dismissTask?.cancel()
        // Long enough to read twice, short enough that it is gone before it
        // becomes furniture. Roughly reading speed plus a beat.
        let seconds = min(9.0, 2.4 + Double(new.line.text.count) / 18.0)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        clearBubble()
        setPose(.idle)
    }

    /// Called when the player answers a moment, either way.
    func dismissMoment() {
        moment = nil
        setPose(.idle)
    }

    private func clearBubble() {
        dismissTask?.cancel()
        dismissTask = nil
        utterance = nil
    }

    // MARK: - Pose

    private func setPose(_ expression: GilExpression, thenIdleAfter delay: Duration? = nil) {
        poseResetTask?.cancel()
        self.expression = expression
        guard let delay else { return }
        poseResetTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            guard self?.utterance == nil else { return }
            self?.expression = .idle
        }
    }

    private static let defaultBars: [Double] = [0.80, 0.92, 0.84]
}
