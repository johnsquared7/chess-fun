import Foundation
import Observation

@Observable
@MainActor
final class GameSession {
    let mode: GameMode
    let rule: any GimmickRule
    private(set) var parameters: GimmickParameters
    let startingRating: OpponentRating
    private(set) var playerColor: PieceColor

    private(set) var position: Position
    private(set) var currentRating: OpponentRating
    private(set) var variantState: VariantState
    private(set) var moveHistory: [Move] = []
    private(set) var positionHistory: [Position] = []
    private(set) var lastMove: Move?
    private(set) var outcome: GameOutcome = .ongoing
    private(set) var selectedSquare: Square?
    private(set) var promotionChoices: [Move] = []
    private(set) var isBotThinking = false
    private(set) var isPaused = false
    /// True only for the consecutive player move granted by TempoFish.
    private(set) var isBonusMove = false
    private(set) var completedPlayerTurns = 0
    private(set) var invalidMoveNonce = 0
    private(set) var resigned = false
    /// The immutable history entry produced at the terminal boundary. Keeping
    /// it on the session lets the result surface show the exact saved award.
    private(set) var completionRecord: GameRecord?
    /// Most recent immutable snapshot for the current player-turn position.
    private(set) var latestAnalysis: PositionAnalysis?
    /// Classification of the player's last move, retained after the root
    /// snapshot is cleared for the opponent's turn.
    private(set) var lastMoveClassification: MoveClassification?
    /// Most recently trustworthy player-relative score. Unlike the current
    /// root snapshot, this remains available while the opponent replies so the
    /// evaluation tide does not blink out between turns.
    private(set) var evaluationScore: AnalysisScore?
    private(set) var isAnalyzing = false
    /// Audit of non-move actions in this game. Snapshot restoration never rolls
    /// this back: once an aid was used, it remains part of the game's integrity.
    private(set) var integrity = GameIntegrity()
    /// The audit belonging to the board replaced by the most recent restart.
    private(set) var previousGameIntegrity: GameIntegrity?
    /// Who the player is up against. Becomes the engine's name once it resolves.
    private(set) var opponentName = LocalOpponent().name

    /// Called for every `GameEvent`, on the main actor. Assign it after `init`;
    /// anything emitted during construction is still available in `eventLog`.
    var onEvent: ((GameEvent) -> Void)?
    /// Bounded replay buffer, so a listener that attaches after construction can
    /// still see how the game began.
    private(set) var eventLog: [GameEvent] = []

    @ObservationIgnored private var notationCache: (plies: Int, position: Position, values: [String])?

    private let feedback: any FeedbackService
    /// Resolved on first use, so a game can start while the engine is still
    /// booting instead of silently falling back to the built-in search.
    private let makeOpponent: OpponentResolver
    private var opponent: (any ChessOpponent)?
    private var analysisService: (any ChessAnalysisService)?
    private var settings: AppSettings
    private let analysisForMove: (Position, Move) -> GimmickMoveAnalysis?
    private let recordCompletion: ((GameRecord) -> Void)?
    private let gameSeed: UInt64
    /// The position this game began from. Readable so the board chrome can
    /// work out what has been captured — a custom starting army means the
    /// standard sixteen-a-side assumption is wrong.
    private(set) var gameStartingPosition: Position
    private var gameStartingParameters: GimmickParameters
    private var completedEngineTurns = 0
    private var didRecordCompletion = false
    private var startedAt = Date()
    private let onSnapshot: ((GameSnapshot?) -> Void)?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var botTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var analysisReadinessTask: Task<Void, Never>?
    private var analysisRetryTask: Task<Void, Never>?
    private var emptyAnalysisRetryCount = 0
    /// Rating rules whose analysis was not ready at commit time, keyed by ply.
    private var deferredRatingTasks: [Int: Task<Void, Never>] = [:]
    private var didResolveAnalysisService = false
    private var lifecycle = UUID()
    private var timeline: [PlySnapshot] = []
    private var timelineIndex = 0
    private static let eventLogLimit = 32

    /// A position alone cannot restore Restfish rests, a live rating, or
    /// repetition history. Timeline entries capture every gameplay value that
    /// changes at a ply boundary.
    private struct PlySnapshot: Hashable, Sendable {
        let position: Position
        /// Mutable so a rating settled after the fact — see
        /// `resolveRatingLater` — reaches the entry undo would return to.
        var currentRating: OpponentRating
        let variantState: VariantState
        let moveHistory: [Move]
        let positionHistory: [Position]
        let lastMove: Move?
        let outcome: GameOutcome
        let lastMoveClassification: MoveClassification?
        let evaluationScore: AnalysisScore?
        let isBonusMove: Bool
        let completedPlayerTurns: Int
        let completedEngineTurns: Int
    }

