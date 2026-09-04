import SwiftUI

/// The visual language for Oddfish: a quiet, midnight ocean with small flashes
/// of coral.
///
/// The palette was rebuilt around one rule borrowed from the chess apps that
/// feel effortless: **flat surfaces, one accent, and a value ramp you can read
/// in a corridor.** The previous version leaned on translucent material, a
/// gradient canvas, and five accents competing on a single screen. Blur is
/// expensive, it muddies small type, and it makes every card the same weight —
/// which is the opposite of hierarchy. Surfaces are now opaque fills that step
/// cleanly, and colour is spent only where it means something.
nonisolated enum OddfishTheme {

    // MARK: - Surfaces
    //
    // Four steps, each a clear jump in luminance. A view picks the step that
    // matches its depth; it never invents an opacity.

    /// The app background. Nothing sits behind it.
    static let canvas = Color(red: 0.055, green: 0.086, blue: 0.125)
    /// Cards, strips, and bars that sit on the canvas.
    static let surface = Color(red: 0.098, green: 0.141, blue: 0.192)
    /// Rows, fields and controls inside a surface.
    static let surfaceHigh = Color(red: 0.145, green: 0.200, blue: 0.263)
    /// The topmost step: pressed states, and chrome that must float.
    static let surfaceTop = Color(red: 0.196, green: 0.263, blue: 0.337)

    /// Retained name for the second step. New code should say `surface`.
    static let canvasRaised = surface

    // MARK: - Ink

    /// Headings and anything the eye must land on first.
    static let ivory = Color(red: 0.949, green: 0.965, blue: 0.973)
    /// Supporting copy. Tuned to retain at least normal-text contrast even on
    /// the highest surface step rather than fading into the card behind it.
    static let mutedInk = Color(red: 0.680, green: 0.750, blue: 0.810)
    /// Labels, units, and disabled text. This is intentionally quieter than
    /// `mutedInk`, but no longer relies on low contrast to create hierarchy.
    static let faintInk = Color(red: 0.600, green: 0.690, blue: 0.760)

    // MARK: - Accent
    //
    // One accent carries every primary action in the app. Coral belongs to the
    // Split O's deliberately odd center tile, urgency, and loss; gold belongs
    // to crowns and Gil. Nothing else gets a colour.

    static let seaGlass = Color(red: 0.310, green: 0.878, blue: 0.867)
    /// The pressed state of an accent fill.
    static let seaGlassPressed = Color(red: 0.216, green: 0.706, blue: 0.702)
    static let seaGlassDeep = Color(red: 0.110, green: 0.490, blue: 0.549)
    /// Text and glyphs drawn on top of an accent fill.
    static let onAccent = Color(red: 0.031, green: 0.063, blue: 0.098)

    static let coral = Color(red: 1.0, green: 0.40, blue: 0.36)
    static let gold = Color(red: 1.00, green: 0.78, blue: 0.35)

    /// The one hairline in the app.
    static let line = Color.white.opacity(0.08)
    /// A stronger divider, for separating a bar from the content it controls.
    static let lineStrong = Color.white.opacity(0.14)

    // MARK: - Board

    /// Board colours live with the rest of the palette so the squares, the piece
    /// fills, and the indicator tints are tuned against each other in one place.
    enum Board {
        static let lightSquare = Color(red: 0.792, green: 0.871, blue: 0.882)
        static let darkSquare = Color(red: 0.220, green: 0.400, blue: 0.478)
        static let whitePieceFill = Color(red: 0.98, green: 0.97, blue: 0.93)
        static let whitePieceOutline = Color(red: 0.05, green: 0.11, blue: 0.16)
        static let blackPieceFill = Color(red: 0.09, green: 0.16, blue: 0.22)
        static let blackPieceOutline = Color(red: 0.86, green: 0.93, blue: 0.95)
        static let frame = Color(red: 0.04, green: 0.09, blue: 0.15)
    }

    // MARK: - Guide

    /// Gil's palette. He needs tokens of his own, distinct from the mode accents,
    /// so he reads as a character rather than another game mode.
    ///
    /// Gold is the one warm note in a midnight-navy app, which is the whole
    /// emotional job: a small lantern swimming next to something cold.
    enum Guide {
        static let body = OddfishTheme.gold
        static let bodyDeep = Color(red: 0.78, green: 0.52, blue: 0.16)
        /// Contour, brow, mouth and iris. Shared with the black pieces so Gil
        /// belongs to the same drawing as the board.
        static let ink = Color(red: 0.05, green: 0.11, blue: 0.17)
        static let bar = Color(red: 0.08, green: 0.20, blue: 0.32)
        static let sclera = ivory
    }

    // MARK: - Spacing

    /// One spacing ramp for every surface. Views pick a step; they do not invent
    /// their own numbers.
    enum Spacing {
        /// 4 — inside a control, between an icon and its own label.
        static let hairline: CGFloat = 4
        /// 8 — between tightly-related lines of text.
        static let tight: CGFloat = 8
        /// 12 — between controls in a row.
        static let snug: CGFloat = 12
        /// 16 — the default gap between elements in a stack.
        static let regular: CGFloat = 16
        /// 24 — between distinct groups on a screen.
        static let loose: CGFloat = 24
        /// 32 — between major sections.
        static let section: CGFloat = 32

        /// Screen edge inset. Compact widths keep the board as wide as possible.
        static let screenEdge: CGFloat = 16
        static let screenEdgeRegular: CGFloat = 28
    }

    // MARK: - Radius

    enum Radius {
        static let control: CGFloat = 14
        static let card: CGFloat = 18
        static let panel: CGFloat = 24
        static let board: CGFloat = 8
        /// Avatars and other small square tiles.
        static let tile: CGFloat = 12
    }

    // MARK: - Motion

    /// Motion is a ramp, like spacing. A view picks the step that matches what
    /// it is doing; it does not invent a spring.
    ///
    /// The governing rule: **the player must finish seeing one thing before the
    /// next one starts.** Anything that arrives on top of the board waits for
    /// the board to settle first — see `Beat`.
    enum Motion {
        /// Press feedback, and anything the finger is already touching.
        static let instant = Animation.easeOut(duration: 0.12)
        /// Indicator and chrome fades.
        static let chrome = Animation.easeOut(duration: 0.18)
        /// Layout that changes size, rows that appear, sheets that resize.
        static let standard = Animation.spring(response: 0.34, dampingFraction: 0.86)
        /// Piece travel. Long enough to be followed by the eye, damped enough
        /// not to wobble. This is the beat everything after a move waits on.
        static let piece = Animation.spring(response: 0.30, dampingFraction: 0.82)
        /// A panel or overlay arriving, with a trace of overshoot.
        static let entrance = Animation.spring(response: 0.44, dampingFraction: 0.76)
        /// Anything leaving. Exits never bounce.
        static let exit = Animation.easeIn(duration: 0.20)
        /// The result card, and nothing else. Deliberately slower and looser
        /// than `entrance`: it is the one moment in a game worth waiting for.
        static let celebrate = Animation.spring(response: 0.58, dampingFraction: 0.66)

        // MARK: Board
        //
        // The board's own cues. These were durations written at the call site,
        // which is the one thing this ramp exists to prevent: a timing tuned
        // against nothing is a timing nobody can tune against later.

        /// The wash that crosses a square as a piece is taken.
        static let captureFlash = Animation.easeOut(duration: 0.22)
        /// A check arriving. Deliberately asymmetric — the glow snaps on and
        /// then leaves twice as slowly, so the eye is caught and then released
        /// rather than blinked at.
        static let checkPulseIn = Animation.easeOut(duration: 0.14)
        static let checkPulseOut = Animation.easeIn(duration: 0.28)
        /// One step of the opponent's thinking dots.
        static let thinkingDots = Animation.easeInOut(duration: 0.22)

        // MARK: Guide
        //
        // Standing rule for the guide: entrances overshoot, exits do not.
        // Anything arriving uses a spring damped at 0.72 or less; anything
        // leaving uses a short ease-in. A bouncy exit reads as a bug.

        /// Face changes. The slight overshoot is the whole difference between
        /// a character that is alive and one that is mechanical.
        static let guidePose = Animation.spring(response: 0.34, dampingFraction: 0.72)
        /// Entrances, with visible overshoot.
        static let guidePop = Animation.spring(response: 0.30, dampingFraction: 0.52)
        /// Landings, with no wobble.
        static let guideSettle = Animation.spring(response: 0.42, dampingFraction: 0.86)
        static let guideExit = Animation.easeIn(duration: 0.18)
        static let guideGaze = Animation.easeOut(duration: 0.14)
        /// A blink, in two halves. The lid drops faster than it lifts, which is
        /// what stops the blink reading as a wink.
        static let guideBlinkClose = Animation.easeIn(duration: 0.07)
        static let guideBlinkOpen = Animation.easeOut(duration: 0.11)

        /// Repeating animations are returned through functions that take the
        /// Reduce Motion flag and answer `nil`, rather than as plain constants.
        ///
        /// This is deliberate: a `repeatForever` constant that someone forgets
        /// to gate keeps running under Reduce Motion forever and nothing fails
        /// loudly. Making the flag part of the call means a caller cannot get
        /// the animation without having considered the question.
        static func guideIdle(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 2.4).repeatForever(autoreverses: true)
        }

        /// The tail. Its period is deliberately not a multiple of the idle
        /// period, so the two drift in and out of phase and the loop never
        /// becomes visible.
        static func guideFlow(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 2.9).repeatForever(autoreverses: true)
        }

        static func guideTalk(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.16).repeatForever(autoreverses: true)
        }
    }

    /// The choreography clock, in seconds.
    ///
    /// Every timed hand-off in the app is named here rather than being a
    /// literal at the call site, because the bug these numbers exist to fix is
    /// invisible in any one file: the mating move used to be covered by the
    /// result scrim while the piece was still sliding, so the most important
    /// half-second of a game was never actually seen.
    ///
    /// The end-of-game sequence reads: the piece lands, the board says
    /// *checkmate* on its own for over half a second, and only then does
    /// anything cover it.
    enum Beat {
        /// How long a piece takes to reach its square. Matches `Motion.piece`.
        static let pieceTravel: Double = 0.30
        /// The board's own terminal flourish — the mate bloom on the losing
        /// king — plays with nothing on top of it for this long.
        static let terminalHold: Double = 0.62
        /// Board settled plus its flourish: when covering chrome may begin.
        static var resultCurtain: Double { pieceTravel + terminalHold }
        /// How long a check pulse stays legible.
        static let checkPulse: Double = 0.45
        /// The gap between consecutive lines of a staggered entrance.
        static let stagger: Double = 0.055
    }

}

