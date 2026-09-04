import SwiftUI

/// The game screen.
///
/// Its shape is deliberately conventional: two player strips with the board
/// between them, the moves under it, and a four-item bar at the bottom. That
/// arrangement is not an accident of any one app — it is what a chess screen
/// converges on once you accept that the board is the only thing on it worth
/// looking at, and that everything else has to earn its line.
///
/// What used to be here instead: a six-item header card above the board, and a
/// three-detent drawer below it that could cover the whole screen. Both were
/// removed. Controls now live behind one Options sheet, which is both simpler
/// to reach and impossible to leave half-open over the board.
struct GameView: View {
    private enum VoiceOverFocus: Hashable {
        case playerStrip
        case opponentStrip
        case pauseHeading
    }

    private let mode: GameMode
    private let onExit: () -> Void
    private let onRematch: () -> Void
    private let onChangeMode: () -> Void
    private let onPickMode: (GameMode) -> Void
    private let onDeclineOffer: () -> Void
    private let onSettingsChange: (AppSettings) -> Void
    @State private var settings: AppSettings
    @State private var session: GameSession
    @State private var showRestartConfirmation = false
    @State private var showExitConfirmation = false
    @State private var showSideConfirmation = false
    @State private var showResignConfirmation = false
    @State private var showOptions = false
    /// How far through the end-of-game sequence the screen has got.
    @State private var endgameStage: EndgameChoreography.Stage = .idle
    /// Set when the player asks to look at the final position again. The result
    /// card can then be brought back, so dismissing it is not a one-way door.
    @State private var isReviewingFinalBoard = false
    @AccessibilityFocusState private var voiceOverFocus: VoiceOverFocus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(GuideDirector.self) private var guide

    init(
        mode: GameMode,
        settings: AppSettings = .default,
        playerColor: PieceColor? = nil,
        /// Overrides the player's per-mode setting. The introduction game uses
        /// this so the boss starts at full strength.
        rating: OpponentRating? = nil,
        feedback: (any FeedbackService)? = nil,
        opponent: @escaping OpponentResolver = { LocalOpponent() },
        onRecord: ((GameRecord) -> Void)? = nil,
        onExit: @escaping () -> Void = {},
        onRematch: @escaping () -> Void = {},
        onChangeMode: @escaping () -> Void = {},
        onPickMode: @escaping (GameMode) -> Void = { _ in },
        onDeclineOffer: @escaping () -> Void = {},
        onSettingsChange: @escaping (AppSettings) -> Void = { _ in },
        onSnapshot: ((GameSnapshot?) -> Void)? = nil,
        restoring restored: GameSnapshot? = nil
    ) {
        self.mode = mode
        self.onExit = onExit
        self.onRematch = onRematch
        self.onChangeMode = onChangeMode
        self.onPickMode = onPickMode
        self.onDeclineOffer = onDeclineOffer
        self.onSettingsChange = onSettingsChange
        _settings = State(initialValue: settings)
        _session = State(initialValue: GameSession(
            mode: mode,
            rating: rating,
            playerColor: playerColor,
            settings: settings,
            feedback: feedback,
            opponent: opponent,
            onRecord: onRecord,
            onSnapshot: onSnapshot,
            restoring: restored
        ))
    }