    init(
        mode: GameMode,
        rating: OpponentRating? = nil,
        rule: (any GimmickRule)? = nil,
        parameters: GimmickParameters? = nil,
        playerColor: PieceColor? = nil,
        gameSeed: UInt64 = UInt64.random(in: UInt64.min ... UInt64.max),
        analysisForMove: @escaping (Position, Move) -> GimmickMoveAnalysis? = { _, _ in nil },
        settings: AppSettings = .default,
        feedback: (any FeedbackService)? = nil,
        opponent: @escaping OpponentResolver = { LocalOpponent() },
        onRecord: ((GameRecord) -> Void)? = nil,
        /// Called whenever the game reaches a resumable state, and with nil the
        /// moment it stops being worth resuming. A phone call mid-game used to
        /// throw the whole game away.
        onSnapshot: ((GameSnapshot?) -> Void)? = nil,
        /// A game to continue instead of starting a new one.
        restoring restored: GameSnapshot? = nil
    ) {
        let resolvedRule = rule ?? mode.gimmickRule
        let resolvedPlayerColor = playerColor ?? settings.playerColor
        let resolvedRating = (rating ?? settings.rating(for: mode, default: resolvedRule.startingRating))
            .clamped(to: resolvedRule.ratingBounds)
        let resolvedParameters = parameters ?? settings.parameters(for: mode, default: resolvedRule.defaultParameters)
        let resolvedPosition = resolvedRule.startingPosition(playerColor: resolvedPlayerColor, seed: gameSeed)
        // A snapshot only takes over when it is complete and self-consistent.
        // Anything doubtful starts a fresh game rather than a corrupted one.
        let resume = restored.flatMap { $0.isResumable && $0.modeID == mode.rawValue ? $0 : nil }
        self.mode = mode
        self.rule = resolvedRule
        self.parameters = resume?.parameters ?? resolvedParameters
        self.startingRating = resume?.startingRating ?? resolvedRating
        self.currentRating = resume?.currentRating ?? resolvedRating
        self.position = resume?.position ?? resolvedPosition
        self.variantState = resume?.variantState ?? VariantState()
        self.settings = settings
        self.playerColor = resume?.playerColor ?? resolvedPlayerColor
        self.gameSeed = resume?.gameSeed ?? gameSeed
        self.gameStartingPosition = resume?.startingPosition ?? resolvedPosition
        self.gameStartingParameters = resume?.startingParameters ?? resolvedParameters
        self.onSnapshot = onSnapshot
        self.analysisForMove = analysisForMove
        self.feedback = feedback ?? NullFeedbackService()
        // The built-in search is the default so tests and previews never depend
        // on an engine process being available.
        self.makeOpponent = opponent
        self.recordCompletion = onRecord
        if let resume {
            moveHistory = resume.moveHistory
            positionHistory = resume.positionHistory
            lastMove = resume.moveHistory.last
            completedPlayerTurns = resume.completedPlayerTurns
            completedEngineTurns = resume.completedEngineTurns
            isBonusMove = resume.isBonusMove
            integrity = resume.integrity
            // Elapsed time is carried by shifting the start, so `elapsedDuration`
            // keeps working without a second notion of "time so far".
            startedAt = Date().addingTimeInterval(-resume.elapsed)
        }
        if settings.evaluationEnabled {
            integrity.record(.analysis)
        }
        resetTimeline()
        emit(.gameStarted(mode))
        startOpponentGame()
    }


    /// Standard algebraic notation for every played move, cached.
    ///
    /// SAN needs a legal-move generation per move to know whether a piece has
    /// to be disambiguated, so building the list is linear in the game length.
    /// The in-game move tape reads it on every view update, which turned a
    /// once-per-move cost into a once-per-frame one; the cache puts it back.
    ///
    /// The key includes the current position, not just the ply count, because
    /// undoing a move and playing a different one leaves the count unchanged.
    /// It holds the position itself rather than its FEN: the key is rebuilt on
    /// every view update, and serialising a board to a string to compare it was
    /// more expensive than comparing the board.
    var moveNotation: [String] {
        if let notationCache, notationCache.plies == moveHistory.count, notationCache.position == position {
            return notationCache.values
        }
        var values: [String] = []
        values.reserveCapacity(moveHistory.count)
        for (index, move) in moveHistory.enumerated() where index < positionHistory.count {
            values.append(ChessNotation.san(for: move, in: positionHistory[index]))
        }
        notationCache = (moveHistory.count, position, values)
        return values
    }

    var isPlayerTurn: Bool { position.sideToMove == playerColor }
    var opponentColor: PieceColor { playerColor.opponent }
    var materialBalance: Int { position.materialBalance(for: playerColor) }
    var ratingDelta: Int { currentRating.rawValue - startingRating.rawValue }
    var crownScoreForCurrentRun: CrownScore {
        mode.crownScore(startingRating: startingRating, parameters: gameStartingParameters)
    }
    var isCrownStartingRatingEligible: Bool { mode.crownRule.accepts(startingRating) }
    var canUndo: Bool {
        !outcome.isTerminal && !resigned && undoTargetIndex != nil
    }
    var canRedo: Bool {
        !outcome.isTerminal && !resigned && timelineIndex < timeline.count - 1
    }
    var isInputEnabled: Bool {
        !outcome.isTerminal && !resigned && !isPaused && !isBotThinking && isPlayerTurn && promotionChoices.isEmpty
    }
    var legalMoves: [Move] {
        VariantRules.legalMoves(in: position, state: variantState, configuration: mode.configuration)
    }
    var engineAllowedMoves: [Move] {
        let candidates = legalMoves
        let legal = Set(candidates)
        var seen: Set<Move> = []
        return rule.allowedEngineMoves(
            in: position,
            candidates: candidates,
            context: engineContext,
            parameters: parameters
        ).filter { legal.contains($0) && seen.insert($0).inserted }
    }
    private var engineContext: GimmickEngineContext {
        let playerMove: Move?
        if let lastMove,
           let previous = positionHistory.last,
           previous.piece(at: lastMove.from)?.color == playerColor {
            playerMove = lastMove
        } else {
            playerMove = nil
        }
        return GimmickEngineContext(
            playerColor: playerColor,
            lastPlayerMove: playerMove,
            randomSample: stableRandomSample,
            engineTurn: completedEngineTurns
        )
    }

