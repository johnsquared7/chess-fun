import SwiftUI

// The furniture around the board.
//
// The game screen used to put everything it knew into one dense card above the
// board — mode, opponent, status, evaluation, and rating — and everything it
// could do into a drawer below it. That is a lot of reading for a screen whose
// whole job is to let someone look at sixty-four squares.
//
// It is now two symmetrical player strips with the board between them, a move
// tape, and a four-item action bar. Each piece of furniture answers exactly one
// question, so none of them has to be studied.

// MARK: - Captured material

/// What one side has taken, and by how much they are ahead.
///
/// Derived from the game's own starting position rather than from a standard
/// army, because several modes begin with a different one and a hard-coded
/// eight-pawns assumption would report phantom captures on move one.
struct CapturedMaterial: Equatable {
    /// Pieces this side has taken, heaviest last, the way a chess site stacks them.
    let taken: [PieceKind]
    /// Positive when this side is ahead on material.
    let advantage: Int

    static let empty = CapturedMaterial(taken: [], advantage: 0)

    /// Cheapest to fifth-cheapest, which is the order every chess site stacks
    /// them in and the order a player scans.
    private static let order: [PieceKind] = [.pawn, .knight, .bishop, .rook, .queen]

    static func forSide(
        _ color: PieceColor,
        start: Position,
        current: Position
    ) -> CapturedMaterial {
        let opponent = color.opponent
        // One pass per board rather than one pass per piece kind. Both strips
        // recompute this whenever anything on the game screen changes.
        let before = census(of: opponent, in: start)
        let now = census(of: opponent, in: current)
        var taken: [PieceKind] = []
        for kind in order {
            // Promotion can push a count above its starting value; a negative
            // difference is not a capture, so it is clamped rather than
            // subtracted from another piece's tally.
            let lost = max(0, (before[kind] ?? 0) - (now[kind] ?? 0))
            taken.append(contentsOf: repeatElement(kind, count: lost))
        }
        return CapturedMaterial(taken: taken, advantage: current.materialBalance(for: color))
    }

    private static func census(of color: PieceColor, in position: Position) -> [PieceKind: Int] {
        var counts: [PieceKind: Int] = [:]
        for index in 0..<64 {
            let square = Square(file: index % 8, rank: index / 8)
            guard let piece = position.piece(at: square), piece.color == color else { continue }
            counts[piece.kind, default: 0] += 1
        }
        return counts
    }
}

/// The little row of taken pieces under a player's name. Overlapped, because at
/// this size a spaced row of eight pawns is wider than the name above it.
struct CapturedMaterialView: View {
    let material: CapturedMaterial
    let color: PieceColor
    var glyph: CGFloat = 15

    /// Shrinks the icons once the row gets long so 12+ captured pieces still
    /// fit in the single line the strip reserves for them. Without this the
    /// advantage label gets squeezed to ~1 character wide and its "+12" wraps
    /// into a vertical "+ / 1 / 2" stack.
    private var effectiveGlyph: CGFloat {
        let count = material.taken.count
        if count <= 8 { return glyph }
        if count <= 11 { return max(10, glyph * 0.9) }
        return max(9, glyph * 0.8)
    }

    private var pieceSpacing: CGFloat {
        material.taken.count > 8 ? -effectiveGlyph * 0.55 : -effectiveGlyph * 0.42
    }

    var body: some View {
        HStack(spacing: 3) {
            if !material.taken.isEmpty {
                HStack(spacing: pieceSpacing) {
                    ForEach(Array(material.taken.enumerated()), id: \.offset) { _, kind in
                        ChessPieceView(piece: Piece(color: color.opponent, kind: kind), square: effectiveGlyph * 1.5)
                            .frame(width: effectiveGlyph, height: effectiveGlyph)
                    }
                }
                // Never let a long row push the score out: clip the overflow
                // rather than growing a second line.
                .clipped()
            }
            if material.advantage > 0 {
                Text("+\(material.advantage)")
                    .font(.oddfishCaption.weight(.heavy))
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, material.taken.isEmpty ? 0 : 5)
            }
        }
        // Captured-piece glyphs stay compact, but the semantic advantage text
        // is allowed to claim its full Dynamic Type line height.
        .frame(minHeight: glyph)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHidden(material.taken.isEmpty && material.advantage <= 0)
    }

    private var accessibilityLabel: String {
        guard !material.taken.isEmpty else { return "" }
        let names = Dictionary(grouping: material.taken, by: { $0 })
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.value.count) \($0.key.rawValue)\($0.value.count == 1 ? "" : "s")" }
        let ahead = material.advantage > 0 ? ", \(material.advantage) ahead" : ""
        return "Captured: " + names.joined(separator: ", ") + ahead
    }
}

