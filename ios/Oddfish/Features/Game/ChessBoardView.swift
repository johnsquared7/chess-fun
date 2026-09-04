import SwiftUI

/// All of the board's proportions, derived from one square size.
///
/// Indicators used to be sized with unrelated constants — a `0.20` dot next to a
/// `max(3, 0.09)` ring next to a flat colour wash — so their visual weights had
/// no relationship to each other. Everything the board draws now comes from here.
private struct BoardMetrics {
    let side: CGFloat
    let perspective: BoardPerspective

    var cell: CGFloat { side / 8 }

    /// Quiet-move dot diameter.
    var quietDot: CGFloat { cell * 0.28 }
    /// Ring drawn around a capturable piece.
    var captureRingWidth: CGFloat { cell * 0.075 }
    var captureRingInset: CGFloat { cell * 0.03 }
    /// Ring around the square the player is dragging over.
    var targetRingWidth: CGFloat { cell * 0.075 }
    var coordinateFont: CGFloat { max(7, cell * 0.17) }
    var coordinateInset: CGFloat { cell * 0.05 }
    var restBadge: CGFloat { cell * 0.30 }

    func origin(of square: Square) -> CGPoint {
        let visual = perspective.visualCoordinates(for: square)
        return CGPoint(x: CGFloat(visual.file) * cell, y: CGFloat(visual.rank) * cell)
    }

    func center(of square: Square) -> CGPoint {
        let origin = origin(of: square)
        return CGPoint(x: origin.x + cell / 2, y: origin.y + cell / 2)
    }

    /// A1 is a dark square. The board previously had this parity inverted, which
    /// put the whole colouring one square out of step with a real board.
    func isLight(_ square: Square) -> Bool {
        !(square.file + square.rank).isMultiple(of: 2)
    }
}

/// The board's own end-of-game flourish.
///
/// It exists as an input rather than as something the board derives, because
/// the board must not draw it the instant the position becomes terminal: the
/// mating piece is still travelling then. The game screen holds this back until
/// the piece has landed — see `EndgameChoreography`.
struct BoardFinale: Equatable {
    enum Kind: Equatable {
        case checkmate
        case stalemate
        case draw
        case resigned
    }

    let kind: Kind
    /// The mated king, when there is one to point at.
    let square: Square?
    let isPlayerWin: Bool
}

