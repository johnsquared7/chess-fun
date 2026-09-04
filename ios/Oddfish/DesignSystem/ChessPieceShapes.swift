import SwiftUI

// MARK: - Metrics

/// How large each piece is drawn, as a fraction of one board square.
///
/// The whole point of these numbers is that they belong *together*. Unicode
/// chess glyphs cannot do this: each codepoint carries its own optical size and
/// baseline, so a king and a pawn set at the same point size do not share a
/// foot line or a base width. Here they do, by construction:
///
/// - every piece stands on the same foot line (`PieceMetrics.footLine`),
/// - every piece's base is close to the same width, so the back rank reads as
///   one row rather than as eight unrelated objects,
/// - the heights climb from pawn to king, which is the only size difference a
///   player should be able to perceive.
///
/// The numbers themselves are no longer chosen here. Every set the app ships is
/// artwork, and a drawing box is a fact about a drawing, so the table is
/// measured off the artwork rather than tabulated beside it — see
/// `PieceArtwork.metrics(_:kind:)`.
nonisolated struct PieceMetrics: Hashable, Sendable {
    /// Width of the piece's own drawing box, as a fraction of the square.
    let width: CGFloat
    /// Height of the piece's own drawing box, as a fraction of the square.
    let height: CGFloat

    /// Where every piece's base sits, as a fraction of the square from its top.
    /// Pieces are bottom-aligned to this line, which is what makes them look
    /// like a set standing on the same floor.
    static let footLine: CGFloat = 0.90

    static func metrics(for kind: PieceKind, set: PieceSet = .caliente) -> PieceMetrics {
        // A set with no artwork cannot happen: `PieceSet` has one case and the
        // generated table covers every kind and colour of it. The fallback
        // keeps a missing drawing from collapsing the board to nothing.
        PieceArtwork.metrics(set, kind: kind) ?? PieceMetrics(width: 0.6, height: 0.75)
    }
}

/// The outer contour of one piece: the union of every filled area and every
/// stroked line its drawing paints.
///
/// This used to build a Staunton family from Swift bezier profiles. That set is
/// gone, so the shape is now purely the artwork's own silhouette — which is
/// still what the flat style fills, what the mode glyphs tint, and what the
/// silhouette audit samples.
nonisolated struct ChessPieceShape: Shape, Hashable, Sendable {
    let kind: PieceKind
    var set: PieceSet = .caliente

    func path(in rect: CGRect) -> Path {
        PieceArtworkShape(set: set, kind: kind).path(in: rect)
    }
}

// MARK: - Rendering

/// One chess piece, drawn to fill its square consistently with every other piece.
///
/// Both armies use the *same* silhouette and the same outline weight; only the
/// inks swap. That is deliberately unlike the Unicode set this replaced, where
/// the white pieces are outline forms and the black pieces are solid forms, so
/// the two sides never looked like one set.
struct ChessPieceView: View {
    let piece: Piece
    /// The side of one board square, in points.
    let square: CGFloat
    /// Overrides the environment, for previews that show a theme other than the
    /// one currently in play.
    var themeOverride: BoardTheme?
    var setOverride: PieceSet?
    var styleOverride: PieceStyle?

    @Environment(\.boardTheme) private var environmentTheme
    @Environment(\.pieceSet) private var environmentSet
    @Environment(\.pieceStyle) private var environmentStyle

    private var theme: BoardTheme { themeOverride ?? environmentTheme }
    private var set: PieceSet { setOverride ?? environmentSet }
    private var style: PieceStyle { styleOverride ?? environmentStyle }
    private var metrics: PieceMetrics { PieceMetrics.metrics(for: piece.kind, set: set) }
    private var isWhite: Bool { piece.color == .white }

    private var fill: Color {
        (isWhite ? theme.whitePieceFill : theme.blackPieceFill).opacity(style.fillOpacity)
    }

    private var outline: Color {
        isWhite ? theme.whitePieceOutline : theme.blackPieceOutline
    }

    /// Scales with the square so the outline stays proportional rather than
    /// turning into a thick band on a small board or vanishing on a large one.
    private var lineWidth: CGFloat {
        max(0.38, square * 0.0105) * style.outlineWidthMultiplier
    }

    var body: some View {
        let width = square * metrics.width
        let height = square * metrics.height

        ZStack {
            if style.drawsArtwork {
                // Behind the artwork, and only where it is needed: the
                // printed-diagram style wants a heavier edge than the artist
                // drew, and a drawing with no contour of its own would
                // otherwise be a hole in a dark square.
                if suppliesContour, lineWidth > 0 {
                    ChessPieceShape(kind: piece.kind, set: set)
                        .stroke(outline, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
                }
                // A set that arrives already modelled draws itself: a slit or
                // an eye added on top would be a second artist's opinion over
                // the first one's.
                PieceArtworkView(
                    set: set,
                    kind: piece.kind,
                    color: piece.color,
                    palette: PiecePalette(
                        body: fill,
                        outline: outline,
                        shadowOpacity: style.castsShadow ? 0.18 : 0
                    ),
                    outlineMultiplier: style.artworkOutlineMultiplier,
                    showsFacets: style.showsArtworkFacets
                )
            } else {
                // `.flat` is defined as the plain silhouette: one solid shape,
                // no contour, no modelling.
                ChessPieceShape(kind: piece.kind, set: set).fill(fill)
            }
        }
        .frame(width: width, height: height)
        // Bottom-align every piece to the shared foot line inside its square.
        .frame(width: square, height: square, alignment: .bottom)
        .offset(y: -square * (1 - PieceMetrics.footLine))
        .shadow(
            color: .black.opacity(style.castsShadow ? 0.08 : 0),
            radius: square * 0.012,
            y: square * 0.008
        )
        .accessibilityHidden(true)
    }

    /// Whether the app adds a contrast contour behind the artwork.
    ///
    /// `.outline` is a treatment, so it always applies; otherwise the app only
    /// steps in where the artist drew no contour at all, which on a dark board
    /// is the difference between a piece and a hole.
    private var suppliesContour: Bool {
        if style == .outline { return true }
        return PieceArtwork.drawing(set, kind: piece.kind, color: piece.color)?
            .carriesOwnContour == false
    }
}

#Preview("Piece set") {
    let square: CGFloat = 56
    return VStack(spacing: 0) {
        ForEach(PieceColor.allCases, id: \.self) { color in
            HStack(spacing: 0) {
                ForEach([PieceKind.king, .queen, .rook, .bishop, .knight, .pawn], id: \.self) { kind in
                    ZStack {
                        Rectangle().fill(
                            kind.hashValue.isMultiple(of: 2)
                                ? BoardTheme.midnight.lightSquare
                                : BoardTheme.midnight.darkSquare
                        )
                        ChessPieceView(piece: Piece(color: color, kind: kind), square: square)
                    }
                    .frame(width: square, height: square)
                }
            }
        }
    }
    .padding()
    .background(OddfishTheme.canvas)
}