    var body: some View {
        GeometryReader { proxy in
            if usesSidePanel(in: proxy.size) {
                sidePanelLayout
            } else {
                compactLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar { toolbar }
        .onAppear { guide.attach(to: session) }
        .onDisappear { guide.detach() }
        .onChange(of: session.eventLog.last) { _, event in
            handleAccessibilityEvent(event)
        }
        .oddfishScreenBackground()
        .overlay(alignment: .top) { guideBubble }
        .overlay { pauseOverlay }
        .overlay { resultOverlay }
        .overlay { guideMoment }
        .overlay { confirmationOverlay }
        .overlay(alignment: .bottom) { reviewReturnBar }
        // One task drives the whole end-of-game sequence. Keying it on the
        // outcome means a rematch cancels an in-flight sequence rather than
        // letting a stale curtain land on a fresh board.
        .task(id: terminalKey) { await runEndgameSequence() }
        .sheet(isPresented: $showOptions) { optionsSheet }
        .sheet(isPresented: promotionPresented) {
            PromotionPicker(color: session.playerColor) { session.choosePromotion($0) } onCancel: { session.cancelPromotion() }
                .presentationDetents([.height(255)])
        }
    }

    private func usesSidePanel(in size: CGSize) -> Bool {
        size.width >= 900 && size.width > size.height && size.height >= 600
    }

    // MARK: - Layouts

    private var sidePanelLayout: some View {
        HStack(spacing: OddfishTheme.Spacing.regular) {
            boardColumn(fullBleed: false)
                .frame(maxWidth: 720)
            GameControlPanel(
                mode: mode,
                session: session,
                settings: settings,
                onSettingsChange: updateSettings,
                onUndo: session.undo,
                onRedo: session.redo,
                onPause: togglePause,
                onRestart: { showRestartConfirmation = true },
                onResign: { showResignConfirmation = true },
                onSwitchSide: { showSideConfirmation = true }
            )
            .frame(width: 340)
        }
        .padding(.horizontal, OddfishTheme.Spacing.screenEdgeRegular)
        .padding(.vertical, OddfishTheme.Spacing.regular)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The board runs to both screen edges.
    ///
    /// It is the only element on the screen that benefits from every point it
    /// can get, and inset margins around it bought nothing: a phone board with
    /// 12pt gutters is six per cent smaller and reads as a picture of a board
    /// rather than as the thing you are playing on.
    ///
    /// The slack that is left over goes above the board rather than below it,
    /// because that is where Gil's bubble lands and where the eye is not.
    private var compactLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            boardColumn(fullBleed: true)
            Spacer(minLength: 0)
                .frame(maxHeight: OddfishTheme.Spacing.loose)
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The board and the two strips that frame it. Shared by both layouts, so
    /// an iPad's side panel does not get a different game screen.
    private func boardColumn(fullBleed: Bool) -> some View {
        let inset: CGFloat = fullBleed ? OddfishTheme.Spacing.snug : 0
        return VStack(spacing: 10) {
            opponentStrip
                .padding(.horizontal, inset)
            board(cornerRadius: fullBleed ? 0 : OddfishTheme.Radius.board)
            playerStrip
                .padding(.horizontal, inset)
            HStack(spacing: OddfishTheme.Spacing.tight) {
                MoveTapeView(
                    notation: session.moveNotation,
                    firstMoveColor: session.gameStartingPosition.sideToMove
                )
                // The tide shows which way the game is going; the figure says
                // by how much. They belong to each other, so the number appears
                // and disappears with the bar rather than living in chrome of
                // its own.
                if showsEvaluationTide {
                    EvaluationScoreLabel(
                        score: session.evaluationScore,
                        isAnalyzing: session.isAnalyzing
                    )
                }
            }
            .padding(.horizontal, inset)
            if let status = exceptionalStatus {
                statusRibbon(status)
                    .padding(.horizontal, inset)
            }
        }
        .frame(maxWidth: fullBleed ? .infinity : 620)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : OddfishTheme.Motion.standard, value: exceptionalStatus)
    }

    private func board(cornerRadius: CGFloat) -> some View {
        ChessBoardView(
            position: session.position,
            mode: mode,
            playerColor: session.playerColor,
            selectedSquare: session.selectedSquare,
            legalMoves: session.legalMoves,
            showsMoveHints: settings.showLegalMoves,
            lastMove: session.lastMove,
            restingState: session.variantState,
            rankedMoves: visibleRankedMoves,
            guideTargetSquare: guideTargetSquare,
            isInputEnabled: session.isInputEnabled,
            invalidMoveNonce: session.invalidMoveNonce,
            finale: endgameStage >= .boardFinale ? boardFinale : nil,
            cornerRadius: cornerRadius,
            onTap: { session.handleTap(on: $0) },
            onDragStart: { session.beginDrag(from: $0) },
            onMove: { session.attemptDragMove(from: $0, to: $1) }
        )
        // Inset on both sides, not just the one the tide needs, so the board
        // stays centred on the screen when the tide is switched on.
        .padding(.horizontal, showsEvaluationTide ? 18 : 0)
        .overlay(alignment: .leading) {
            if showsEvaluationTide {
                EvaluationTideView(
                    score: session.evaluationScore,
                    playerColor: session.playerColor,
                    isAnalyzing: session.isAnalyzing
                )
                .padding(.vertical, 6)
                .padding(.leading, 3)
            }
        }
        .animation(reduceMotion ? nil : OddfishTheme.Motion.entrance, value: endgameStage)
        // No layout priority. The board is the one element here that can give
        // up height gracefully — it is aspect-fitted, so a shorter proposal
        // just draws a smaller square. The strips around it are text, and text
        // that is offered less height than it needs does not shrink, it spills
        // out of the card painted behind it. Sizing the board first took its
        // full square and left the strips short, which is what put the
        // opponent's name over the navigation bar and "YOUR MOVE" outside its
        // pill at accessibility text sizes. Letting the strips measure first
        // and giving the board the remainder keeps every line inside its own
        // background, down to this floor.
        .frame(minHeight: 240)
    }

    // MARK: - Strips

    private var showsEvaluationTide: Bool {
        settings.evaluationEnabled && settings.showEvaluationBar
    }

    private var opponentStrip: some View {
        GamePlayerStrip(
            occupant: .opponent,
            name: session.opponentName,
            rating: session.currentRating.rawValue,
            color: session.opponentColor,
            material: CapturedMaterial.forSide(
                session.opponentColor,
                start: session.gameStartingPosition,
                current: session.position
            ),
            isOnMove: !session.isPlayerTurn && !session.outcome.isTerminal && !session.resigned,
            isThinking: session.isBotThinking
        )
        .accessibilityIdentifier("game-opponent-strip")
        .accessibilityLabel(opponentStripLabel)
        .accessibilityFocused($voiceOverFocus, equals: .opponentStrip)
    }

    private var playerStrip: some View {
        GamePlayerStrip(
            occupant: .player(mode),
            name: "You",
            rating: nil,
            color: session.playerColor,
            material: CapturedMaterial.forSide(
                session.playerColor,
                start: session.gameStartingPosition,
                current: session.position
            ),
            isOnMove: session.isPlayerTurn && !session.outcome.isTerminal && !session.resigned && !session.isPaused,
            isThinking: false
        )
        .accessibilityIdentifier("game-player-strip")
        .accessibilityLabel(playerStripLabel)
        .accessibilityFocused($voiceOverFocus, equals: .playerStrip)
    }

    /// The strips carry the turn status, so it is read where the player is
    /// already looking. The phrasing is kept verbatim because it is also the
    /// accessibility contract the UI tests assert on.
    private var playerStripLabel: String {
        var label = "You, playing \(session.playerColor.rawValue.capitalized)"
        if session.isPlayerTurn && !session.outcome.isTerminal && !session.resigned {
            label = "Your move · \(session.playerColor.rawValue.capitalized). " + label
        }
        if ChessEngine.isInCheck(session.playerColor, in: session.position) {
            label += ". Your king is in check"
        }
        return label
    }

    private var opponentStripLabel: String {
        var label = "\(session.opponentName), rated \(session.currentRating.rawValue), playing \(session.opponentColor.rawValue.capitalized)"
        if session.isBotThinking { label += ". Thinking" }
        return label
    }

    /// A single line, shown only when the game is in a state the strips cannot
    /// describe. Most of the time there is nothing here and the board simply
    /// sits closer to the bar.
    @ViewBuilder
    private func statusRibbon(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(OddfishTheme.gold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(OddfishTheme.gold.opacity(0.10), in: Capsule())
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityIdentifier("game-status-ribbon")
    }

    /// Deliberately silent about the end of the game. The board draws the
    /// result and the card names it; a third copy of the same sentence under
    /// the move tape was noise, and it made "You resigned" ambiguous to
    /// anything looking for it.
    private var exceptionalStatus: String? {
        if session.isPaused { return "Game paused" }
        if session.isBonusMove { return "Bonus move — you are still on move" }
        return nil
    }

    // MARK: - Bottom bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(OddfishTheme.line)
                .frame(height: 1)
            GameActionBar(
                canUndo: session.canUndo,
                canRedo: session.canRedo,
                isPaused: session.isPaused,
                isPlayable: !session.outcome.isTerminal && !session.resigned,
                onOptions: { showOptions = true },
                onUndo: session.undo,
                onRedo: session.redo,
                onPause: togglePause
            )
        }
        .background(OddfishTheme.surface.ignoresSafeArea(edges: .bottom))
        .accessibilityIdentifier("game-control-drawer")
    }

    private var optionsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    GameControlDetails(
                        mode: mode,
                        session: session,
                        settings: settings,
                        onSettingsChange: updateSettings,
                        onUndo: session.undo,
                        onRedo: session.redo,
                        onPause: togglePause,
                        onRestart: { showOptions = false; showRestartConfirmation = true },
                        onResign: { showOptions = false; showResignConfirmation = true },
                        onSwitchSide: { showOptions = false; showSideConfirmation = true }
                    )
                    .padding(OddfishTheme.Spacing.regular)
                }
                .scrollIndicators(.hidden)
                // Restart and Resign stay pinned below the fold line, so
                // resigning is Options → Resign with no scrolling in between.
                Divider().overlay(OddfishTheme.line)
                GameDestructiveFooter(
                    isResignDisabled: session.outcome.isTerminal || session.resigned,
                    onRestart: { showOptions = false; showRestartConfirmation = true },
                    onResign: { showOptions = false; showResignConfirmation = true }
                )
                .padding(.horizontal, OddfishTheme.Spacing.regular)
                .padding(.vertical, OddfishTheme.Spacing.snug)
            }
            .background(OddfishTheme.canvas)
            .navigationTitle("Game options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showOptions = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(OddfishTheme.canvas)
        .accessibilityIdentifier("game-options-sheet")
    }

    // MARK: - Actions

    private func togglePause() {
        session.isPaused ? session.resume() : session.pause()
    }

    private func restart() {
        session.restart()
        resetEndgame()
        onRematch()
    }

    private func updateSettings(_ updated: AppSettings) {
        settings = updated
        session.applySettings(updated)
        onSettingsChange(updated)
    }

    /// Announces only state that is otherwise visual and transient. The move
    /// event supplies the facts; polling labels after a render can describe a
    /// later position when the engine replies quickly.
    private func handleAccessibilityEvent(_ event: GameEvent?) {
        guard let event else { return }
        switch event {
        case .moveCommitted(let move):
            if let announcement = GameAccessibilityCopy.move(
                move,
                opponentName: session.opponentName,
                isBonusMove: session.isBonusMove
            ) {
                OddfishAccessibility.announce(announcement)
            }

        case .gamePaused:
            moveVoiceOverFocus(to: .pauseHeading)

        case .gameResumed:
            moveVoiceOverFocus(to: session.isPlayerTurn ? .playerStrip : .opponentStrip)

        case .gameStarted, .selectionRejected, .promotionOffered, .gameEnded:
            break
        }
    }

    private func moveVoiceOverFocus(to destination: VoiceOverFocus) {
        guard OddfishAccessibility.isVoiceOverRunning else { return }
        Task { @MainActor in
            // The destination may be entering as an overlay in this update.
            await Task.yield()
            voiceOverFocus = destination
        }
    }

    private var visibleRankedMoves: [AnalysisLine] {
        guard settings.evaluationEnabled, settings.showMoveRanks,
              session.isPlayerTurn else { return [] }
        return session.latestAnalysis?.topFive ?? []
    }

    private var guideTargetSquare: Square? {
        guard settings.evaluationEnabled,
              settings.showMoveAnalysis,
              let classification = session.lastMoveClassification,
              !classification.isBest else { return nil }
        return classification.bestMove.to
    }

    private var promotionPresented: Binding<Bool> {
        Binding(
            get: { !session.promotionChoices.isEmpty },
            set: { if !$0 { session.cancelPromotion() } }
        )
    }

    // MARK: - End of game

    /// Changes exactly once per finished game, and again on restart. Used as the
    /// task id so the sequence restarts cleanly rather than accumulating.
    private var terminalKey: String {
        guard session.outcome.isTerminal || session.resigned else { return "ongoing" }
        return "\(session.moveHistory.count)-\(session.resigned)-\(outcomeTitle)"
    }

    private func runEndgameSequence() async {
        guard session.outcome.isTerminal || session.resigned else {
            endgameStage = .idle
            isReviewingFinalBoard = false
            return
        }
        await EndgameChoreography.play { stage in
            withAnimation(
                reduceMotion
                    ? OddfishTheme.Motion.chrome
                    : (stage == .curtain ? OddfishTheme.Motion.celebrate : OddfishTheme.Motion.entrance)
            ) {
                endgameStage = stage
            }
        }
    }

    private func resetEndgame() {
        endgameStage = .idle
        isReviewingFinalBoard = false
    }

    /// What the board itself draws once the mating piece has landed.
    private var boardFinale: BoardFinale? {
        if session.resigned {
            return BoardFinale(kind: .resigned, square: kingSquare(of: session.playerColor), isPlayerWin: false)
        }
        switch session.outcome {
        case .ongoing:
            return nil
        case .checkmate(let winner):
            return BoardFinale(
                kind: .checkmate,
                square: kingSquare(of: winner.opponent),
                isPlayerWin: winner == session.playerColor
            )
        case .stalemate:
            return BoardFinale(kind: .stalemate, square: kingSquare(of: session.position.sideToMove), isPlayerWin: false)
        case .draw:
            return BoardFinale(kind: .draw, square: kingSquare(of: session.playerColor), isPlayerWin: false)
        }
    }

    private func kingSquare(of color: PieceColor) -> Square? {
        session.position.kingSquare(of: color)
    }

    // MARK: - Chrome

    /// Floats over the top of the board rather than joining the stack. The board
    /// is sized from whatever the fixed chrome leaves it, so a bubble in the
    /// layout would shrink the board every time Gil spoke.
    @ViewBuilder
    private var guideBubble: some View {
        if let utterance = guide.utterance {
            GuideBubbleView(
                utterance: utterance,
                expression: guide.expression,
                barLevels: guide.barLevels,
                onDismiss: { guide.dismiss() }
            )
            .padding(.horizontal, OddfishTheme.Spacing.snug)
            // Sits in the clear band above the opponent strip. That band is
            // where the layout's spare height goes, and this is what it is for.
            // On a short phone there is no band and the bubble overlaps the
            // strip instead, which is the correct trade: what he is saying
            // matters more for the few seconds it is up than the rating does.
            .padding(.top, OddfishTheme.Spacing.regular)
            .allowsHitTesting(true)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity),
                        removal: .opacity
                      )
            )
            .animation(reduceMotion ? nil : OddfishTheme.Motion.entrance, value: utterance)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            GuidePerchButton(
                expression: guide.expression,
                barLevels: guide.barLevels,
                action: { guide.dismiss() }
            )
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Exit", systemImage: "xmark") {
                if session.outcome.isTerminal || session.resigned {
                    session.exit()
                    onExit()
                } else {
                    showExitConfirmation = true
                }
            }
            .accessibilityHint("Returns to the mode list")
        }
    }

    @ViewBuilder
    private var pauseOverlay: some View {
        if session.isPaused {
            OddfishModalScrim {
                VStack(spacing: 15) {
                    // He naps while you are paused.
                    GilView(size: 62, expression: .napping)
                    Text("Take a breath")
                        .font(.oddfishTitle)
                        .foregroundStyle(OddfishTheme.ivory)
                        .accessibilityLabel("Game paused. Take a breath")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($voiceOverFocus, equals: .pauseHeading)
                    Button("Resume game") { session.resume() }
                        .buttonStyle(OddfishPrimaryButtonStyle())
                }
            }
            .accessibilityIdentifier("game-pause-overlay")
        }
    }

    @ViewBuilder
    private var guideMoment: some View {
        if let moment = guide.moment {
            GuideMomentView(
                moment: moment,
                onChoose: { mode in
                    guide.dismissMoment()
                    session.exit()
                    onPickMode(mode)
                },
                onDecline: {
                    let action = moment.declineAction
                    guide.dismissMoment()
                    guard action == .restart else { return }
                    onDeclineOffer()
                    session.restart()
                    resetEndgame()
                }
            )
        }
    }

    /// Centered confirmations for the four expensive actions. These used to be
    /// system confirmation dialogs, but presented right after the options sheet
    /// dismissed they rendered as a top-anchored popover with a tail instead of
    /// a bottom sheet — oddly placed and easy to miss. A centered card matches
    /// the pause and result modals, keeps both buttons the same full-width
    /// size, and keeps the UITest button labels ("Restart game", "Leave game",
    /// "Resign game") verbatim.
    @ViewBuilder
    private var confirmationOverlay: some View {
        if showRestartConfirmation {
            GameConfirmDialog(
                title: "Restart this game?",
                message: "Your current board will be replaced with a new game.",
                confirmTitle: "Restart game",
                confirmIcon: "arrow.clockwise",
                onConfirm: {
                    showRestartConfirmation = false
                    restart()
                },
                onCancel: { showRestartConfirmation = false }
            )
            .accessibilityIdentifier("game-confirm-restart")
        } else if showExitConfirmation {
            GameConfirmDialog(
                title: "Leave this game?",
                message: "Your active game will not be saved.",
                confirmTitle: "Leave game",
                confirmIcon: "rectangle.portrait.and.arrow.right",
                onConfirm: {
                    showExitConfirmation = false
                    session.exit()
                    onExit()
                },
                onCancel: { showExitConfirmation = false }
            )
            .accessibilityIdentifier("game-confirm-exit")
        } else if showSideConfirmation {
            GameConfirmDialog(
                title: "Switch sides and restart?",
                message: "Changing sides starts a fresh game. \(session.opponentName) will move first when you play Black.",
                confirmTitle: "Restart as \(session.opponentColor.rawValue.capitalized)",
                confirmIcon: "arrow.triangle.2.circlepath",
                onConfirm: {
                    showSideConfirmation = false
                    let color = session.opponentColor
                    session.restart(as: color)
                    resetEndgame()
                    // Session-only: switching sides restarts this game but must
                    // not rewrite the global default. Persisting it here is what
                    // leaked "Play as Black" into the next mode's game.
                },
                onCancel: { showSideConfirmation = false }
            )
            .accessibilityIdentifier("game-confirm-side")
        } else if showResignConfirmation {
            // Resign keeps a confirmation while it is the most expensive tap
            // on the screen: it ends the game, records a loss, and ends the
            // crown run in one go.
            GameConfirmDialog(
                title: "Resign this game?",
                message: "Your current game will count as a loss.",
                confirmTitle: "Resign game",
                confirmIcon: "flag.fill",
                onConfirm: {
                    showResignConfirmation = false
                    session.resign()
                },
                onCancel: { showResignConfirmation = false }
            )
            .accessibilityIdentifier("game-confirm-resign")
        }
    }

    /// The result card, once the board has had its moment.
    ///
    /// Gil owns the screen while a moment is up; two result cards at once would
    /// be two voices talking over each other.
    @ViewBuilder
    private var resultOverlay: some View {
        if guide.moment == nil,
           endgameStage == .curtain,
           !isReviewingFinalBoard,
           session.outcome.isTerminal || session.resigned {
            GameResultOverlay(
                title: outcomeTitle,
                subtitle: outcomeSubtitle,
                symbol: resultSymbol,
                tint: resultTint,
                isWin: isPlayerCheckmateWin,
                award: session.completionRecord?.award,
                ineligibleNote: session.completionRecord?.award == nil && isPlayerCheckmateWin
                    ? "No crowns · \(mode.crownRule.startingRequirementText)"
                    : nil,
                onRematch: restart,
                onChangeMode: {
                    session.exit()
                    onChangeMode()
                },
                onReview: {
                    withAnimation(OddfishTheme.Motion.standard) { isReviewingFinalBoard = true }
                }
            )
            .transition(.opacity)
        }
    }

    /// Shown while the player is looking at the finished board, so the result
    /// card is one tap away rather than gone for good.
    @ViewBuilder
    private var reviewReturnBar: some View {
        if isReviewingFinalBoard {
            Button("Show result", systemImage: "chevron.up") {
                withAnimation(OddfishTheme.Motion.entrance) { isReviewingFinalBoard = false }
            }
            .buttonStyle(OddfishPrimaryButtonStyle(fillsWidth: false))
            .padding(.bottom, 78)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityIdentifier("game-show-result")
        }
    }

    private var outcomeTitle: String {
        if session.resigned { return "You resigned" }
        switch session.outcome {
        case .checkmate(let winner): return winner == session.playerColor ? "Checkmate. You win." : "Checkmate. You lose."
        case .stalemate: return "Stalemate"
        case .draw: return "Draw"
        case .ongoing: return "Game in progress"
        }
    }

    private var isPlayerCheckmateWin: Bool {
        if case .checkmate(let winner) = session.outcome {
            return winner == session.playerColor
        }
        return false
    }

    private var outcomeSubtitle: String {
        if session.resigned { return "A fresh board is waiting whenever you are." }
        switch session.outcome {
        case .checkmate(let winner): return winner == session.playerColor ? "That was a clean finish." : "The tide turns. Try another line."
        case .stalemate: return "Neither side has a legal move."
        case .draw: return "The board has reached a draw."
        case .ongoing: return ""
        }
    }

    private var resultSymbol: String {
        if session.resigned { return "flag.fill" }
        if case .checkmate(let winner) = session.outcome { return winner == session.playerColor ? "crown.fill" : "wave.3.right" }
        return "equal.circle.fill"
    }

    private var resultTint: Color {
        if session.resigned { return OddfishTheme.coral }
        if case .checkmate(let winner) = session.outcome { return winner == session.playerColor ? OddfishTheme.gold : OddfishTheme.coral }
        return OddfishTheme.ivory
    }
}

