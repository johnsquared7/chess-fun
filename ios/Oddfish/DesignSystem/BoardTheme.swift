import SwiftUI

/// The colours of one board, as a value.
///
/// Every board colour used to be a constant on `OddfishTheme.Board`. Midnight
/// teal is a good opinion, but it was the *only* opinion — and a chess app whose
/// board a player cannot change is unusual enough to be noticed. Themes are
/// values so a preview can render one without it being the one in play.
nonisolated struct BoardTheme: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let lightSquare: Color
    let darkSquare: Color
    /// The border drawn around the whole board.
    let frame: Color
    let whitePieceFill: Color
    let whitePieceOutline: Color
    let blackPieceFill: Color
    let blackPieceOutline: Color
    /// Quiet-move dots and selection.
    let indicator: Color
    /// Captures and check.
    let warning: Color
    /// The last-move wash. Deliberately its own token rather than a tint of
    /// `indicator`: the two are read at the same time and for different
    /// reasons — "where the opponent just went" and "where I may go" — so a
    /// board that draws them in one hue makes the player decode opacity.
    let highlight: Color
    /// Some nominally "dark" squares are mid-tone wood or green. White ink
    /// cannot reach sufficient contrast on those themes, so they deliberately
    /// use dark ink on both square colours.
    let darkSquareNeedsDarkInk: Bool

    /// The colour a coordinate label takes when it sits on a given square, so a
    /// theme cannot produce a label that disappears into its own board.
    func coordinate(onLight isLight: Bool) -> Color {
        usesDarkInk(onLight: isLight)
            ? .black.opacity(0.85)
            : .white.opacity(0.90)
    }

    /// Move markers, in ink rather than in an accent.
    ///
    /// A tinted dot has to clear two backgrounds at once, and on most boards it
    /// clears neither: sea-glass on pale blue and sea-glass on deep teal are the
    /// same value as their squares. Black on a light square and white on a dark
    /// one always separate, whatever the theme's hues are.
    func moveDot(onLight isLight: Bool) -> Color {
        usesDarkInk(onLight: isLight)
            ? .black.opacity(0.60)
            : .white.opacity(0.60)
    }

    private func usesDarkInk(onLight isLight: Bool) -> Bool {
        isLight || darkSquareNeedsDarkInk
    }
}