/// The app's type ramp. Every size in the app comes from here so headings,
/// body copy, and labels stay in proportion across screens.
extension Font {
    /// The brand wordmark uses the standard system face so its static launch
    /// rendering and its SwiftUI rendering share the same typographic voice.
    static let oddfishWordmark = Font.system(.largeTitle, design: .default).weight(.black)
    /// Screen-owning title, e.g. the home wordmark.
    static let oddfishDisplay = Font.system(.largeTitle, design: .rounded).weight(.black)
    /// Section or sheet title.
    static let oddfishTitle = Font.system(.title2, design: .rounded).weight(.bold)
    /// Card title, status line.
    static let oddfishHeadline = Font.system(.headline, design: .rounded).weight(.bold)
    /// Default running copy.
    static let oddfishBody = Font.system(.subheadline, design: .rounded)
    /// Supporting copy under a headline.
    static let oddfishCaption = Font.system(.caption, design: .rounded)
    /// Control labels.
    static let oddfishControl = Font.system(.subheadline, design: .rounded).weight(.bold)
    /// Numeric values that must not reflow as digits change.
    static let oddfishNumeric = Font.system(.subheadline, design: .monospaced).weight(.bold)
    /// The small all-caps label above a value. Paired with `.tracking(0.8)`.
    static let oddfishOverline = Font.system(.caption2, design: .rounded).weight(.heavy)
}