    private var stableRandomSample: UInt64 {
        var hash = UInt64(14_695_981_039_346_656_037) ^ gameSeed
        for byte in position.fen.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        hash ^= UInt64(completedEngineTurns)
        hash &*= 1_099_511_628_211
        return hash
    }
    var selectedMoves: [Move] {
        guard let selectedSquare else { return [] }
        return legalMoves.filter { $0.from == selectedSquare }
    }
    var bonusMoveProgress: (completed: Int, target: Int)? {
        guard let definition = rule.parameterDefinitions.first(where: { $0.id == GimmickParameterKey.cycle }) else { return nil }
        return (completedPlayerTurns % Int(parameters.value(for: definition)), Int(parameters.value(for: definition)))
    }
    var elapsedDuration: TimeInterval {
        let end = pausedAt ?? Date()
        return max(0, end.timeIntervalSince(startedAt) - pausedDuration)
    }

    func handleTap(on square: Square) {
        guard isInputEnabled else { return }
        if let selectedSquare {
            if square == selectedSquare {
                self.selectedSquare = nil
                return
            }
            if attemptMove(from: selectedSquare, to: square) { return }
            if let piece = position.piece(at: square), piece.color == playerColor,
               legalMoves.contains(where: { $0.from == square }) {
                self.selectedSquare = square
                feedback.play(.selection, settings: settings)
            } else {
                rejectMove(.illegalDestination(from: selectedSquare, to: square, movingKind: position.piece(at: selectedSquare)?.kind))
            }
            return
        }
        select(square)
    }

    func beginDrag(from square: Square) {
        guard isInputEnabled else { return }
        guard canSelect(square) else { return }
        selectedSquare = square
        feedback.play(.selection, settings: settings)
    }

    @discardableResult
    func attemptDragMove(from: Square, to: Square) -> Bool {
        let succeeded = attemptMove(from: from, to: to)
        if !succeeded { rejectMove(.illegalDestination(from: from, to: to, movingKind: position.piece(at: from)?.kind)) }
        return succeeded
    }

    /// The only move-commit path used by both destination taps and drops.
    @discardableResult
    func attemptMove(from: Square, to: Square) -> Bool {
        guard isInputEnabled else { return false }
        let choices = legalMoves.filter { $0.from == from && $0.to == to }
        guard !choices.isEmpty else { return false }
        if choices.contains(where: { $0.promotion != nil }) {
            if settings.autoQueen, let queenMove = choices.first(where: { $0.promotion == .queen }) {
                commit(queenMove)
                return true
            }
            promotionChoices = choices
            selectedSquare = nil
            emit(.promotionOffered)
            return true
        }
        commit(choices[0])
        return true
    }

    func choosePromotion(_ kind: PieceKind) {
        guard let move = promotionChoices.first(where: { $0.promotion == kind }) else { return }
        promotionChoices = []
        commit(move)
    }

    func cancelPromotion() {
        selectedSquare = promotionChoices.first?.from
        promotionChoices = []
    }

    func pause() {
        guard !outcome.isTerminal, !resigned, !isPaused else { return }
        defer { publishSnapshot() }
        integrity.record(.pause)
        isPaused = true
        pausedAt = Date()
        botTask?.cancel()
        cancelAnalysis(clearSnapshot: false)
        botTask = nil
        isBotThinking = false
        emit(.gamePaused)
    }

    func resume() {
        guard isPaused, !outcome.isTerminal, !resigned else { return }
        defer { publishSnapshot() }
        integrity.record(.resume)
        if let pausedAt { pausedDuration += Date().timeIntervalSince(pausedAt) }
        pausedAt = nil
        isPaused = false
        emit(.gameResumed)
        if isPlayerTurn {
            scheduleAnalysis()
        } else {
            scheduleBot()
        }
    }

    func restart(as newPlayerColor: PieceColor? = nil) {
        defer { publishSnapshot() }
        integrity.record(newPlayerColor.map { $0 != playerColor } == true ? .sideChange : .restart)
        previousGameIntegrity = integrity
        integrity = GameIntegrity()
        if settings.evaluationEnabled {
            integrity.record(.analysis)
        }
        cancelTasks()
        lifecycle = UUID()
        if let newPlayerColor { playerColor = newPlayerColor }
        position = rule.startingPosition(playerColor: playerColor, seed: gameSeed)
        gameStartingPosition = position
        gameStartingParameters = parameters
        currentRating = startingRating
        variantState = VariantState()
        moveHistory = []
        positionHistory = []
        lastMove = nil
        latestAnalysis = nil
        lastMoveClassification = nil
        evaluationScore = nil
        outcome = .ongoing
        selectedSquare = nil
        promotionChoices = []
        isBotThinking = false
        isPaused = false
        resigned = false
        completionRecord = nil
        didRecordCompletion = false
        startedAt = Date()
        pausedAt = nil
        pausedDuration = 0
        isBonusMove = false
        completedPlayerTurns = 0
        completedEngineTurns = 0
        eventLog.removeAll(keepingCapacity: true)
        resetTimeline()
        emit(.gameStarted(mode))
        startOpponentGame()
    }

