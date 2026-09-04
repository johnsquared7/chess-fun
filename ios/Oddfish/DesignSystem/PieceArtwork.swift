import SwiftUI

// MARK: - Imported piece artwork

/// The piece artwork Oddfish renders.
///
/// Every set the app ships comes from an artist's own SVG, converted by
/// `Pieces/GeneratePieceArt.swift` — see `Pieces/README.md` for provenance and
/// the licence, and `COPYRIGHT.md` for the obligations that come with it.
///
/// Four things about the conversion are worth knowing:
///
/// 1. **Nothing is hand-copied.** The generator reads the upstream sprite sheet
///    and emits the tables in `PieceArt/`; re-running it reproduces them. What
///    is stored is the artist's own path data, in the set's own 40-unit frame,
///    where one frame is one board square.
/// 2. **The palette is the board theme's, not the artwork's.** Every fill in
///    every set collapses to four roles — see `PieceInk` — and the theme
///    supplies them. A set that carried its own greys would be the one thing on
///    the board that five board themes could not reach.
/// 3. **Facets are measured, not copied.** One artist paints a lighter face as
///    a solid `#8C8C8C`; another paints it as white at a quarter opacity. The
///    generator reduces both to the same statement — *this face is a third of
///    the way lighter than the body* — so one renderer serves all of them.
/// 4. **The silhouette is derived.** Some pieces state part of themselves only
///    in stroke: Caliente's king's cross and rook's battlements are lines, not
///    filled areas. The generator expands every stroke into the region it
///    covers and unions the whole stack.
///
/// One set ships today, but nothing here is written for one: the roles, the
/// measured facets and the derived silhouette exist because four very
/// differently-painted sets had to share a renderer.
nonisolated enum PieceArtwork {
    /// The side of one board square in the artwork's own coordinates. Every
    /// piece-packager set is authored to this frame, which is what puts a set
    /// on one floor and one size ramp before the app scales anything.
    static let frame: CGFloat = 40

    static func drawing(_ set: PieceSet, kind: PieceKind, color: PieceColor) -> PieceDrawing? {
        tables[set]?[color]?[kind]
    }

    /// The drawing box as a fraction of a square, which is exactly the piece's
    /// share of its square. Derived rather than tabulated so the app's metrics
    /// cannot drift from the artwork they describe.
    static func metrics(_ set: PieceSet, kind: PieceKind) -> PieceMetrics? {
        guard let box = drawing(set, kind: kind, color: .white)?.box else { return nil }
        return PieceMetrics(width: box.width / frame, height: box.height / frame)
    }

    private static let tables: [PieceSet: [PieceColor: [PieceKind: PieceDrawing]]] = [
        .caliente: CalientePieceArt.all
    ]

    /// Parsed once per piece rather than per frame: the board rebuilds these
    /// paths on every layout pass, and re-reading the same string thirty-two
    /// times a pass is the one thing that would make an imported set cost more
    /// than a drawn one.
    static func silhouette(_ set: PieceSet, kind: PieceKind) -> [PiecePath.Element] {
        parsedSilhouettes[Key(set: set, kind: kind, color: .white)] ?? []
    }

    static func layers(
        _ set: PieceSet,
        kind: PieceKind,
        color: PieceColor
    ) -> [(PieceLayer, [PiecePath.Element])] {
        parsedLayers[Key(set: set, kind: kind, color: color)] ?? []
    }

    private struct Key: Hashable {
        let set: PieceSet
        let kind: PieceKind
        let color: PieceColor
    }

    private static let everyKey: [Key] = tables.keys.flatMap { set in
        PieceColor.allCases.flatMap { color in
            PieceKind.allCases.map { Key(set: set, kind: $0, color: color) }
        }
    }

    private static let parsedSilhouettes: [Key: [PiecePath.Element]] = Dictionary(
        uniqueKeysWithValues: everyKey.compactMap { key in
            guard let drawing = drawing(key.set, kind: key.kind, color: key.color) else { return nil }
            return (key, PiecePath.elements(drawing.silhouette))
        }
    )

    private static let parsedLayers: [Key: [(PieceLayer, [PiecePath.Element])]] = Dictionary(
        uniqueKeysWithValues: everyKey.compactMap { key in
            guard let drawing = drawing(key.set, kind: key.kind, color: key.color) else { return nil }
            return (key, drawing.layers.map { ($0, PiecePath.elements($0.data)) })
        }
    )
}

/// What a colour in the artwork *means*, so the board theme can supply it.
///
/// Every fill in every imported set is one of four things: the piece's own
/// material, its contour, a face of the material that models it, or the shadow
/// it casts on the square. Four roles is few enough to hand to a theme and
/// enough to keep a set's three-dimensional read.
nonisolated enum PieceInk: Hashable, Sendable {
    case body
    case outline
    /// How far this face sits from the body: positive towards white, negative
    /// towards black, `1` being the whole way. Measured by the generator from
    /// the artist's own colour and opacity, so a set painted in solid greys and
    /// a set painted in translucent washes arrive here saying the same thing.
    case facet(Double)
    case groundShadow
}