extension View {
    /// The app's ground, and the only way to paint it.
    ///
    /// Flat, not a gradient. The gradient this replaces spanned 0.063 to 0.055
    /// luminance — invisible on a phone, by its own description — but it left
    /// every label on top of it sitting over an indeterminate background, which
    /// is enough for automated contrast sampling to refuse to measure the pair.
    /// The home screen had already been moved to a solid fill for exactly that
    /// reason; the three screens still on the gradient were the ones failing.
    func oddfishScreenBackground() -> some View {
        background(OddfishTheme.canvas.ignoresSafeArea())
    }

    /// An opaque card. Named for what it is now rather than for the material it
    /// used to be. The transitional `oddfishGlassCard` spelling is gone: two
    /// names for one card meant a screen's depth could not be read from its
    /// call, and half the app was still describing a material this theme
    /// deliberately stopped using.
    func oddfishSurface(
        _ fill: Color = OddfishTheme.surface,
        cornerRadius: CGFloat = OddfishTheme.Radius.card,
        stroke: Color = OddfishTheme.line
    ) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fill)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                }
        }
    }

    /// Fades and lifts a view in, one step behind the step before it. Used for
    /// the lines of a result card so they arrive as a sentence rather than as a
    /// block.
    func oddfishStagger(_ index: Int, active: Bool, reduceMotion: Bool) -> some View {
        opacity(active ? 1 : 0)
            .offset(y: active || reduceMotion ? 0 : 10)
            .animation(
                reduceMotion
                    ? OddfishTheme.Motion.chrome
                    : OddfishTheme.Motion.entrance.delay(Double(index) * OddfishTheme.Beat.stagger),
                value: active
            )
    }
}