/// One scrim, one card, one set of paddings for every modal the game screen
/// puts over the board. Three near-identical copies of this had drifted apart
/// by a few points each.
private struct OddfishModalScrim<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            content
                .padding(26)
                .frame(maxWidth: 340)
                .background {
                    RoundedRectangle(cornerRadius: OddfishTheme.Radius.panel, style: .continuous)
                        .fill(OddfishTheme.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: OddfishTheme.Radius.panel, style: .continuous)
                                .strokeBorder(OddfishTheme.lineStrong, lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.5), radius: 26, y: 14)
                }
                .padding(.horizontal, OddfishTheme.Spacing.loose)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.93)
                .opacity(revealed ? 1 : 0)
                .animation(reduceMotion ? .easeOut(duration: 0.18) : OddfishTheme.Motion.entrance, value: revealed)
        }
        .onAppear { revealed = true }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// One centered confirmation card for the four expensive game actions.
///
/// Both buttons are full-width and share one min-height, so confirm and cancel
/// are always the same size. Labels match the old system dialogs verbatim so
/// existing UI tests keep passing.
private struct GameConfirmDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirmIcon: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        OddfishModalScrim {
            VStack(spacing: 0) {
                Text(title)
                    .font(.oddfishTitle)
                    .foregroundStyle(OddfishTheme.ivory)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.oddfishBody)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                VStack(spacing: 10) {
                    Button(confirmTitle, systemImage: confirmIcon, action: onConfirm)
                        .buttonStyle(GameDestructiveButtonStyle())
                    Button("Cancel", action: onCancel)
                        .buttonStyle(OddfishSecondaryButtonStyle())
                }
            }
        }
        .accessibilityIdentifier("game-confirm-dialog")
    }
}