struct ChessBoardView: View {
    let position: Position
    let mode: GameMode
    let playerColor: PieceColor
    let selectedSquare: Square?
    /// Every legal move in the position. Interaction is driven by this, so
    /// lifting a piece works whether or not move hints are switched on.
    let legalMoves: [Move]
    /// Whether the legal-destination markers are drawn. A display preference
    /// only — it must never decide what the player is allowed to do.
    let showsMoveHints: Bool
    let lastMove: Move?
    let restingState: VariantState
    /// Current top engine lines, rendered as ranked destination badges.
    let rankedMoves: [AnalysisLine]
    /// The better destination from Gil's retained last-move review.
    let guideTargetSquare: Square?
    let isInputEnabled: Bool
    let invalidMoveNonce: Int
    /// Non-nil once the game screen has decided the board may celebrate.
    let finale: BoardFinale?
    /// Squared off when the board runs to the screen edges, rounded when it
    /// sits inside a panel.
    var cornerRadius: CGFloat = OddfishTheme.Radius.board
    let onTap: (Square) -> Void
    let onDragStart: (Square) -> Void
    let onMove: (Square, Square) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.boardTheme) private var theme
    @Environment(\.boardDecoration) private var decoration
    @State private var drag: DragState?
    @State private var shakeNonce = 0
    @State private var board: TrackedBoard
    /// Rises to 1 each time the side to move changes into check, then decays.
    /// A pulse rather than a constant glow: a permanent wash under the king is
    /// wallpaper by the third move, and stops being read at all.
    @State private var checkPulse: CGFloat = 0
    /// The square a piece was taken on, held just long enough to flash.
    @State private var captureFlash: Square?

    init(
        position: Position,
        mode: GameMode,
        playerColor: PieceColor = .white,
        selectedSquare: Square?,
        legalMoves: [Move],
        showsMoveHints: Bool,
        lastMove: Move?,
        restingState: VariantState,
        rankedMoves: [AnalysisLine] = [],
        guideTargetSquare: Square? = nil,
        isInputEnabled: Bool,
        invalidMoveNonce: Int,
        finale: BoardFinale? = nil,
        cornerRadius: CGFloat = OddfishTheme.Radius.board,
        onTap: @escaping (Square) -> Void,
        onDragStart: @escaping (Square) -> Void,
        onMove: @escaping (Square, Square) -> Bool
    ) {
        self.position = position
        self.mode = mode
        self.playerColor = playerColor
        self.selectedSquare = selectedSquare
        self.legalMoves = legalMoves
        self.showsMoveHints = showsMoveHints
        self.lastMove = lastMove
        self.restingState = restingState
        self.rankedMoves = rankedMoves
        self.guideTargetSquare = guideTargetSquare
        self.isInputEnabled = isInputEnabled
        self.invalidMoveNonce = invalidMoveNonce
        self.finale = finale
        self.cornerRadius = cornerRadius
        self.onTap = onTap
        self.onDragStart = onDragStart
        self.onMove = onMove
        _board = State(initialValue: TrackedBoard(position: position))
    }

    /// The position the piece layer is currently drawing, together with the
    /// identities that belong to it. Keeping them in one value means the two can
    /// never be read out of step.
    private struct TrackedBoard: Equatable {
        var position: Position
        var identity: BoardPieceIdentity

        init(position: Position) {
            self.position = position
            self.identity = BoardPieceIdentity(position)
        }

        mutating func advance(to next: Position, lastMove: Move?) {
            identity.advance(from: position, to: next, lastMove: lastMove)
            position = next
        }
    }

    private struct DragState: Equatable {
        let source: Square
        var translation: CGSize
        var target: Square?
    }

    /// The two derived values that cost real work, computed once per body
    /// evaluation and handed down to the layers that need them.
    ///
    /// Both used to be recomputed inside the accessibility label and hint of
    /// every one of the 64 input squares. `checkedKingSquare` runs full attack
    /// detection, so a single render of the board did it 64 times over — and
    /// the board re-renders on every replay step and on every frame of a drag.
    private struct Derived {
        let checkedKing: Square?
        let rankedDestinations: [RankedDestination]
    }

    var body: some View {
        let derived = Derived(checkedKing: checkedKingSquare, rankedDestinations: rankedDestinations)

        return GeometryReader { proxy in
            // Snap to a whole number of squares. A fractional cell size makes
            // rasterised squares differ by a pixel across the board, which is
            // exactly the uneven grid the old layout produced.
            let raw = min(proxy.size.width, proxy.size.height)
            let side = max(8, (raw / 8).rounded(.down) * 8)
            let metrics = BoardMetrics(side: side, perspective: BoardPerspective(color: playerColor))

            ZStack(alignment: .topLeading) {
                surface(metrics)
                pieceLayer(metrics)
                markerLayer(metrics, checkedKing: derived.checkedKing)
                analysisLayer(metrics, ranked: derived.rankedDestinations)
                inputLayer(metrics, derived: derived)
                if let drag {
                    draggedPiece(drag, metrics: metrics)
                }
                if let finale {
                    finaleLayer(finale, metrics: metrics)
                }
            }
            .frame(width: side, height: side)
            .modifier(BoardShake(nonce: shakeNonce, enabled: !reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: invalidMoveNonce) { _, _ in shakeNonce += 1 }
            .onChange(of: position) { previous, current in
                noteCapture(from: previous, to: current)
                board.advance(to: current, lastMove: lastMove)
            }
            .onChange(of: derived.checkedKing) { _, current in
                guard current != nil else { return }
                pulseCheck()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chess board, \(playerColor.rawValue) at the bottom")
    }

    // MARK: - Layers

    /// Squares, their state washes, and the coordinates. Clipped to the board
    /// shape so the plate's rounded corners and border are actually visible —
    /// previously square cells covered the rounded plate entirely.
    private func surface(_ metrics: BoardMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<64, id: \.self) { index in
                let square = Square(file: index % 8, rank: index / 8)
                squareBackground(square, metrics: metrics)
                    .frame(width: metrics.cell, height: metrics.cell)
                    .position(metrics.center(of: square))
            }
            if decoration.showsCoordinates {
                coordinates(metrics)
            }
        }
        .frame(width: metrics.side, height: metrics.side)
        .clipShape(shape)
        .shadow(color: .black.opacity(cornerRadius > 0 ? 0.45 : 0), radius: 20, y: 10)
        .accessibilityHidden(true)
    }

    /// Everything that describes a square's *state* rather than its colour.
    ///
    /// Each of these is a flat wash of one token, at one of two opacities. The
    /// previous board mixed a radial gradient, a stroked border and a flat fill
    /// in the same stack, so three cues that mean three different things all
    /// looked like different bugs in the same drawing.
    @ViewBuilder
    private func squareBackground(_ square: Square, metrics: BoardMetrics) -> some View {
        ZStack {
            Rectangle().fill(
                metrics.isLight(square) ? theme.lightSquare : theme.darkSquare
            )

            if decoration.highlightsLastMove, lastMove?.from == square || lastMove?.to == square {
                Rectangle()
                    .fill(theme.highlight.opacity(metrics.isLight(square) ? 0.52 : 0.42))
                    .transition(.opacity)
            }

            if selectedSquare == square || drag?.source == square {
                Rectangle().fill(theme.highlight.opacity(0.66))
            }

            if captureFlash == square {
                Rectangle().fill(theme.warning.opacity(0.55))
            }
        }
        .animation(reduceMotion ? nil : OddfishTheme.Motion.chrome, value: lastMove)
        .animation(reduceMotion ? nil : OddfishTheme.Motion.instant, value: selectedSquare)
        .animation(reduceMotion ? nil : OddfishTheme.Motion.captureFlash, value: captureFlash)
    }

    /// Rank and file labels, coloured from the square they actually sit on. The
    /// previous version guessed the parity separately and landed low-contrast on
    /// some of them.
    private func coordinates(_ metrics: BoardMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<8, id: \.self) { file in
                let square = Square(file: file, rank: metrics.perspective.bottomRank)
                coordinateLabel(String(Array("abcdefgh")[file]), on: square, metrics: metrics)
                    .padding(metrics.coordinateInset)
                    .frame(width: metrics.cell, height: metrics.cell, alignment: .bottomTrailing)
                    .position(metrics.center(of: square))
            }
            ForEach(0..<8, id: \.self) { rank in
                let square = Square(file: metrics.perspective.leftFile, rank: rank)
                coordinateLabel("\(rank + 1)", on: square, metrics: metrics)
                    .padding(metrics.coordinateInset)
                    .frame(width: metrics.cell, height: metrics.cell, alignment: .topLeading)
                    .position(metrics.center(of: square))
            }
        }
        .frame(width: metrics.side, height: metrics.side, alignment: .topLeading)
    }

    private func coordinateLabel(_ text: String, on square: Square, metrics: BoardMetrics) -> some View {
        let color = metrics.isLight(square)
            ? theme.coordinate(onLight: true)
            : theme.coordinate(onLight: false)

        // Coordinates are redundant decoration: every interactive square has
        // a complete VoiceOver label. Draw the geometry-bound glyph into a
        // canvas so the Dynamic Type audit does not mistake it for readable UI
        // copy that should grow beyond the square it belongs to.
        return Canvas { context, size in
            let label = context.resolve(
                Text(text)
                    .font(.system(size: metrics.coordinateFont, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
            )
            context.draw(
                label,
                at: CGPoint(x: size.width / 2, y: size.height / 2),
                anchor: .center
            )
        }
        .frame(
            width: metrics.coordinateFont * 1.25,
            height: metrics.coordinateFont * 1.35
        )
        .accessibilityHidden(true)
    }

    /// Pieces live above the squares and outside the board clip, so a lifted or
    /// travelling piece is never sliced off at the edge. Keyed by identity token
    /// so a move slides rather than cross-fading.
    private func pieceLayer(_ metrics: BoardMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(placements, id: \.token) { placement in
                pieceContent(placement, metrics: metrics)
                    .frame(width: metrics.cell, height: metrics.cell)
                    .position(metrics.center(of: placement.square))
            }
        }
        .frame(width: metrics.side, height: metrics.side)
        .animation(reduceMotion ? nil : OddfishTheme.Motion.piece, value: board.position)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pieceContent(_ placement: Placement, metrics: BoardMetrics) -> some View {
        if drag?.source == placement.square {
            // The lifted piece is drawn by the drag layer instead.
            Color.clear
        } else {
            ChessPieceView(piece: placement.piece, square: metrics.cell)
                .overlay(alignment: .topTrailing) {
                    let rest = restingState.restTurns(at: placement.square)
                    if rest > 0 {
                        RestBadge(turns: rest, size: metrics.restBadge)
                            .padding(metrics.cell * 0.04)
                    }
                }
        }
    }

    /// Move markers and the check pulse, above the pieces.
    ///
    /// Quiet dots and capture rings are one layer because they answer one
    /// question — *where can this piece go* — and separating them meant the
    /// two halves of the answer were drawn at different depths.
    private func markerLayer(_ metrics: BoardMetrics, checkedKing: Square?) -> some View {
        ZStack(alignment: .topLeading) {
            if let king = checkedKing, checkPulse > 0.001 {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [theme.warning.opacity(0.9), theme.warning.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: metrics.cell * 0.68
                        )
                    )
                    .frame(width: metrics.cell * 1.36, height: metrics.cell * 1.36)
                    .scaleEffect(0.72 + 0.28 * checkPulse)
                    .opacity(Double(checkPulse))
                    .blendMode(.plusLighter)
                    .position(metrics.center(of: king))
            }

            // The transition is attached to the marker itself and only then
            // wrapped in a cell and positioned. Declaring it outside `.position`
            // scales the board-sized layer instead of the dot, which drags every
            // marker toward the centre of the board as it appears.
            ForEach(quietTargets, id: \.self) { square in
                Circle()
                    .fill(theme.moveDot(onLight: metrics.isLight(square)))
                    .frame(width: metrics.quietDot, height: metrics.quietDot)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                    .frame(width: metrics.cell, height: metrics.cell)
                    .position(metrics.center(of: square))
            }

            ForEach(captureTargets, id: \.self) { square in
                Circle()
                    .strokeBorder(theme.moveDot(onLight: metrics.isLight(square)), lineWidth: metrics.captureRingWidth)
                    .padding(metrics.captureRingInset)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
                    .frame(width: metrics.cell, height: metrics.cell)
                    .position(metrics.center(of: square))
            }

            if let target = drag?.target, target != drag?.source {
                Rectangle()
                    .strokeBorder(OddfishTheme.ivory.opacity(0.9), lineWidth: metrics.targetRingWidth)
                    .frame(width: metrics.cell, height: metrics.cell)
                    .position(metrics.center(of: target))
            }
        }
        .frame(width: metrics.side, height: metrics.side)
        .animation(reduceMotion ? nil : OddfishTheme.Motion.chrome, value: selectedSquare)
        .allowsHitTesting(false)
    }

    /// Engine ranks are intentionally attached to destination squares instead
    /// of repeated in a detached list. Gil's gold review marker is a full-square
    /// outline so it cannot be mistaken for one of those current-position ranks.
    private func analysisLayer(_ metrics: BoardMetrics, ranked: [RankedDestination]) -> some View {
        ZStack(alignment: .topLeading) {
            if let guideTargetSquare {
                RoundedRectangle(cornerRadius: metrics.cell * 0.12, style: .continuous)
                    .strokeBorder(
                        OddfishTheme.Guide.body,
                        style: StrokeStyle(
                            lineWidth: max(2, metrics.cell * 0.055),
                            dash: [metrics.cell * 0.12, metrics.cell * 0.07]
                        )
                    )
                    .padding(metrics.cell * 0.045)
                    .frame(width: metrics.cell, height: metrics.cell)
                    .position(metrics.center(of: guideTargetSquare))
                    .accessibilityElement()
                    .accessibilityLabel("Gil's suggested square, \(guideTargetSquare.algebraic)")
                    .accessibilityIdentifier("game-gil-square")
            }

            ForEach(ranked) { destination in
                Text("\(destination.rank)")
                    .font(.system(size: max(10, metrics.cell * 0.20), weight: .heavy, design: .rounded))
                    .foregroundStyle(destination.rank == 1 ? OddfishTheme.Guide.ink : OddfishTheme.ivory)
                    .frame(width: metrics.cell * 0.34, height: metrics.cell * 0.34)
                    .background(
                        destination.rank == 1 ? OddfishTheme.Guide.body : OddfishTheme.canvas.opacity(0.88),
                        in: Circle()
                    )
                    .overlay(Circle().stroke(OddfishTheme.ivory.opacity(0.55), lineWidth: 1))
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                    .position(
                        x: metrics.origin(of: destination.square).x + metrics.cell * 0.23,
                        y: metrics.origin(of: destination.square).y + metrics.cell * 0.23
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Move rank \(destination.rank), \(destination.square.algebraic)")
                    .accessibilityIdentifier("game-move-rank-\(destination.rank)")
            }
        }
        .frame(width: metrics.side, height: metrics.side)
        .allowsHitTesting(false)
    }

    /// The end of the game, on the board itself.
    ///
    /// This is the half-second the whole choreography exists to protect. It has
    /// to be legible with nothing on top of it, so it is drawn as a bloom
    /// centred on the mated king plus a badge that names the result — not as a
    /// dimming of the board, which is what the result scrim is for.
    private func finaleLayer(_ finale: BoardFinale, metrics: BoardMetrics) -> some View {
        let tint = finaleTint(finale)
        return ZStack(alignment: .topLeading) {
            if let square = finale.square {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.10), tint.opacity(0)],
                            center: .center,
                            startRadius: metrics.cell * 0.10,
                            endRadius: metrics.cell * 1.15
                        )
                    )
                    .frame(width: metrics.cell * 2.3, height: metrics.cell * 2.3)
                    .blendMode(.plusLighter)
                    .position(metrics.center(of: square))

                // A ring that expands past the king and fades, the way a struck
                // bell looks. One shot, not a loop.
                Circle()
                    .strokeBorder(tint.opacity(0.85), lineWidth: metrics.cell * 0.06)
                    .frame(width: metrics.cell * 1.9, height: metrics.cell * 1.9)
                    .transition(.scale(scale: 0.25).combined(with: .opacity))
                    .frame(width: metrics.cell, height: metrics.cell)
                    .position(metrics.center(of: square))

                FinaleBadge(text: finaleBadgeText(finale), tint: tint, cell: metrics.cell)
                    .position(
                        x: min(max(metrics.center(of: square).x, metrics.cell * 1.1), metrics.side - metrics.cell * 1.1),
                        y: metrics.center(of: square).y - metrics.cell * 0.78
                    )
            }
        }
        .frame(width: metrics.side, height: metrics.side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
    }

    private func finaleTint(_ finale: BoardFinale) -> Color {
        switch finale.kind {
        case .checkmate: finale.isPlayerWin ? OddfishTheme.gold : theme.warning
        case .resigned: theme.warning
        case .stalemate, .draw: OddfishTheme.ivory
        }
    }

    private func finaleBadgeText(_ finale: BoardFinale) -> String {
        switch finale.kind {
        case .checkmate: "CHECKMATE"
        case .stalemate: "STALEMATE"
        case .draw: "DRAW"
        case .resigned: "RESIGNED"
        }
    }

    /// Transparent hit targets on top of everything, so a touch always lands on
    /// a square regardless of what is drawn over it.
    private func inputLayer(_ metrics: BoardMetrics, derived: Derived) -> some View {
        ZStack {
            ForEach(0..<64, id: \.self) { index in
                let square = Square(file: index % 8, rank: index / 8)
                squareInput(square, metrics: metrics, derived: derived)
                    .position(metrics.center(of: square))
            }
        }
        .frame(width: metrics.side, height: metrics.side)
    }

    /// Gestures and accessibility are attached to the cell-sized view, *before*
    /// it is positioned. `.position` returns a container that fills the board, so
    /// a gesture added afterwards would cover all 64 squares instead of one.
    private func squareInput(_ square: Square, metrics: BoardMetrics, derived: Derived) -> some View {
        Color.clear
            .frame(width: metrics.cell, height: metrics.cell)
            .contentShape(Rectangle())
            .onTapGesture { if drag == nil { onTap(square) } }
            .gesture(dragGesture(for: square, metrics: metrics))
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(accessibilityLabel(for: square, checkedKing: derived.checkedKing))
            .accessibilityHint(accessibilityHint(for: square, ranked: derived.rankedDestinations))
            .accessibilityAction { onTap(square) }
    }

    @ViewBuilder
    private func draggedPiece(_ drag: DragState, metrics: BoardMetrics) -> some View {
        if let piece = position.piece(at: drag.source) {
            let base = metrics.center(of: drag.source)
            ChessPieceView(piece: piece, square: metrics.cell)
                .frame(width: metrics.cell, height: metrics.cell)
                .scaleEffect(1.16)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
                // Lifted clear of the fingertip, the way a physical piece would
                // be. Dropping this offset is why the old drag felt like
                // pushing a sticker rather than holding a piece.
                .position(x: base.x + drag.translation.width, y: base.y + drag.translation.height - metrics.cell * 0.22)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Derived state

    private struct Placement: Identifiable {
        let token: Int
        let square: Square
        let piece: Piece
        var id: Int { token }
    }

    private struct RankedDestination: Identifiable {
        let square: Square
        let rank: Int
        var id: Square { square }
    }

    private var rankedDestinations: [RankedDestination] {
        let grouped = Dictionary(grouping: rankedMoves, by: { $0.move.to })
        return grouped.compactMap { square, lines in
            guard let rank = lines.map(\.rank).min() else { return nil }
            return RankedDestination(square: square, rank: rank)
        }.sorted { $0.rank < $1.rank }
    }

    private var placements: [Placement] {
        var placements: [Placement] = []
        placements.reserveCapacity(32)
        for index in 0..<64 {
            let square = Square(file: index % 8, rank: index / 8)
            guard let piece = board.position.piece(at: square),
                  let token = board.identity.token(at: square) else { continue }
            placements.append(Placement(token: token, square: square, piece: piece))
        }
        return placements
    }

    /// Moves out of the selected square, which is what the markers describe.
    private var selectedMoves: [Move] {
        guard let selectedSquare else { return [] }
        return legalMoves.filter { $0.from == selectedSquare }
    }

    /// The subset actually drawn. Empty when the player has turned hints off.
    private var hintedMoves: [Move] {
        showsMoveHints ? selectedMoves : []
    }

    private var captureTargets: [Square] {
        hintedMoves.filter(\.isCapture).map(\.to)
    }

    private var quietTargets: [Square] {
        hintedMoves.filter { !$0.isCapture }.map(\.to)
    }

    /// The king currently in check, if either is.
    ///
    /// Walks board indices instead of `position.squares()`, and asks whether
    /// the king's own square is attacked instead of calling `isInCheck`, which
    /// would go and find the king again from scratch.
    private var checkedKingSquare: Square? {
        for index in 0..<64 {
            let square = Square(file: index % 8, rank: index / 8)
            guard let piece = position.piece(at: square), piece.kind == .king else { continue }
            if ChessEngine.isSquareAttacked(square, by: piece.color.opponent, in: position) { return square }
        }
        return nil
    }

    // MARK: - Gestures

    private func dragGesture(for square: Square, metrics: BoardMetrics) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard isInputEnabled else { return }
                if drag == nil {
                    guard position.piece(at: square)?.color == playerColor,
                          legalMoves.contains(where: { $0.from == square }) else { return }
                    onDragStart(square)
                    drag = DragState(
                        source: square,
                        translation: value.translation,
                        target: targetSquare(from: square, translation: value.translation, metrics: metrics)
                    )
                } else if drag?.source == square {
                    drag?.translation = value.translation
                    drag?.target = targetSquare(from: square, translation: value.translation, metrics: metrics)
                }
            }
            .onEnded { value in
                guard let drag, drag.source == square else { return }
                self.drag = nil
                let destination = targetSquare(from: square, translation: value.translation, metrics: metrics) ?? square
                _ = onMove(square, destination)
            }
    }

    private func targetSquare(from source: Square, translation: CGSize, metrics: BoardMetrics) -> Square? {
        let center = metrics.center(of: source)
        let x = center.x + translation.width
        // Matches the lift applied to the dragged piece, so the square under the
        // *piece* is the one that is targeted rather than the one under the
        // finger that is hidden by it.
        let y = center.y + translation.height - metrics.cell * 0.22
        let visualFile = Int((x / metrics.cell).rounded(.down))
        let visualRank = Int((y / metrics.cell).rounded(.down))
        guard (0..<8).contains(visualFile), (0..<8).contains(visualRank) else { return nil }
        return metrics.perspective.square(visualFile: visualFile, visualRank: visualRank)
    }

    // MARK: - Transient cues

    /// Flashes the square a piece was just taken on.
    ///
    /// Read from the position change rather than from `lastMove`, because a
    /// capture that arrives through undo, redo or a variant's own bookkeeping
    /// still removes a piece and should still be seen.
    private func noteCapture(from previous: Position, to current: Position) {
        guard !reduceMotion, let move = lastMove, move.isCapture else { return }
        guard previous.piece(at: move.to) != nil || move.flags.contains(.enPassant) else { return }
        let square = move.flags.contains(.enPassant)
            ? Square(file: move.to.file, rank: move.from.rank)
            : move.to
        captureFlash = square
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            if captureFlash == square { captureFlash = nil }
        }
    }

    private func pulseCheck() {
        guard !reduceMotion else { return }
        checkPulse = 0
        withAnimation(OddfishTheme.Motion.checkPulseIn) { checkPulse = 1 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(OddfishTheme.Beat.checkPulse))
            withAnimation(OddfishTheme.Motion.checkPulseOut) { checkPulse = 0 }
        }
    }

    // MARK: - Accessibility

    private func accessibilityLabel(for square: Square, checkedKing: Square?) -> String {
        guard let piece = position.piece(at: square) else { return "\(square.algebraic), empty" }
        var label = "\(square.algebraic), \(piece.color.rawValue) \(piece.kind.rawValue)"
        let rest = restingState.restTurns(at: square)
        if rest > 0 { label += ", resting for \(rest) more \(rest == 1 ? "turn" : "turns")" }
        if checkedKing == square { label += ", in check" }
        return label
    }

    private func accessibilityHint(for square: Square, ranked: [RankedDestination]) -> String {
        if guideTargetSquare == square {
            return "Gil's suggested square from the last move review"
        }
        if let rank = ranked.first(where: { $0.square == square })?.rank {
            return "Stockfish move rank \(rank) destination"
        }
        if let move = selectedMoves.first(where: { $0.to == square }) {
            return move.isCapture ? "Legal capture" : "Legal destination"
        }
        if selectedSquare == square { return "Selected. Double tap again to cancel." }
        return "Double tap to select or move"
    }
}