nonisolated extension BoardTheme {
    /// The board Oddfish shipped with, and still the default.
    static let midnight = BoardTheme(
        id: "midnight",
        title: "Midnight",
        lightSquare: Color(red: 0.792, green: 0.871, blue: 0.882),
        darkSquare: Color(red: 0.220, green: 0.400, blue: 0.478),
        frame: Color(red: 0.04, green: 0.09, blue: 0.15),
        whitePieceFill: Color(red: 0.98, green: 0.97, blue: 0.93),
        whitePieceOutline: Color(red: 0.05, green: 0.11, blue: 0.16),
        blackPieceFill: Color(red: 0.09, green: 0.16, blue: 0.22),
        blackPieceOutline: Color(red: 0.86, green: 0.93, blue: 0.95),
        indicator: OddfishTheme.seaGlass,
        warning: OddfishTheme.coral,
        highlight: Color(red: 0.98, green: 0.84, blue: 0.36),
        darkSquareNeedsDarkInk: false
    )

    /// The board almost every chess site uses. Here because a player who wants a
    /// chessboard to look like a chessboard should be able to have one.
    static let classic = BoardTheme(
        id: "classic",
        title: "Classic",
        lightSquare: Color(red: 0.94, green: 0.86, blue: 0.71),
        darkSquare: Color(red: 0.71, green: 0.53, blue: 0.39),
        frame: Color(red: 0.35, green: 0.24, blue: 0.16),
        whitePieceFill: Color(red: 0.99, green: 0.98, blue: 0.95),
        whitePieceOutline: Color(red: 0.16, green: 0.12, blue: 0.10),
        blackPieceFill: Color(red: 0.13, green: 0.11, blue: 0.10),
        blackPieceOutline: Color(red: 0.95, green: 0.92, blue: 0.87),
        indicator: Color(red: 0.36, green: 0.55, blue: 0.30),
        warning: Color(red: 0.78, green: 0.24, blue: 0.20),
        highlight: Color(red: 0.98, green: 0.82, blue: 0.24),
        darkSquareNeedsDarkInk: true
    )

    /// The green board, for players who learned on one.
    static let kelp = BoardTheme(
        id: "kelp",
        title: "Kelp",
        lightSquare: Color(red: 0.93, green: 0.93, blue: 0.83),
        darkSquare: Color(red: 0.46, green: 0.59, blue: 0.34),
        frame: Color(red: 0.22, green: 0.29, blue: 0.16),
        whitePieceFill: Color(red: 0.99, green: 0.99, blue: 0.97),
        whitePieceOutline: Color(red: 0.14, green: 0.16, blue: 0.12),
        blackPieceFill: Color(red: 0.12, green: 0.14, blue: 0.11),
        blackPieceOutline: Color(red: 0.94, green: 0.95, blue: 0.90),
        indicator: Color(red: 0.95, green: 0.77, blue: 0.24),
        warning: Color(red: 0.83, green: 0.29, blue: 0.22),
        highlight: Color(red: 0.98, green: 0.87, blue: 0.30),
        darkSquareNeedsDarkInk: true
    )

    /// Neutral greys, and the highest square contrast of the set.
    static let slate = BoardTheme(
        id: "slate",
        title: "Slate",
        lightSquare: Color(red: 0.87, green: 0.88, blue: 0.90),
        darkSquare: Color(red: 0.33, green: 0.36, blue: 0.42),
        frame: Color(red: 0.16, green: 0.18, blue: 0.21),
        whitePieceFill: Color(red: 0.99, green: 0.99, blue: 1.00),
        whitePieceOutline: Color(red: 0.13, green: 0.15, blue: 0.18),
        blackPieceFill: Color(red: 0.11, green: 0.13, blue: 0.16),
        blackPieceOutline: Color(red: 0.90, green: 0.92, blue: 0.95),
        indicator: Color(red: 0.24, green: 0.62, blue: 0.94),
        warning: Color(red: 0.90, green: 0.35, blue: 0.31),
        highlight: Color(red: 0.99, green: 0.79, blue: 0.31),
        darkSquareNeedsDarkInk: false
    )

    /// Warm and low-contrast, for reading a board in the dark.
    static let ember = BoardTheme(
        id: "ember",
        title: "Ember",
        lightSquare: Color(red: 0.62, green: 0.47, blue: 0.46),
        darkSquare: Color(red: 0.24, green: 0.16, blue: 0.19),
        frame: Color(red: 0.12, green: 0.08, blue: 0.10),
        whitePieceFill: Color(red: 0.96, green: 0.90, blue: 0.82),
        whitePieceOutline: Color(red: 0.17, green: 0.10, blue: 0.10),
        blackPieceFill: Color(red: 0.10, green: 0.07, blue: 0.09),
        blackPieceOutline: Color(red: 0.90, green: 0.72, blue: 0.60),
        indicator: Color(red: 0.98, green: 0.72, blue: 0.35),
        warning: Color(red: 0.95, green: 0.42, blue: 0.33),
        highlight: Color(red: 0.99, green: 0.66, blue: 0.38),
        darkSquareNeedsDarkInk: false
    )

    static let all: [BoardTheme] = [.midnight, .classic, .kelp, .slate, .ember]

    static func theme(id: String) -> BoardTheme {
        all.first { $0.id == id } ?? .midnight
    }
}

/// How the pieces are rendered. The silhouettes are shared — only their
/// treatment changes, so every style keeps the same shared foot line and height
/// ramp that makes the set read as one set.
/// Which silhouette family the pieces are drawn from.
///
/// This is a different axis from `PieceStyle`: a set decides *what shape* a
/// piece is, a style decides how that shape is rendered. The two compose, so
/// every set has a carved, an outline and a flat treatment.
///
/// One case ships. The axis is kept rather than collapsed because the choice is
/// persisted in `AppSettings`, because the environment threads it to every
/// piece on the board, and because adding a set is now a role declaration and a
/// generator run — see `Pieces/README.md`.
nonisolated public enum PieceSet: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// avi's Caliente, converted from the artist's own drawings.
    case caliente

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .caliente: "Caliente"
        }
    }

    /// Shown wherever the set is named, because it credits the artist as well
    /// as describing the pieces.
    public var detail: String {
        switch self {
        case .caliente:
            "avi's Caliente, drawn for readability on a small board: rounder volumes, a heavier contour, and six pieces that separate at a glance."
        }
    }

    /// Who drew the set and on what terms.
    ///
    /// This is not decoration. Caliente is CC BY-SA 4.0, which requires the
    /// artist to be credited where a player can see it — and since it is now
    /// the *only* set the app ships, that credit is load-bearing rather than
    /// courteous. Holding it on the case itself is what stops the licence
    /// screen and the set list from drifting apart.
    public var credit: PieceSetCredit? {
        switch self {
        case .caliente:
            PieceSetCredit(
                author: "avi",
                licence: "CC BY-SA 4.0",
                source: "github.com/avi-0/caliente"
            )
        }
    }

    /// A set that is no longer offered must not cost a player their history.
    ///
    /// `AppSettings` is stored as one document, and one unreadable field
    /// discards the whole of it — stats, games and all. Four sets have been
    /// retired from this enum already, so an identifier that no longer exists
    /// resolves to the one that does rather than throwing.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PieceSet(rawValue: raw) ?? .caliente
    }
}