struct OddfishEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.oddfishOverline)
            .tracking(1.4)
            .foregroundStyle(OddfishTheme.faintInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Buttons
//
// Four button roles, and no view builds its own. The primary is the loudest
// thing on any screen it appears on, which is only possible because nothing
// else in the app uses a filled accent.

/// Fills its width, 54pt tall, accent fill with dark text.
struct OddfishPrimaryButtonStyle: ButtonStyle {
    var tint: Color = OddfishTheme.seaGlass
    var fillsWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.oddfishControl)
            .foregroundStyle(OddfishTheme.onAccent)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 54)
            .padding(.vertical, 8)
            .padding(.horizontal, fillsWidth ? 0 : 22)
            .background(
                RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? OddfishTheme.seaGlassPressed : tint)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(OddfishTheme.Motion.instant, value: configuration.isPressed)
    }
}

/// The quieter sibling: a raised surface with ivory text.
struct OddfishSecondaryButtonStyle: ButtonStyle {
    var fillsWidth: Bool = true

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.oddfishControl)
            .foregroundStyle(OddfishTheme.ivory)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 50)
            .padding(.vertical, 7)
            .padding(.horizontal, fillsWidth ? 0 : 18)
            .background(
                RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? OddfishTheme.surfaceTop : OddfishTheme.surfaceHigh)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous)
                    .strokeBorder(OddfishTheme.line, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(OddfishTheme.Motion.instant, value: configuration.isPressed)
    }
}

/// Whole rows and cards that behave as buttons. Presses register as a small
/// scale and a darkening, never as a colour change.
struct OddfishPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(OddfishTheme.Motion.instant, value: configuration.isPressed)
    }
}

/// Kept so existing call sites read the same. New code should apply
/// `OddfishPrimaryButtonStyle` to a plain `Button`.
struct OddfishPrimaryButton: View {
    let title: String
    var systemImage: String = "arrow.right"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(OddfishPrimaryButtonStyle())
        .accessibilityHint("Double tap to continue")
    }
}

/// A circular icon button for screen chrome — settings, close, back.
struct OddfishIconButton: View {
    let systemImage: String
    var label: String
    var tint: Color = OddfishTheme.ivory
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(OddfishTheme.surfaceHigh, in: Circle())
                .overlay(Circle().strokeBorder(OddfishTheme.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(OddfishPressableStyle())
        .frame(width: 44, height: 44)
        .accessibilityLabel(label)
    }
}

/// One item in the game screen's bottom bar: a glyph over a short label, sized
/// so four of them share a phone's width without crowding.
struct OddfishActionBarButton: View {
    let title: String
    let systemImage: String
    var tint: Color = OddfishTheme.ivory
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 22)
                Text(title)
                    .font(.oddfishCaption.weight(.bold))
                    // Four of these share a phone's width, so each label has
                    // about a quarter of it and every title here is a single
                    // unbreakable word. Wrapping to a second line therefore
                    // could not break at a space: it hyphenated mid-word and
                    // then clipped, which is how "Options" became "Op-tio…".
                    // One line that shrinks is the same answer the catalogue
                    // tiles already give for an unbreakable name.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                    // The gutter the scale factor measures against. Without
                    // it a shrunk label fills its whole quarter of the bar
                    // and sits flush against its neighbour, which is how
                    // "Options Pause Undo Redo" read as one long word.
                    .padding(.horizontal, OddfishTheme.Spacing.hairline)
            }
            .foregroundStyle(isEnabled ? tint : OddfishTheme.faintInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(OddfishPressableStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(title)
    }
}