    func undo() {
        guard canUndo, let target = undoTargetIndex else { return }
        defer { publishSnapshot() }
        integrity.record(.undo)
        restoreSnapshot(at: target)
    }

    func redo() {
        guard canRedo else { return }
        defer { publishSnapshot() }
        integrity.record(.redo)
        let later = ((timelineIndex + 1)..<timeline.count)
        let target = later.first(where: { timeline[$0].position.sideToMove == playerColor })
            ?? (timeline.count - 1)
        restoreSnapshot(at: target)
    }

    /// Stage 4 and future live settings use the same audit boundary as today's
    /// controls instead of mutating `integrity` from presentation code.
    func recordControlUse(_ control: GameControl) {
        defer { publishSnapshot() }
        integrity.record(control)
    }

    /// Applies the live analysis surface without rebuilding the session. Search
    /// work is restarted only when its limits or line count changed;
    /// presentation toggles can reveal an already-delivered snapshot.
    func applySettings(_ updated: AppSettings) {
        guard updated != settings else { return }
        defer { publishSnapshot() }
        let previous = settings
        let searchChanged = previous.evaluationEnabled != updated.evaluationEnabled
            || previous.ponderEnabled != updated.ponderEnabled
            || previous.analysisDepth != updated.analysisDepth
            || previous.analysisTimeLimit != updated.analysisTimeLimit
        let updatedParameters = updated.parameters(for: mode, default: rule.defaultParameters)
        let parametersChanged = updatedParameters != parameters
        let revealedAssistance = updated.evaluationEnabled && (
            !previous.evaluationEnabled
                || (!previous.showEvaluationBar && updated.showEvaluationBar)
                || (!previous.showMoveRanks && updated.showMoveRanks)
                || (!previous.showMoveAnalysis && updated.showMoveAnalysis)
        )

        if !moveHistory.isEmpty {
            integrity.record(.settingChange)
        }
        if revealedAssistance {
            integrity.record(.analysis)
        }

        settings = updated
        parameters = updatedParameters
        guard searchChanged || parametersChanged else { return }
        emptyAnalysisRetryCount = 0
        cancelAnalysis(clearSnapshot: true)
        if parametersChanged, position.sideToMove == opponentColor {
            botTask?.cancel()
            isBotThinking = false
            scheduleBot()
        }
        if shouldAnalyzePosition {
            scheduleAnalysis()
        } else {
            evaluationScore = nil
        }
    }

    func resign() {
        defer { publishSnapshot() }
        guard !outcome.isTerminal, !resigned else { return }
        integrity.record(.resign)
        cancelTasks()
        resigned = true
        selectedSquare = nil
        promotionChoices = []
        recordCompletionIfNeeded(result: .loss)
        feedback.play(.loss, settings: settings)
        emit(.gameEnded(GameEndEvent(
            outcome: outcome,
            result: .loss,
            resigned: true,
            moveCount: moveHistory.count,
            duration: elapsedDuration,
            opponentRating: currentRating.rawValue
        )))
    }

    func exit() {
        integrity.record(.exit)
        // Leaving is an explicit discard, not an interruption. Invalidate the
        // lifecycle as well as cancelling known tasks so the unstructured
        // opponent-startup task cannot schedule work after the store is cleared.
        lifecycle = UUID()
        cancelTasks()
        onSnapshot?(nil)
    }

    private func select(_ square: Square) {
        guard canSelect(square) else { return }
        selectedSquare = square
        feedback.play(.selection, settings: settings)
    }

    /// Shared gate for taps and drag lifts, so both reject for the same reason
    /// and report it the same way.
    private func canSelect(_ square: Square) -> Bool {
        guard let piece = position.piece(at: square) else {
            rejectMove(.emptySquare(square))
            return false
        }
        guard piece.color == playerColor else {
            rejectMove(.opponentPiece(square))
            return false
        }
        guard legalMoves.contains(where: { $0.from == square }) else {
            let resting = variantState.restTurns(at: square)
            rejectMove(resting > 0
                ? .restingPiece(square, remainingTurns: resting)
                : .pieceHasNoMoves(square))
            return false
        }
        return true
    }

    private func rejectMove(_ reason: SelectionRejection) {
        invalidMoveNonce &+= 1
        feedback.play(.invalid, settings: settings)
        emit(.selectionRejected(reason))
    }