/// The attribution one imported piece set travels with.
nonisolated public struct PieceSetCredit: Hashable, Sendable {
    public let author: String
    public let licence: String
    public let source: String
}

nonisolated public enum PieceStyle: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// Filled, outlined and shadowed. The original.
    case carved
    /// Heavier outline over a lighter fill, closer to a printed diagram.
    case outline
    /// Solid silhouettes with no outline or shadow. The most legible at very
    /// small sizes, and the fastest to read on a busy board.
    case flat

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .carved: "Carved"
        case .outline: "Outline"
        case .flat: "Flat"
        }
    }

    var outlineWidthMultiplier: CGFloat {
        switch self {
        case .carved: 1.0
        case .outline: 2.1
        case .flat: 0
        }
    }

    var castsShadow: Bool {
        switch self {
        case .carved: true
        case .outline, .flat: false
        }
    }

    /// `.outline` lightens the fill so the heavier contour reads as line art
    /// rather than as a thick border round a solid shape.
    var fillOpacity: Double {
        switch self {
        case .carved, .flat: 1.0
        case .outline: 0.82
        }
    }

    // MARK: Sets whose contour is drawn in rather than added round

    /// An imported set arrives with its own contour already inside the artwork,
    /// so a style scales that weight instead of adding one. The numbers are
    /// much gentler than `outlineWidthMultiplier` for that reason: 2.1× a
    /// contour that is already a sixteenth of a square is a band, not a line.
    var artworkOutlineMultiplier: CGFloat {
        switch self {
        case .carved: 1.0
        case .outline: 1.5
        case .flat: 0
        }
    }

    /// The modelled facets and the cast ellipse are what make an imported set
    /// look three-dimensional, which is the one thing `.outline` is trying not
    /// to look. `.flat` never reaches this: it draws the silhouette instead.
    var showsArtworkFacets: Bool {
        switch self {
        case .carved: true
        case .outline, .flat: false
        }
    }

    /// Whether a set with its own artwork is drawn as that artwork, or falls
    /// back to its plain silhouette.
    var drawsArtwork: Bool { self != .flat }
}

/// How much of the board's own chrome is drawn.
nonisolated public struct BoardDecoration: Codable, Hashable, Sendable {
    public var showsCoordinates: Bool
    public var highlightsLastMove: Bool

    public init(showsCoordinates: Bool = true, highlightsLastMove: Bool = true) {
        self.showsCoordinates = showsCoordinates
        self.highlightsLastMove = highlightsLastMove
    }

    public static let `default` = BoardDecoration()
}

// MARK: - Environment

private struct BoardThemeKey: EnvironmentKey {
    static let defaultValue = BoardTheme.midnight
}

private struct PieceStyleKey: EnvironmentKey {
    static let defaultValue = PieceStyle.carved
}

private struct PieceSetKey: EnvironmentKey {
    static let defaultValue = PieceSet.caliente
}

private struct BoardDecorationKey: EnvironmentKey {
    static let defaultValue = BoardDecoration.default
}

extension EnvironmentValues {
    /// Read by the board and by every piece, so a preview can show a theme that
    /// is not the one in play without any view taking an extra parameter.
    var boardTheme: BoardTheme {
        get { self[BoardThemeKey.self] }
        set { self[BoardThemeKey.self] = newValue }
    }

    var pieceStyle: PieceStyle {
        get { self[PieceStyleKey.self] }
        set { self[PieceStyleKey.self] = newValue }
    }

    var pieceSet: PieceSet {
        get { self[PieceSetKey.self] }
        set { self[PieceSetKey.self] = newValue }
    }

    var boardDecoration: BoardDecoration {
        get { self[BoardDecorationKey.self] }
        set { self[BoardDecorationKey.self] = newValue }
    }
}

extension View {
    func boardAppearance(
        theme: BoardTheme,
        pieceSet: PieceSet,
        pieceStyle: PieceStyle,
        decoration: BoardDecoration = .default
    ) -> some View {
        environment(\.boardTheme, theme)
            .environment(\.pieceSet, pieceSet)
            .environment(\.pieceStyle, pieceStyle)
            .environment(\.boardDecoration, decoration)
    }
}