private struct GameControlPanel: View {
    let mode: GameMode
    let session: GameSession
    let settings: AppSettings
    let onSettingsChange: (AppSettings) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onPause: () -> Void
    let onRestart: () -> Void
    let onResign: () -> Void
    let onSwitchSide: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: OddfishTheme.Spacing.snug) {
                OddfishEyebrow(text: "GAME CONTROLS")
                GameStatusStrip(session: session, tint: mode.tint)
            }
            .padding(OddfishTheme.Spacing.regular)

            // The wide layout has no bottom bar, so the three live controls sit
            // at the top of the panel instead. Same glyphs, same identifiers —
            // only one of the two ever exists at a time.
            HStack(spacing: 0) {
                OddfishActionBarButton(
                    title: session.isPaused ? "Resume" : "Pause",
                    systemImage: session.isPaused ? "play.fill" : "pause.fill",
                    isEnabled: !session.outcome.isTerminal && !session.resigned,
                    action: onPause
                )
                .accessibilityIdentifier("game-pause")
                OddfishActionBarButton(
                    title: "Undo",
                    systemImage: "arrow.uturn.backward",
                    isEnabled: session.canUndo,
                    action: onUndo
                )
                .accessibilityIdentifier("game-undo")
                OddfishActionBarButton(
                    title: "Redo",
                    systemImage: "arrow.uturn.forward",
                    isEnabled: session.canRedo,
                    action: onRedo
                )
                .accessibilityIdentifier("game-redo")
            }
            .padding(.bottom, OddfishTheme.Spacing.tight)

            Divider().overlay(OddfishTheme.line)

            ScrollView {
                GameControlDetails(
                    mode: mode,
                    session: session,
                    settings: settings,
                    onSettingsChange: onSettingsChange,
                    onUndo: onUndo,
                    onRedo: onRedo,
                    onPause: onPause,
                    onRestart: onRestart,
                    onResign: onResign,
                    onSwitchSide: onSwitchSide
                )
                .padding(OddfishTheme.Spacing.regular)
            }
            .scrollIndicators(.hidden)

            Divider().overlay(OddfishTheme.line)
            GameDestructiveFooter(
                isResignDisabled: session.outcome.isTerminal || session.resigned,
                onRestart: onRestart,
                onResign: onResign
            )
            .padding(OddfishTheme.Spacing.regular)
        }
        .frame(maxHeight: .infinity)
        .oddfishSurface(cornerRadius: OddfishTheme.Radius.panel)
        .accessibilityIdentifier("game-control-side-panel")
    }
}