    private func commit(_ move: Move) {
        guard let movingPiece = position.piece(at: move.from),
              let next = ChessEngine.apply(move, to: position) else {
            // Defensive: every caller filters through `legalMoves` first, so
            // reaching here means the move and the board disagree.
            rejectMove(.illegalDestination(from: move.from, to: move.to, movingKind: position.piece(at: move.from)?.kind))
            return
        }
        let wasCapture = move.isCapture
        let oldPosition = position
        let givesCheck = ChessEngine.isInCheck(next.sideToMove, in: next)
        let cachedClassification: MoveClassification?
        let cachedGimmickAnalysis: GimmickMoveAnalysis?
        if movingPiece.color == playerColor, latestAnalysis?.position == oldPosition {
            cachedClassification = latestAnalysis?.classification(
                for: move,
                toleranceCentipawns: settings.bestMoveToleranceCentipawns
            )
            cachedGimmickAnalysis = latestAnalysis?.gimmickAnalysis(
                for: move,
                toleranceCentipawns: gimmickTolerance
            )
        } else {
            cachedClassification = nil
            cachedGimmickAnalysis = nil
        }
        if movingPiece.color == playerColor {
            lastMoveClassification = cachedClassification
            if let cachedClassification {
                evaluationScore = cachedClassification.playedScore
            }
        }
        let analysis = analysisForMove(oldPosition, move) ?? cachedGimmickAnalysis
        // Cancelling never awaits Stockfish. From this line onward the board
        // commit is ordinary synchronous game-state work.
        cancelAnalysis(clearSnapshot: true)
        positionHistory.append(oldPosition)
        variantState = VariantRules.applying(move, in: oldPosition, state: variantState, configuration: mode.configuration)
        position = next
        moveHistory.append(move)
        lastMove = move
        selectedSquare = nil
        promotionChoices = []
        let ply = GimmickPly(
            move: move,
            movingPiece: movingPiece,
            positionBefore: oldPosition,
            positionAfter: next,
            ply: moveHistory.count,
            wasCapture: wasCapture,
            givesCheck: givesCheck,
            analysis: analysis,
            playerColor: playerColor
        )
        currentRating = rule.rating(
            after: ply,
            currentRating: currentRating,
            parameters: parameters
        ).clamped(to: rule.ratingBounds)
        if movingPiece.color == playerColor, rule.requiresPlayerAnalysis, analysis == nil {
            resolveRatingLater(for: ply, tolerance: gimmickTolerance)
        }
        let wasBonusTurn = isBonusMove
        if movingPiece.color == playerColor {
            if wasBonusTurn {
                isBonusMove = false
            } else {
                completedPlayerTurns += 1
            }
        } else {
            completedEngineTurns += 1
        }
        feedback.play(wasCapture ? .capture : .move, settings: settings)

        emit(.moveCommitted(MoveEvent(
            move: move,
            side: movingPiece.color,
            pieceKind: movingPiece.kind,
            capturedKind: capturedKind(of: move, in: oldPosition),
            givesCheck: givesCheck,
            ply: moveHistory.count,
            isPlayerMove: movingPiece.color == playerColor
        )))
        evaluateOutcomeAfterMove()
        if outcome.isTerminal {
            appendTimelineSnapshot()
            return
        }
        if movingPiece.color == playerColor,
           !wasBonusTurn,
           rule.grantsBonusMove(
               after: ply,
               completedPlayerTurns: completedPlayerTurns,
               parameters: parameters
           ) {
            position = position.replacingSideToMove(playerColor, clearEnPassant: true)
            isBonusMove = true
            // The bonus board is a different position with a different side to
            // move. The evaluation above answered for the opponent, so without
            // this a bonus that lands on a stalemate leaves the game running
            // with the player to move and no legal move to make.
            evaluateOutcomeAfterMove()
            if outcome.isTerminal {
                appendTimelineSnapshot()
                return
            }
        }
        appendTimelineSnapshot()
        if ChessEngine.isInCheck(position.sideToMove, in: position) {
            feedback.play(.check, settings: settings)
        }
        if isPlayerTurn {
            scheduleAnalysis()
        } else {
            scheduleBot()
        }
    }

    /// The game as something that can be written to disk and read back.
    var snapshot: GameSnapshot {
        GameSnapshot(
            modeID: mode.rawValue,
            playerColor: playerColor,
            startingRating: startingRating,
            currentRating: currentRating,
            parameters: parameters,
            startingParameters: gameStartingParameters,
            gameSeed: gameSeed,
            startingFEN: gameStartingPosition.fen,
            currentFEN: position.fen,
            historyFENs: positionHistory.map(\.fen),
            moveHistory: moveHistory,
            variantState: variantState,
            completedPlayerTurns: completedPlayerTurns,
            completedEngineTurns: completedEngineTurns,
            isBonusMove: isBonusMove,
            integrity: integrity,
            elapsed: elapsedDuration
        )
    }

    /// Publishes the game, or clears it once there is nothing worth resuming.
    ///
    /// A finished, resigned or untouched game is deliberately cleared: offering
    /// to resume a game that is over would be worse than not offering at all.
    private func publishSnapshot() {
        guard let onSnapshot else { return }
        let candidate = snapshot
        let worthKeeping = !outcome.isTerminal && !resigned && candidate.isResumable
        onSnapshot(worthKeeping ? candidate : nil)
    }

    /// The rule's own best-move tolerance, falling back to the display setting.
    private var gimmickTolerance: Int {
        rule.parameterDefinitions
            .first(where: { $0.id == GimmickParameterKey.tolerance })
            .map { Int(parameters.value(for: $0).rounded()) }
            ?? settings.bestMoveToleranceCentipawns
    }