nonisolated struct PieceLayer: Hashable, Sendable {
    enum Paint: Hashable, Sendable {
        case fill(PieceInk)
        case stroke(PieceInk, width: CGFloat, roundCap: Bool, miterLimit: CGFloat)
    }

    let data: String
    let paint: Paint
    /// Some artists draw a piece as one path with holes punched in it, which
    /// only reads correctly under the even-odd rule. Caliente does not, but the
    /// generator emits the flag wherever the source declares it, so a set that
    /// needs it converts without a code change.
    let evenOdd: Bool

    init(_ data: String, _ paint: Paint, evenOdd: Bool = false) {
        self.data = data
        self.paint = paint
        self.evenOdd = evenOdd
    }

    var ink: PieceInk {
        switch paint {
        case .fill(let ink): ink
        case .stroke(let ink, _, _, _): ink
        }
    }

    var isFacet: Bool {
        if case .facet = ink { return true }
        return false
    }
}

nonisolated struct PieceDrawing: Hashable, Sendable {
    /// The bounding box of everything the drawing paints, in the 40-unit frame.
    /// Because the generator measured it from stroke-expanded outlines, the
    /// artwork fills this box exactly — contour included — rather than spilling
    /// half a line weight past it.
    let box: CGRect
    /// Whether the artist drew a contour at all. Alpha's black pawn is one flat
    /// silhouette with nothing around it, so on a dark square the app has to
    /// supply the contrast edge that the artwork does not.
    let carriesOwnContour: Bool
    let silhouette: String
    let layers: [PieceLayer]

    /// The heaviest contour in the drawing, which is how much room a style that
    /// thickens the contour has to be given back.
    var widestStroke: CGFloat {
        layers.reduce(0) { widest, layer in
            if case .stroke(_, let width, _, _) = layer.paint { max(widest, width) } else { widest }
        }
    }
}

// MARK: - Path data