private struct GameStatusStrip: View {
    let session: GameSession
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            metric(title: "TURN", value: turnValue, tint: session.isPlayerTurn ? OddfishTheme.seaGlass : OddfishTheme.mutedInk)
            Divider().frame(height: 27).overlay(OddfishTheme.line)
            metric(title: "MATERIAL", value: materialValue, tint: materialTint)
            Divider().frame(height: 27).overlay(OddfishTheme.line)
            metric(title: "RATING", value: ratingValue, tint: tint, identifier: "game-drawer-rating")
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func metric(title: String, value: String, tint: Color, identifier: String? = nil) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(OddfishTheme.mutedInk)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityIdentifier(identifier ?? "")
        }
        .frame(maxWidth: .infinity)
    }

    private var turnValue: String {
        if session.outcome.isTerminal || session.resigned { return "DONE" }
        if session.isPaused { return "PAUSED" }
        return session.isPlayerTurn ? "YOU · \(sideInitial)" : "THEM · \(opponentInitial)"
    }

    private var sideInitial: String { session.playerColor == .white ? "W" : "B" }
    private var opponentInitial: String { session.opponentColor == .white ? "W" : "B" }

    private var materialValue: String {
        if session.materialBalance == 0 { return "EVEN" }
        return session.materialBalance > 0 ? "+\(session.materialBalance)" : "\(session.materialBalance)"
    }

    private var materialTint: Color {
        session.materialBalance > 0 ? OddfishTheme.seaGlass : (session.materialBalance < 0 ? OddfishTheme.coral : OddfishTheme.ivory)
    }

    private var ratingValue: String {
        let delta = session.ratingDelta
        let signed = delta >= 0 ? "+\(delta)" : "\(delta)"
        return "\(session.currentRating.rawValue) \(signed)"
    }
}