// MARK: - Small board pieces of furniture

/// The rejected-move shake.
///
/// A keyframe track rather than three chained `asyncAfter` closures. The old
/// version could not be interrupted: two rejections in quick succession left
/// timers from the first still firing into the second, so the board drifted off
/// centre and stayed there.
private struct BoardShake: ViewModifier {
    let nonce: Int
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyframeAnimator(
                initialValue: CGFloat.zero,
                trigger: nonce
            ) { view, offset in
                view.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(9, duration: 0.055)
                    CubicKeyframe(-7, duration: 0.070)
                    CubicKeyframe(4, duration: 0.060)
                    SpringKeyframe(0, duration: 0.16, spring: .snappy)
                }
            }
        } else {
            content
        }
    }
}

/// The word that names the result, over the board, in the half-second before
/// anything covers it.
private struct FinaleBadge: View {
    let text: String
    let tint: Color
    let cell: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: max(11, cell * 0.26), weight: .black, design: .rounded))
            .tracking(1.2)
            .foregroundStyle(OddfishTheme.onAccent)
            .padding(.horizontal, cell * 0.30)
            .padding(.vertical, cell * 0.14)
            .background(tint, in: Capsule())
            .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
            .fixedSize()
    }
}

/// Restfish rest indicator: one pip per remaining turn, on a ring.
private struct RestBadge: View {
    let turns: Int
    let size: CGFloat

    @Environment(\.boardTheme) private var theme
    private var tint: Color { theme.indicator }

    var body: some View {
        ZStack {
            Circle()
                .fill(OddfishTheme.canvas.opacity(0.92))
                .overlay {
                    Circle().strokeBorder(tint, lineWidth: max(1, size * 0.09))
                }
            HStack(spacing: size * 0.10) {
                ForEach(0..<max(1, turns), id: \.self) { _ in
                    Circle()
                        .fill(tint)
                        .frame(width: size * 0.18, height: size * 0.18)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Board") {
    ChessBoardView(
        position: .starting,
        mode: .classic,
        selectedSquare: Square("e2"),
        legalMoves: ChessEngine.legalMoves(in: .starting),
        showsMoveHints: true,
        lastMove: nil,
        restingState: VariantState(),
        isInputEnabled: true,
        invalidMoveNonce: 0,
        onTap: { _ in },
        onDragStart: { _ in },
        onMove: { _, _ in true }
    )
    .padding()
    .background(OddfishTheme.canvas)
}