/// Reads the compact path strings the generator emits.
///
/// This is deliberately not an SVG reader — that lives in the generator, which
/// has already resolved transforms, relative commands, arcs, shorthands and
/// inherited styles. All that is left in a stored string is absolute
/// `M L Q C Z` with space-separated numbers, which keeps the generated tables a
/// fraction of the size of the equivalent Swift literals and keeps them out of
/// the type checker.
nonisolated enum PiecePath {
    enum Element: Hashable, Sendable {
        case move(CGPoint)
        case line(CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case close
    }

    static func elements(_ data: String) -> [Element] {
        var elements: [Element] = []
        var numbers: [CGFloat] = []
        var fields = data.split(separator: " ")[...]

        func take(_ count: Int) -> [CGFloat] {
            numbers.removeAll(keepingCapacity: true)
            for _ in 0 ..< count {
                guard let field = fields.first, let value = Double(field) else { return [] }
                numbers.append(CGFloat(value))
                fields = fields.dropFirst()
            }
            return numbers
        }

        while let command = fields.first {
            fields = fields.dropFirst()
            switch command {
            case "M":
                let values = take(2)
                guard values.count == 2 else { return elements }
                elements.append(.move(CGPoint(x: values[0], y: values[1])))
            case "L":
                let values = take(2)
                guard values.count == 2 else { return elements }
                elements.append(.line(CGPoint(x: values[0], y: values[1])))
            case "Q":
                let values = take(4)
                guard values.count == 4 else { return elements }
                elements.append(.quadCurve(
                    to: CGPoint(x: values[2], y: values[3]),
                    control: CGPoint(x: values[0], y: values[1])
                ))
            case "C":
                let values = take(6)
                guard values.count == 6 else { return elements }
                elements.append(.curve(
                    to: CGPoint(x: values[4], y: values[5]),
                    control1: CGPoint(x: values[0], y: values[1]),
                    control2: CGPoint(x: values[2], y: values[3])
                ))
            case "Z":
                elements.append(.close)
            default:
                return elements
            }
        }
        return elements
    }

    /// Maps the artwork's `box` onto `rect`, which is what makes one piece fill
    /// its drawing rect exactly.
    static func path(_ elements: [Element], from box: CGRect, into rect: CGRect) -> Path {
        let scaleX = box.width == 0 ? 0 : rect.width / box.width
        let scaleY = box.height == 0 ? 0 : rect.height / box.height

        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: rect.minX + (point.x - box.minX) * scaleX,
                y: rect.minY + (point.y - box.minY) * scaleY
            )
        }

        var path = Path()
        for element in elements {
            switch element {
            case .move(let point): path.move(to: place(point))
            case .line(let point): path.addLine(to: place(point))
            case .quadCurve(let point, let control):
                path.addQuadCurve(to: place(point), control: place(control))
            case .curve(let point, let control1, let control2):
                path.addCurve(to: place(point), control1: place(control1), control2: place(control2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// The outer contour of one imported piece: the union of every filled area and
/// every stroked line the drawing paints, computed by the generator.
nonisolated struct PieceArtworkShape: Shape, Hashable, Sendable {
    let set: PieceSet
    let kind: PieceKind

    func path(in rect: CGRect) -> Path {
        guard let box = PieceArtwork.drawing(set, kind: kind, color: .white)?.box else { return Path() }
        return PiecePath.path(PieceArtwork.silhouette(set, kind: kind), from: box, into: rect)
    }
}

// MARK: - Rendering

/// The inks one imported piece is painted in, resolved from the board theme.
nonisolated struct PiecePalette: Hashable, Sendable {
    let body: Color
    let outline: Color
    let groundShadow: Color

    init(body: Color, outline: Color, shadowOpacity: Double) {
        self.body = body
        self.outline = outline
        self.groundShadow = .black.opacity(shadowOpacity)
    }

    /// A facet is the body carried towards white or black by the amount the
    /// artist used. Restating it that way reproduces the artwork exactly when
    /// the theme's body happens to match the artist's, and stays a highlight or
    /// a shadow rather than an arbitrary colour when it does not.
    func color(for ink: PieceInk) -> Color {
        switch ink {
        case .body: body
        case .outline: outline
        case .groundShadow: groundShadow
        case .facet(let amount):
            amount == 0 ? body
                : amount > 0 ? body.mix(with: .white, by: amount)
                             : body.mix(with: .black, by: -amount)
        }
    }
}

/// One imported piece, drawn as the stack of layers the artist drew.
///
/// A `Canvas` rather than a `ZStack` of shapes: a piece runs to seventeen
/// layers, and a full board is thirty-two pieces, so a view per layer would put
/// five hundred shapes in the hierarchy for a drawing that never animates
/// internally.
struct PieceArtworkView: View {
    let set: PieceSet
    let kind: PieceKind
    let color: PieceColor
    let palette: PiecePalette
    /// Multiplies the artwork's own contour weight, for a set whose outline is
    /// drawn in rather than added around.
    var outlineMultiplier: CGFloat = 1
    /// Off for the printed-diagram style, which wants flat colour under its
    /// contour rather than modelled volume.
    var showsFacets: Bool = true

    var body: some View {
        Canvas { context, size in
            guard let drawing = PieceArtwork.drawing(set, kind: kind, color: color) else { return }
            let rect = CGRect(origin: .zero, size: size)
            // A `Canvas` clips to its own bounds, and the stored box already
            // ends where the artwork's own contour ends. Thickening that
            // contour therefore has to buy its extra width from the drawing
            // rather than from outside it, or the style picker would shave the
            // piece's edges as it heavies them.
            let bleed = max(0, outlineMultiplier - 1) * drawing.widestStroke / 2
            let box = drawing.box.insetBy(dx: -bleed, dy: -bleed)
            // The box and the rect share an aspect ratio by construction, so
            // either axis gives the same answer; the smaller one keeps a
            // contour inside the canvas if a caller ever frames the piece
            // loosely.
            let scale = min(
                box.width == 0 ? 0 : size.width / box.width,
                box.height == 0 ? 0 : size.height / box.height
            )

            for (layer, elements) in PieceArtwork.layers(set, kind: kind, color: color) {
                guard showsFacets || !(layer.isFacet || layer.ink == .groundShadow) else { continue }
                let path = PiecePath.path(elements, from: box, into: rect)

                switch layer.paint {
                case .fill(let ink):
                    context.fill(
                        path,
                        with: .color(palette.color(for: ink)),
                        style: FillStyle(eoFill: layer.evenOdd)
                    )
                case .stroke(let ink, let width, let roundCap, let miterLimit):
                    let scaled = width * scale * outlineMultiplier
                    guard scaled > 0 else { continue }
                    context.stroke(
                        path,
                        with: .color(palette.color(for: ink)),
                        style: StrokeStyle(
                            lineWidth: scaled,
                            lineCap: roundCap ? .round : .butt,
                            lineJoin: .round,
                            miterLimit: miterLimit
                        )
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Caliente") {
    let square: CGFloat = 52
    return VStack(spacing: 16) {
        ForEach(BoardTheme.all) { theme in
            VStack(spacing: 0) {
                ForEach(PieceColor.allCases, id: \.self) { color in
                    HStack(spacing: 0) {
                        ForEach([PieceKind.king, .queen, .rook, .bishop, .knight, .pawn], id: \.self) { kind in
                            ZStack {
                                Rectangle().fill(
                                    kind.hashValue.isMultiple(of: 2)
                                        ? theme.lightSquare
                                        : theme.darkSquare
                                )
                                ChessPieceView(
                                    piece: Piece(color: color, kind: kind),
                                    square: square,
                                    themeOverride: theme
                                )
                            }
                            .frame(width: square, height: square)
                        }
                    }
                }
            }
        }
    }
    .padding()
    .background(OddfishTheme.canvas)
}