/// Restart and Resign, pinned outside the scrollable settings so resigning
/// never requires scrolling. Shared by the options sheet and the wide-layout
/// side panel, so both surfaces stay identical. Both buttons are full-half
/// width with one shared min-height, so they are always the same size.
private struct GameDestructiveFooter: View {
    let isResignDisabled: Bool
    let onRestart: () -> Void
    let onResign: () -> Void

    var body: some View {
        HStack(spacing: OddfishTheme.Spacing.tight) {
            Button("Restart", systemImage: "arrow.clockwise", action: onRestart)
                .buttonStyle(OddfishSecondaryButtonStyle())
                .accessibilityIdentifier("game-restart")
            Button("Resign", systemImage: "flag.fill", action: onResign)
                .buttonStyle(GameDestructiveButtonStyle())
                .disabled(isResignDisabled)
                .accessibilityIdentifier("game-resign")
        }
    }
}

private struct GameControlDetails: View {
    let mode: GameMode
    let session: GameSession
    let settings: AppSettings
    let onSettingsChange: (AppSettings) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onPause: () -> Void
    let onRestart: () -> Void
    let onResign: () -> Void
    let onSwitchSide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.regular) {
            modeSummary
            crownRun
            Divider().overlay(OddfishTheme.line)
            if !mode.gimmickRule.parameterDefinitions.isEmpty {
                modeControls
                Divider().overlay(OddfishTheme.line)
            }
            analysisControls
            Divider().overlay(OddfishTheme.line)
            sideControl
        }
    }

    private var modeSummary: some View {
        HStack(alignment: .top, spacing: OddfishTheme.Spacing.snug) {
            OddfishModeGlyph(mode: mode, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title)
                    .font(.oddfishHeadline)
                    .foregroundStyle(OddfishTheme.ivory)
                Text(mode.inGameCue)
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Started at \(session.startingRating.rawValue) · vs \(session.opponentName)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(mode.tint)
                if let progress = session.bonusMoveProgress {
                    Text(session.isBonusMove
                         ? "Bonus move ready"
                         : "Bonus move \(progress.completed)/\(progress.target)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(session.isBonusMove ? OddfishTheme.seaGlass : OddfishTheme.mutedInk)
                        .accessibilityIdentifier("game-bonus-progress")
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var crownRun: some View {
        HStack(alignment: .top, spacing: OddfishTheme.Spacing.snug) {
            CrownIcons(tier: session.integrity.maximumCrownTier, size: 12)
                .frame(width: 50, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.isCrownStartingRatingEligible
                     ? "CROWN RUN · UP TO \(session.integrity.maximumCrownTier)"
                     : "CROWNS OFF FOR THIS RUN")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.65)
                    .foregroundStyle(session.isCrownStartingRatingEligible ? OddfishTheme.Guide.body : OddfishTheme.mutedInk)
                Text(session.isCrownStartingRatingEligible
                     ? "Checkmate · \(session.crownScoreForCurrentRun.formatted)"
                     : mode.crownRule.startingRequirementText)
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("game-crown-status")
    }

    private var modeControls: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.tight) {
            OddfishEyebrow(text: "RULE CONTROLS")
            ForEach(mode.gimmickRule.parameterDefinitions) { definition in
                if definition.range == 0...1, definition.step == 1 {
                    Toggle(definition.title, isOn: Binding(
                        get: { parameterValue(definition) >= 0.5 },
                        set: { updateParameter($0 ? 1 : 0, definition: definition) }
                    ))
                    .font(.oddfishControl)
                } else {
                    Stepper(
                        value: Binding(
                            get: { parameterValue(definition) },
                            set: { updateParameter($0, definition: definition) }
                        ),
                        in: definition.range,
                        step: definition.step
                    ) {
                        LabeledContent(definition.title, value: parameterLabel(definition))
                            .font(.oddfishControl)
                            .foregroundStyle(OddfishTheme.ivory)
                    }
                }
            }
            Text("Changes apply immediately and are saved for the next game.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(OddfishTheme.mutedInk)
        }
    }

    private func parameterValue(_ definition: GimmickParameterDefinition) -> Double {
        settings.parameters(for: mode, default: mode.gimmickRule.defaultParameters).value(for: definition)
    }

    private func updateParameter(_ value: Double, definition: GimmickParameterDefinition) {
        var updated = settings
        updated.setParameter(value, definition: definition, for: mode)
        onSettingsChange(updated)
    }

    private func parameterLabel(_ definition: GimmickParameterDefinition) -> String {
        let value = Int(parameterValue(definition).rounded())
        if definition.id == GimmickParameterKey.chance { return "\(value)%" }
        if definition.id == GimmickParameterKey.tolerance { return "\(value) cp" }
        if definition.id == GimmickParameterKey.cycle { return "\(value) turns" }
        return "\(value) Elo"
    }

    private var analysisControls: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.snug) {
            HStack(spacing: OddfishTheme.Spacing.tight) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("EVALUATION")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(OddfishTheme.mutedInk)
                    Text(settings.evaluationEnabled ? analysisStatus : "Hidden · clean-game eligible")
                        .font(.oddfishCaption)
                        .foregroundStyle(settings.evaluationEnabled ? OddfishTheme.seaGlass : OddfishTheme.mutedInk)
                }
                Spacer(minLength: 8)
                Toggle("Evaluation", isOn: settingBinding(\.evaluationEnabled))
                    .labelsHidden()
                    .accessibilityLabel("Evaluation")
                    .accessibilityIdentifier("game-evaluation-toggle")
            }

            if settings.evaluationEnabled {
                Stepper(
                    value: settingBinding(\.analysisDepth),
                    in: 10...28,
                    step: 2
                ) {
                    LabeledContent("Depth", value: "\(settings.analysisDepth)")
                        .font(.oddfishControl)
                        .foregroundStyle(OddfishTheme.ivory)
                }
                .accessibilityIdentifier("game-analysis-depth")

                Picker("Max time", selection: settingBinding(\.analysisTimeLimit)) {
                    ForEach(AnalysisTimeLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .font(.oddfishControl)
                .accessibilityIdentifier("game-analysis-time")

                VStack(spacing: 0) {
                    analysisToggle(
                        "Evaluation tide",
                        systemImage: "water.waves",
                        keyPath: \.showEvaluationBar,
                        identifier: "game-evaluation-bar-toggle"
                    )
                    Divider().overlay(OddfishTheme.line)
                    analysisToggle(
                        "Move ranks · top 5",
                        systemImage: "number.circle",
                        keyPath: \.showMoveRanks,
                        identifier: "game-move-ranks-toggle"
                    )
                    Divider().overlay(OddfishTheme.line)
                    analysisToggle(
                        "Last-move review",
                        systemImage: "scope",
                        keyPath: \.showMoveAnalysis,
                        identifier: "game-move-review-toggle"
                    )
                }
                .padding(.horizontal, 10)
                .background(OddfishTheme.surfaceHigh, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if settings.showMoveAnalysis,
                   let classification = session.lastMoveClassification {
                    MoveReviewCard(classification: classification)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: settingBinding(\.ponderEnabled)) {
                    Label("Predictive thinking", systemImage: "bolt.horizontal.circle")
                        .font(.oddfishControl)
                }
                .accessibilityIdentifier("game-ponder-toggle")
                Text("Keeps Stockfish thinking one line ahead while you play, even when evaluation is hidden. Uses more CPU and battery.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var analysisStatus: String {
        if session.isAnalyzing { return "Reading the tide… · depth \(settings.analysisDepth)" }
        if let depth = session.latestAnalysis?.depth {
            return "Depth \(depth) · \(settings.analysisTimeLimit.shortTitle) max"
        }
        return "Depth \(settings.analysisDepth) · waiting"
    }

    private func analysisToggle(
        _ title: String,
        systemImage: String,
        keyPath: WritableKeyPath<AppSettings, Bool>,
        identifier: String
    ) -> some View {
        Toggle(isOn: settingBinding(keyPath)) {
            Label(title, systemImage: systemImage)
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.ivory)
        }
        .frame(minHeight: 42)
        .accessibilityIdentifier(identifier)
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                var updated = settings
                updated[keyPath: keyPath] = value
                onSettingsChange(updated)
            }
        )
    }

    private var sideControl: some View {
        HStack(spacing: OddfishTheme.Spacing.snug) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PLAYING AS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(OddfishTheme.mutedInk)
                Text(session.playerColor.rawValue.capitalized)
                    .font(.oddfishHeadline)
                    .foregroundStyle(OddfishTheme.ivory)
            }
            Spacer(minLength: 8)
            Button(action: onSwitchSide) {
                Label("Play as \(session.opponentColor.rawValue.capitalized)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.oddfishControl)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
                .buttonStyle(OddfishSecondaryButtonStyle(fillsWidth: false))
                .accessibilityIdentifier("game-switch-side")
        }
    }
}

private struct PromotionPicker: View {
    let color: PieceColor
    let onPick: (PieceKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Choose your piece")
                .font(.oddfishTitle)
                .foregroundStyle(OddfishTheme.ivory)
            HStack(spacing: OddfishTheme.Spacing.snug) {
                ForEach([PieceKind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                    Button { onPick(kind) } label: {
                        ChessPieceView(piece: Piece(color: color, kind: kind), square: 60)
                            .frame(width: 62, height: 62)
                            .background(
                                OddfishTheme.surfaceHigh,
                                in: RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous)
                                    .strokeBorder(OddfishTheme.line, lineWidth: 1)
                            }
                    }
                    .buttonStyle(OddfishPressableStyle())
                    .accessibilityLabel(kind.rawValue.capitalized)
                }
            }
            Button("Cancel", action: onCancel)
                .font(.oddfishControl)
                .foregroundStyle(OddfishTheme.mutedInk)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OddfishTheme.canvas)
    }
}

/// Resign is the one destructive control in the app, so it is the one place a
/// coral fill is allowed to sit under a label.
private struct GameDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.oddfishControl)
            .foregroundStyle(OddfishTheme.coral)
            .frame(maxWidth: .infinity, minHeight: 50)
            // Mirrors OddfishSecondaryButtonStyle's box model exactly (frame
            // then padding): without this the destructive button measured
            // 50pt tall next to the secondary's 64pt.
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous)
                    .fill(OddfishTheme.coral.opacity(configuration.isPressed ? 0.24 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous)
                    .strokeBorder(OddfishTheme.coral.opacity(0.35), lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(OddfishTheme.Motion.instant, value: configuration.isPressed)
    }
}