    /// Settles a rating rule that needed analysis the board did not have yet.
    ///
    /// A commit must never wait for Stockfish, so a player moving faster than
    /// the analysis stream — or moving at all while the 107 MB networks are
    /// still loading — would otherwise skip the mode's entire mechanic in
    /// silence. In RattleFish, whose crown metric is "lowest Elo lost per best
    /// move", a skipped drop quietly *improves* the recorded score, so the
    /// scoreboard would reward moving fast over playing well.
    ///
    /// The adjustment is applied to whatever the rating is when the answer
    /// arrives. Every rating rule is a relative delta, so a late arrival lands
    /// on the same number it would have had.
    private func resolveRatingLater(for ply: GimmickPly, tolerance: Int) {
        guard deferredRatingTasks[ply.ply] == nil else { return }
        let token = lifecycle
        deferredRatingTasks[ply.ply] = Task { [weak self] in
            guard let self else { return }
            let opponent = await self.resolveOpponent()
            guard !Task.isCancelled,
                  self.lifecycle == token,
                  let service = opponent as? any ChessAnalysisService else {
                self.deferredRatingTasks[ply.ply] = nil
                return
            }
            // Deliberately short. This runs behind whatever the live board is
            // analysing, and must not starve it.
            let request = AnalysisRequest(
                position: ply.positionBefore,
                allowedMoves: ChessEngine.legalMoves(in: ply.positionBefore),
                targetDepth: 12,
                maximumTime: .milliseconds(400),
                multiPV: nil
            )
            var latest: PositionAnalysis?
            for await snapshot in await service.analysisUpdates(for: request) {
                guard !Task.isCancelled else { break }
                latest = snapshot
            }
            guard !Task.isCancelled, self.lifecycle == token else {
                self.deferredRatingTasks[ply.ply] = nil
                return
            }
            defer { self.deferredRatingTasks[ply.ply] = nil }
            guard let resolved = latest?.gimmickAnalysis(
                for: ply.move,
                toleranceCentipawns: tolerance
            ) else { return }

            let settled = GimmickPly(
                move: ply.move,
                movingPiece: ply.movingPiece,
                positionBefore: ply.positionBefore,
                positionAfter: ply.positionAfter,
                ply: ply.ply,
                wasCapture: ply.wasCapture,
                givesCheck: ply.givesCheck,
                analysis: resolved,
                playerColor: ply.playerColor
            )
            self.currentRating = self.rule.rating(
                after: settled,
                currentRating: self.currentRating,
                parameters: self.parameters
            ).clamped(to: self.rule.ratingBounds)
            self.refreshTimelineRating()
            self.publishSnapshot()
        }
    }

    /// The live rating is part of every snapshot, so a late adjustment has to
    /// reach the entry the player would return to with undo.
    private func refreshTimelineRating() {
        guard timeline.indices.contains(timelineIndex) else { return }
        timeline[timelineIndex].currentRating = currentRating
    }

    private func evaluateOutcomeAfterMove() {
        let standard = ChessEngine.outcome(for: position, history: positionHistory)
        if standard.isTerminal {
            outcome = standard
        } else if legalMoves.isEmpty {
            // A non-check Restfish position with every move resting is a
            // variant stalemate. Check positions are already waived above.
            outcome = .stalemate
        } else {
            outcome = .ongoing
        }
        guard outcome.isTerminal else { return }
        cancelTasks()
        let result: GameResult
        switch outcome {
        case .checkmate(let winner): result = winner == playerColor ? .win : .loss
        case .stalemate, .draw: result = .draw
        case .ongoing: return
        }
        recordCompletionIfNeeded(result: result)
        feedback.play(result == .win ? .win : (result == .loss ? .loss : .move), settings: settings)
        emit(.gameEnded(GameEndEvent(
            outcome: outcome,
            result: result,
            resigned: false,
            moveCount: moveHistory.count,
            duration: elapsedDuration,
            opponentRating: currentRating.rawValue
        )))
    }

    private func scheduleBot() {
        guard !isPaused, !outcome.isTerminal, !resigned,
              position.sideToMove == opponentColor else { return }
        botTask?.cancel()
        let token = lifecycle
        let context = engineContext
        let request = OpponentRequest(
            position: position,
            allowedMoves: engineAllowedMoves,
            history: positionHistory,
            rating: currentRating,
            thinkingTime: currentRating.thinkingTime
        )
        isBotThinking = true
        botTask = Task { [weak self] in
            // A short pause before the reply, so the opponent reads as taking a
            // turn rather than snapping back instantly.
            try? await Task.sleep(for: .milliseconds(360))
            guard !Task.isCancelled, let self else { return }
            let opponent = await self.resolveOpponent()
            guard !Task.isCancelled else { return }
            let move: Move?
            if self.rule.requiresEngineAnalysis,
               let service = opponent as? any ChessAnalysisService {
                let analysisRequest = AnalysisRequest(
                    position: request.position,
                    allowedMoves: request.allowedMoves,
                    targetDepth: max(12, self.settings.analysisDepth),
                    maximumTime: request.thinkingTime,
                    multiPV: nil
                )
                var latest: PositionAnalysis?
                let updates = await service.analysisUpdates(for: analysisRequest)
                for await snapshot in updates {
                    guard !Task.isCancelled else { return }
                    latest = snapshot
                }
                if let latest,
                   let selected = self.rule.selectEngineMove(
                       from: latest,
                       context: context,
                       parameters: self.parameters
                   ), request.allowedMoves.contains(selected) {
                    move = selected
                } else {
                    move = await opponent.bestMove(for: request)
                }
            } else {
                move = await opponent.bestMove(for: request)
            }
            guard !Task.isCancelled else { return }
            self.commitBotMove(
                move.map {
                    self.weakenedBelowCalibration(
                        $0,
                        allowedMoves: request.allowedMoves,
                        sample: context.randomSample
                    )
                },
                token: token
            )
        }
    }