// MARK: - Player strip

/// One side of the board: who they are, what they have taken, and whether the
/// game is currently waiting on them.
///
/// Both strips are the same view. Symmetry is the point — a player should be
/// able to read the opponent's line and their own with one habit, not two.
struct GamePlayerStrip: View {
    enum Occupant {
        case player(GameMode)
        case opponent
    }

    let occupant: Occupant
    let name: String
    /// Shown as the rating chip. Nil hides the chip entirely.
    let rating: Int?
    let color: PieceColor
    let material: CapturedMaterial
    let isOnMove: Bool
    let isThinking: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OddfishTheme.Spacing.tight) {
                    HStack(spacing: 10) {
                        avatar
                        identity
                        Spacer(minLength: 4)
                    }
                    trailing
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 10) {
                    avatar
                    identity
                    Spacer(minLength: 4)
                    trailing
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Substantial enough to read as one of the two sides of the game rather
        // than as a caption, and it takes height the board cannot use anyway.
        .frame(minHeight: 62)
        .background {
            RoundedRectangle(cornerRadius: OddfishTheme.Radius.card, style: .continuous)
                .fill(OddfishTheme.surface)
        }
        .overlay {
            // The on-move cue is a border rather than a fill, so the strip does
            // not change weight every half-move and drag the eye off the board.
            RoundedRectangle(cornerRadius: OddfishTheme.Radius.card, style: .continuous)
                .strokeBorder(
                    isOnMove ? OddfishTheme.seaGlass.opacity(0.85) : OddfishTheme.line,
                    lineWidth: isOnMove ? 1.5 : 1
                )
        }
        .animation(reduceMotion ? nil : OddfishTheme.Motion.chrome, value: isOnMove)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOnMove ? .isSelected : [])
    }

    private var identity: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.oddfishHeadline)
                        .foregroundStyle(OddfishTheme.ivory)
                        .lineLimit(1)
                        // A name is one unbreakable word, so let it shrink
                        // before it truncates: at large text sizes the tail
                        // truncation alone turned "Stockfish" into "Stoc…"
                        // while there was still room to read it smaller.
                        .minimumScaleFactor(0.6)
                        .truncationMode(.tail)
                    if let rating {
                        Text("\(rating)")
                            .font(.oddfishNumeric)
                            .monospacedDigit()
                            .foregroundStyle(OddfishTheme.mutedInk)
                            // A rating is a single number and must never wrap.
                            // Without this, 3,600 broke after the "60" and put
                            // a lone "0" on a second line.
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(reduceMotion ? nil : .snappy, value: rating)
                    }
                }
                // Always reserves the captured row's height, even when empty,
                // so the strip (and the board below it) never changes height
                // when the first capture lands.
                if !material.taken.isEmpty || material.advantage > 0 {
                    CapturedMaterialView(material: material, color: color)
                        .frame(height: 15, alignment: .leading)
                } else {
                    Color.clear
                        .frame(height: 15)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OddfishTheme.Radius.tile, style: .continuous)
                .fill(OddfishTheme.surfaceHigh)
            switch occupant {
            case .player(let mode):
                ChessPieceView(piece: Piece(color: color, kind: .king), square: 30)
                    .frame(width: 30, height: 30)
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(mode.tint)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(OddfishTheme.surfaceHigh, lineWidth: 1.5))
                            .offset(x: 6, y: 4)
                    }
            case .opponent:
                GilView(size: 30, expression: isThinking ? .doubtful : .idle)
            }
        }
        .frame(width: 40, height: 40)
        .overlay {
            RoundedRectangle(cornerRadius: OddfishTheme.Radius.tile, style: .continuous)
                .strokeBorder(OddfishTheme.line, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailing: some View {
        // Fixed footprint regardless of turn state. Previously this was empty
        // when idle, "YOUR MOVE" on your turn, and dots while thinking — three
        // different widths/heights — so every half-move relaid out the strip
        // and nudged the board up/down by a point or two.
        Group {
            if isThinking {
                ThinkingDots()
            } else if isOnMove {
                Text("YOUR MOVE")
                    .font(.oddfishOverline)
                    .foregroundStyle(OddfishTheme.seaGlass)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: 1, height: 22)
                    .accessibilityHidden(true)
            }
        }
        .frame(minWidth: 86, alignment: .trailing)
        .frame(height: 22)
    }
}