struct OddfishModeGlyph: View {
    let mode: GameMode
    var size: CGFloat = 46

    @Environment(\.pieceSet) private var pieceSet

    /// Each mode is represented by a real piece from the board's own set, so the
    /// glyph above the board and the pieces on it are recognisably the same
    /// drawing rather than two different interpretations.
    private var kind: PieceKind {
        switch mode {
        case .classic: .rook
        case .restfish, .tempoFish, .fadeFish, .babyFish, .pacifish,
             .pawnFish, .upstreamFish: .pawn
        case .flinchFish, .stableFish, .dwindleFish, .piranhaFish, .revengeFish: .knight
        case .rattleFish, .levelFish, .fortressFish, .shuffleFish: .rook
        case .mopeFish, .mimicFish, .chapelFish, .moodSwingFish, .contraryFish: .bishop
        case .gluttonFish, .fumbleFish, .royalFish, .comebackFish, .comboFish: .queen
        case .throneFish, .lastStandFish: .king
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(OddfishTheme.surfaceHigh)
            OddfishBoardTile(size: size * 0.70)
                .opacity(0.55)

            let metrics = PieceMetrics.metrics(for: kind, set: pieceSet)
            // "The board's own set" has to mean the drawing, not just the
            // outline: Caliente states a rook's battlements and a knight's eye
            // in contour, so a flat silhouette of it would hand five modes the
            // same featureless trapezoid.
            PieceArtworkView(
                set: pieceSet,
                kind: kind,
                color: .white,
                palette: PiecePalette(
                    body: mode.tint,
                    outline: mode.tint.mix(with: .black, by: 0.55),
                    shadowOpacity: 0
                ),
                showsFacets: false
            )
            .frame(width: size * metrics.width * 0.92, height: size * metrics.height * 0.92)

            // Each mode's one-glance signature, kept small so the piece stays
            // the subject.
            switch mode {
            case .classic:
                EmptyView()
            case .restfish, .tempoFish:
                OddfishWaveShape()
                    .stroke(OddfishTheme.seaGlass, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: size * 0.72, height: size * 0.24)
                    .offset(y: size * 0.29)
            case .flinchFish:
                Circle()
                    .stroke(OddfishTheme.coral, lineWidth: 1.4)
                    .frame(width: size * 0.20, height: size * 0.20)
                    .overlay {
                        Rectangle()
                            .fill(OddfishTheme.coral)
                            .frame(width: 1, height: size * 0.09)
                            .offset(y: -size * 0.035)
                    }
                    .offset(x: size * 0.29, y: -size * 0.26)
            default:
                Image(systemName: mode.systemImage)
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(mode.tint)
                    .padding(size * 0.08)
                    .background(OddfishTheme.surface, in: Circle())
                    .offset(x: size * 0.28, y: -size * 0.27)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The production Split O mark. Every branded surface uses this one asset,
/// exported from `Brand/OddfishMark.svg`, so launch, home, and marketing art
/// cannot silently drift into separate identities again.
struct OddfishBrandMark: View {
    var size: CGFloat = 56

    var body: some View {
        Image("OddfishMark")
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct OddfishBoardTile: View {
    let size: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { column in
                        Rectangle()
                            .fill((row + column).isMultiple(of: 2) ? OddfishTheme.ivory.opacity(0.11) : OddfishTheme.seaGlassDeep.opacity(0.24))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .rotationEffect(.degrees(-7))
    }
}




private struct OddfishWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.midY), control1: CGPoint(x: rect.width * 0.20, y: rect.minY), control2: CGPoint(x: rect.width * 0.30, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control1: CGPoint(x: rect.width * 0.70, y: rect.maxY), control2: CGPoint(x: rect.width * 0.80, y: rect.maxY))
        return path
    }
}