    /// Applies the sub-1320 weakening described on `OpponentRating`.
    ///
    /// Derived from the same stable sample the gimmick rules use, so undoing to
    /// a position and replaying it produces the same opponent move rather than a
    /// different one each time.
    private func weakenedBelowCalibration(
        _ move: Move,
        allowedMoves: [Move],
        sample: UInt64
    ) -> Move {
        let randomness = currentRating.uncalibratedRandomness
        guard randomness > 0, allowedMoves.count > 1 else { return move }
        let roll = Double(sample % 1_000) / 1_000
        guard roll < randomness else { return move }
        return allowedMoves[Int((sample >> 12) % UInt64(allowedMoves.count))]
    }

    private func startOpponentGame() {
        let token = lifecycle
        Task { [weak self] in
            guard let self else { return }
            let resolved = await self.resolveOpponent()
            await resolved.newGame()
            guard self.lifecycle == token else { return }
            self.analysisService = resolved as? any ChessAnalysisService
            self.didResolveAnalysisService = true
            if self.isPlayerTurn {
                self.scheduleAnalysis()
            } else {
                self.scheduleBot()
            }
        }
    }

    private func scheduleAnalysis() {
        guard analysisTask == nil,
              shouldAnalyzePosition,
              !isPaused,
              !outcome.isTerminal,
              !resigned,
              position.sideToMove == playerColor else { return }
        guard let analysisService else {
            waitForAnalysisService()
            return
        }

        let token = lifecycle
        let root = position
        let request = AnalysisRequest(
            position: root,
            allowedMoves: legalMoves,
            targetDepth: settings.analysisDepth,
            maximumTime: settings.analysisTimeLimit.duration,
            // Visible move review must classify any move the player commits.
            // Hidden predictive thinking needs only the principal line.
            multiPV: (settings.evaluationEnabled || rule.requiresPlayerAnalysis) ? nil : 1
        )
        guard !request.allowedMoves.isEmpty else { return }

        latestAnalysis = nil
        isAnalyzing = true
        analysisTask = Task { [weak self] in
            let updates = await analysisService.analysisUpdates(for: request)
            for await snapshot in updates {
                guard !Task.isCancelled, let self else { return }
                guard self.lifecycle == token,
                      self.position == root,
                      self.position.sideToMove == self.playerColor,
                      !self.isPaused,
                      !self.outcome.isTerminal,
                      !self.resigned else { return }
                self.latestAnalysis = snapshot
                self.evaluationScore = snapshot.lines.first?.score
                self.emptyAnalysisRetryCount = 0
            }
            guard !Task.isCancelled, let self, self.lifecycle == token else { return }
            let shouldRetry = self.latestAnalysis == nil
                && self.shouldAnalyzePosition
                && self.position == root
                && self.emptyAnalysisRetryCount < 1
            self.analysisTask = nil
            self.isAnalyzing = false
            if shouldRetry {
                self.emptyAnalysisRetryCount += 1
                self.analysisRetryTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled, let self else { return }
                    self.analysisRetryTask = nil
                    self.scheduleAnalysis()
                }
            }
        }
    }

    private var shouldAnalyzePosition: Bool {
        settings.evaluationEnabled || settings.ponderEnabled || rule.requiresPlayerAnalysis
    }

    /// A player can open the drawer and enable evaluation while the 107 MB
    /// networks are still booting. Remember that intent instead of requiring a
    /// second toggle after the engine becomes available.
    private func waitForAnalysisService() {
        guard analysisReadinessTask == nil else { return }
        let token = lifecycle
        analysisReadinessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, self.lifecycle == token else { return }
                if self.analysisService != nil {
                    self.analysisReadinessTask = nil
                    self.scheduleAnalysis()
                    return
                }
                if self.didResolveAnalysisService {
                    self.analysisReadinessTask = nil
                    return
                }
            }
        }
    }

    private func cancelAnalysis(clearSnapshot: Bool) {
        // Cancelling the consumer terminates its AsyncStream. Stockfish's
        // termination handler carries the request ID, so an old cancellation
        // can never stop a newer analysis after a quick pause/resume.
        analysisTask?.cancel()
        analysisReadinessTask?.cancel()
        for task in deferredRatingTasks.values { task.cancel() }
        deferredRatingTasks.removeAll()
        analysisRetryTask?.cancel()
        analysisTask = nil
        analysisReadinessTask = nil
        analysisRetryTask = nil
        isAnalyzing = false
        if clearSnapshot { latestAnalysis = nil }
    }

    private func resolveOpponent() async -> any ChessOpponent {
        if let opponent { return opponent }
        let resolved = await makeOpponent()
        opponent = resolved
        opponentName = resolved.name
        return resolved
    }

    private func commitBotMove(_ move: Move?, token: UUID) {
        guard lifecycle == token, !isPaused, !outcome.isTerminal, !resigned,
              position.sideToMove == opponentColor else { return }
        isBotThinking = false
        let allowedMoves = engineAllowedMoves
        guard let move, allowedMoves.contains(move) else {
            // The bot never gets to manufacture a move; a cancelled/obsolete
            // search falls back to the same validated root list.
            if let fallback = allowedMoves.first {
                commit(fallback)
            } else {
                evaluateOutcomeAfterMove()
            }
            return
        }
        commit(move)
    }

    // MARK: - Reversible timeline

    private var undoTargetIndex: Int? {
        guard timelineIndex > 0 else { return nil }
        return stride(from: timelineIndex - 1, through: 0, by: -1)
            .first { timeline[$0].position.sideToMove == playerColor }
    }

    private func makeSnapshot() -> PlySnapshot {
        PlySnapshot(
            position: position,
            currentRating: currentRating,
            variantState: variantState,
            moveHistory: moveHistory,
            positionHistory: positionHistory,
            lastMove: lastMove,
            outcome: outcome,
            lastMoveClassification: lastMoveClassification,
            evaluationScore: evaluationScore,
            isBonusMove: isBonusMove,
            completedPlayerTurns: completedPlayerTurns,
            completedEngineTurns: completedEngineTurns
        )
    }

    private func resetTimeline() {
        timeline = [makeSnapshot()]
        timelineIndex = 0
    }

    private func appendTimelineSnapshot() {
        defer { publishSnapshot() }
        if timelineIndex < timeline.count - 1 {
            timeline.removeSubrange((timelineIndex + 1)..<timeline.count)
        }
        timeline.append(makeSnapshot())
        timelineIndex = timeline.count - 1
    }

    private func restoreSnapshot(at index: Int) {
        guard timeline.indices.contains(index) else { return }
        let snapshot = timeline[index]

        cancelTasks()
        lifecycle = UUID()
        timelineIndex = index
        position = snapshot.position
        currentRating = snapshot.currentRating
        variantState = snapshot.variantState
        moveHistory = snapshot.moveHistory
        positionHistory = snapshot.positionHistory
        lastMove = snapshot.lastMove
        outcome = snapshot.outcome
        lastMoveClassification = snapshot.lastMoveClassification
        evaluationScore = snapshot.evaluationScore
        isBonusMove = snapshot.isBonusMove
        completedPlayerTurns = snapshot.completedPlayerTurns
        completedEngineTurns = snapshot.completedEngineTurns
        latestAnalysis = nil
        selectedSquare = nil
        promotionChoices = []
        isBotThinking = false
        isPaused = false
        pausedAt = nil
        resigned = false

        guard !outcome.isTerminal else { return }
        if isPlayerTurn {
            scheduleAnalysis()
        } else {
            scheduleBot()
        }
    }

    private func emit(_ event: GameEvent) {
        eventLog.append(event)
        if eventLog.count > Self.eventLogLimit {
            eventLog.removeFirst(eventLog.count - Self.eventLogLimit)
        }
        onEvent?(event)
    }

    /// En passant removes a pawn that is not standing on the destination square,
    /// so the captured kind cannot simply be read from `move.to`.
    private func capturedKind(of move: Move, in previous: Position) -> PieceKind? {
        if move.flags.contains(.enPassant) { return .pawn }
        guard move.isCapture else { return nil }
        return previous.piece(at: move.to)?.kind
    }

    private func cancelTasks() {
        botTask?.cancel()
        botTask = nil
        cancelAnalysis(clearSnapshot: true)
        isBotThinking = false
    }

    private func recordCompletionIfNeeded(result: GameResult) {
        guard !didRecordCompletion else { return }
        didRecordCompletion = true
        let wonByCheckmate: Bool
        if case .checkmate(let winner) = outcome {
            wonByCheckmate = winner == playerColor
        } else {
            wonByCheckmate = false
        }
        let award = mode.crownAward(
            wonByCheckmate: wonByCheckmate,
            startingRating: startingRating,
            parameters: gameStartingParameters,
            integrity: integrity
        )
        let record = GameRecord(
            modeID: mode.rawValue,
            result: result,
            duration: elapsedDuration,
            moveCount: moveHistory.count,
            notation: ChessNotation.notation(
                for: moveHistory,
                startingPosition: gameStartingPosition,
                mode: mode,
                playerColor: playerColor,
                parameters: gameStartingParameters
            ),
            startingFEN: gameStartingPosition.fen,
            playerColorID: playerColor.rawValue,
            startingRating: startingRating.rawValue,
            endingRating: currentRating.rawValue,
            award: award,
            personalBestVariant: mode.personalBestVariant(parameters: gameStartingParameters),
            parameterValues: gameStartingParameters.storedValues
        )
        completionRecord = record
        recordCompletion?(record)
    }
}