/// Three dots that travel, so "thinking" is legible without a word for it.
struct ThinkingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(OddfishTheme.mutedInk)
                    .frame(width: 5, height: 5)
                    .opacity(reduceMotion ? 0.7 : (phase == index ? 1 : 0.32))
                    .scaleEffect(reduceMotion ? 1 : (phase == index ? 1.25 : 1))
            }
        }
        .frame(height: 22)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(260))
                withAnimation(OddfishTheme.Motion.thinkingDots) { phase = (phase + 1) % 3 }
            }
        }
        .accessibilityLabel("Thinking")
    }
}

// MARK: - Move tape

/// The played moves, in algebraic notation, scrolled to the end.
///
/// A running move list is the one piece of information a chess screen can show
/// for free: it takes a single line, it never needs to be opened, and it is the
/// answer to "what just happened" that a highlighted square only half gives.
struct MoveTapeView: View {
    /// Already-formatted notation, oldest first. The session caches it, because
    /// generating SAN needs a legal-move generation per move.
    let notation: [String]
    /// Which side opened. Everything else about numbering follows from it.
    let firstMoveColor: PieceColor
    private struct Entry: Identifiable {
        let ply: Int
        let number: Int
        let san: String
        let isWhite: Bool
        var id: Int { ply }
    }

    private var entries: [Entry] {
        // A game that starts with Black to move still numbers from one; the
        // side that opened just occupies the left-hand slot.
        notation.indices.map { index in
            Entry(
                ply: index,
                number: index / 2 + 1,
                san: notation[index],
                isWhite: index.isMultiple(of: 2) == (firstMoveColor == .white)
            )
        }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                Text("No moves yet")
                    .font(.oddfishCaption.weight(.semibold))
                    .foregroundStyle(OddfishTheme.faintInk)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(entries) { entry in
                                HStack(spacing: 4) {
                                    if entry.ply.isMultiple(of: 2) {
                                        Text("\(entry.number).")
                                            .font(.oddfishCaption.weight(.bold))
                                            .foregroundStyle(OddfishTheme.faintInk)
                                            .monospacedDigit()
                                    }
                                    Text(entry.san)
                                        .font(.oddfishBody.weight(.heavy))
                                        .foregroundStyle(
                                            entry.ply == entries.count - 1
                                                ? OddfishTheme.onAccent
                                                : OddfishTheme.mutedInk
                                        )
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background {
                                    if entry.ply == entries.count - 1 {
                                        Capsule().fill(OddfishTheme.seaGlass)
                                    }
                                }
                                .id(entry.ply)
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: entries.count) { _, _ in
                        withAnimation(OddfishTheme.Motion.standard) {
                            proxy.scrollTo(entries.count - 1, anchor: .trailing)
                        }
                    }
                }
            }
        }
        // Keep the empty and populated states at least the same height without
        // clipping scaled notation into a fixed 30pt slot.
        .frame(minHeight: 30)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Move list")
        .accessibilityIdentifier("game-move-tape")
    }
}

// MARK: - End of game

/// The clock that keeps the result card off the mating move.
///
/// This exists as its own type for one reason: the bug it fixes is a timing
/// bug, and a timing bug that lives inside a view body cannot be tested. The
/// durations are parameters so a test can run the whole sequence in
/// milliseconds and still assert the order.
enum EndgameChoreography {
    /// What the game screen is allowed to draw.
    enum Stage: Int, Comparable, Sendable {
        /// The game is running, or the board has not finished the mating move.
        case idle
        /// The board owns the screen: mate bloom, badge, nothing on top.
        case boardFinale
        /// The scrim and the result card may come up.
        case curtain

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Runs the sequence, handing each stage back as it is reached.
    ///
    /// Cancellation leaves the stage where it was: a player who taps Rematch
    /// mid-sequence gets a fresh board, not a curtain that arrives afterwards.
    static func play(
        travel: Duration = .milliseconds(Int(OddfishTheme.Beat.pieceTravel * 1000)),
        hold: Duration = .milliseconds(Int(OddfishTheme.Beat.terminalHold * 1000)),
        onStage: @MainActor @Sendable (Stage) -> Void
    ) async {
        // The mating piece is still travelling. Nothing may be drawn over it.
        do { try await Task.sleep(for: travel) } catch { return }
        onStage(.boardFinale)
        // The board says checkmate on its own. This is the beat the whole
        // sequence exists to protect.
        do { try await Task.sleep(for: hold) } catch { return }
        onStage(.curtain)
    }
}

/// The result card.
///
/// Its lines arrive one behind the next rather than as a block, which is the
/// difference between a card that appears and a card that is delivered. Under
/// Reduce Motion the stagger collapses to a single fade.
struct GameResultOverlay: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let isWin: Bool
    let award: CrownAward?
    let ineligibleNote: String?
    let onRematch: () -> Void
    let onChangeMode: () -> Void
    let onReview: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @AccessibilityFocusState private var isTitleFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 0) {
                emblem
                    .oddfishStagger(0, active: revealed, reduceMotion: reduceMotion)
                    .padding(.bottom, 14)

                Text(title)
                    .font(.system(.title, design: .rounded).weight(.black))
                    .foregroundStyle(OddfishTheme.ivory)
                    .multilineTextAlignment(.center)
                    .oddfishStagger(1, active: revealed, reduceMotion: reduceMotion)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
                    .accessibilityIdentifier("game-result-title")

                Text(subtitle)
                    .font(.oddfishBody)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .padding(.top, 5)
                    .oddfishStagger(2, active: revealed, reduceMotion: reduceMotion)

                if let award {
                    CrownAwardSummary(award: award, prominent: true)
                        .padding(.top, 16)
                        .oddfishStagger(3, active: revealed, reduceMotion: reduceMotion)
                        .accessibilityIdentifier("game-crown-award")
                } else if let ineligibleNote {
                    Text(ineligibleNote)
                        .font(.oddfishCaption)
                        .foregroundStyle(OddfishTheme.gold)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                        .oddfishStagger(3, active: revealed, reduceMotion: reduceMotion)
                        .accessibilityIdentifier("game-crown-ineligible")
                }

                VStack(spacing: 10) {
                    Button("Rematch", systemImage: "arrow.clockwise", action: onRematch)
                        .buttonStyle(OddfishPrimaryButtonStyle())
                    if let onReview {
                        Button("Review the board", systemImage: "eye", action: onReview)
                            .buttonStyle(OddfishSecondaryButtonStyle())
                            .accessibilityIdentifier("game-result-review")
                    }
                    Button("Change mode", action: onChangeMode)
                        .buttonStyle(OddfishSecondaryButtonStyle())
                }
                .padding(.top, 22)
                .oddfishStagger(4, active: revealed, reduceMotion: reduceMotion)
            }
            .padding(26)
            .frame(maxWidth: 360)
            .background {
                RoundedRectangle(cornerRadius: OddfishTheme.Radius.panel, style: .continuous)
                    .fill(OddfishTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: OddfishTheme.Radius.panel, style: .continuous)
                            .strokeBorder(OddfishTheme.lineStrong, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.55), radius: 30, y: 16)
            }
            .padding(.horizontal, OddfishTheme.Spacing.loose)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.90)
            .opacity(revealed ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.2) : OddfishTheme.Motion.celebrate, value: revealed)
        }
        .onAppear {
            revealed = true
            guard OddfishAccessibility.isVoiceOverRunning else { return }
            Task { @MainActor in
                // Focus after the card has entered the accessibility tree.
                await Task.yield()
                isTitleFocused = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("game-result-overlay")
    }

    /// A win gets a ring behind the glyph; a loss does not. The difference has
    /// to be readable before the words are.
    private var emblem: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(isWin ? 0.16 : 0.10))
                .frame(width: 76, height: 76)
            if isWin {
                Circle()
                    .strokeBorder(tint.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 92, height: 92)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.5)
                    .opacity(revealed ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : OddfishTheme.Motion.celebrate.delay(0.10),
                        value: revealed
                    )
            }
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Action bar

/// The four things a player reaches for mid-game, and the handle for everything
/// else. Modelled on the one bar every chess app converges on, because it is
/// the arrangement that survives being used one-handed without looking.
struct GameActionBar: View {
    let canUndo: Bool
    let canRedo: Bool
    let isPaused: Bool
    let isPlayable: Bool
    let onOptions: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onPause: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            OddfishActionBarButton(title: "Options", systemImage: "line.3.horizontal", action: onOptions)
                .accessibilityIdentifier("game-options")
            OddfishActionBarButton(
                title: isPaused ? "Resume" : "Pause",
                systemImage: isPaused ? "play.fill" : "pause.fill",
                isEnabled: isPlayable,
                action: onPause
            )
            .accessibilityIdentifier("game-pause")
            OddfishActionBarButton(
                title: "Undo",
                systemImage: "arrow.uturn.backward",
                isEnabled: canUndo,
                action: onUndo
            )
            .accessibilityIdentifier("game-undo")
            OddfishActionBarButton(
                title: "Redo",
                systemImage: "arrow.uturn.forward",
                isEnabled: canRedo,
                action: onRedo
            )
            .accessibilityIdentifier("game-redo")
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("game-action-bar")
    }
}
