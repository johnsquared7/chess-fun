#!/usr/bin/env swift
// Converts piece-packager sprite sheets into the Swift drawing tables the app
// renders. Run from the repository root:
//
//     swift Pieces/GeneratePieceArt.swift            # every set
//     swift Pieces/GeneratePieceArt.swift staunty    # one set
//
// Everything about the output is derived, so no artwork is ever hand-copied:
// re-running against a newer sprite sheet reproduces the tables exactly.
//
// A piece-packager file is one `<svg>` holding twelve `<g id="wp">`-style
// groups, one per colour and kind, each a stack of flat `<path>` layers. The
// four sets here do not otherwise resemble each other: two are pure fills, one
// is stroked, one is written in relative commands with arcs, rounded rects,
// CSS `style` attributes and even-odd fills. So this is a real, if small, SVG
// reader — and it refuses to guess, because a converter that silently drops
// geometry produces a piece set that is subtly wrong everywhere.

import CoreGraphics
import Foundation

// MARK: - Failure

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - What each colour in a set means

/// The role a painted colour plays, declared per set and per army.
///
/// Only four roles exist, because only four things need to survive into a
/// themed app: the piece's material, its contour, the facets that model it, and
/// the shadow it casts on the square. Declaring them by hand is the point — an
/// undeclared colour stops the run, so a set cannot be half-converted.
enum Role {
    /// The piece's own material. Exactly one colour per army.
    case body
    /// The contour, whether the artist drew it as a stroke or as a filled
    /// shape behind everything else.
    case outline
    /// A lighter or darker face of the body. Its strength is *measured*
    /// against the body colour rather than declared, so the app can restate it
    /// in any theme's inks.
    case facet
    /// The ellipse under the piece, not part of the piece.
    case groundShadow
}

struct SetSpec {
    let name: String
    /// `roles["w"]["#cccccc"]` — canonical six-digit hex keys; `url` matches
    /// any gradient reference.
    let roles: [String: [String: Role]]
}

/// One spelling per colour, so `black`, `#000`, `#000000` and an inherited
/// default all reach the same declared role.
func canonical(_ colour: String) -> String {
    var value = colour.trimmingCharacters(in: .whitespaces).lowercased()
    if value.hasPrefix("url(") { return "url" }
    if value == "white" { value = "#ffffff" }
    if value == "black" { value = "#000000" }
    guard value.hasPrefix("#") else { return value }
    let digits = String(value.dropFirst())
    if digits.count == 3 { return "#" + digits.map { "\($0)\($0)" }.joined() }
    return value
}

let specs: [SetSpec] = [
    SetSpec(name: "caliente", roles: [
        "w": ["#ffffff": .body, "#cccccc": .facet, "#000000": .outline, "url": .groundShadow],
        "b": ["#595959": .body, "#8c8c8c": .facet, "#000000": .outline, "url": .groundShadow]
    ])
    // Staunty, Alfarishy and Alpha were converted here too, and the reader
    // still handles everything they needed — relative commands, arcs, rects,
    // CSS `style`, even-odd fills, inherited paint. They were removed because
    // of their licences, not their geometry. See Pieces/README.md.
]

// MARK: - Colour

struct RGB {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value == "white" { value = "#ffffff" }
        if value == "black" { value = "#000000" }
        guard value.hasPrefix("#") else { return nil }
        var digits = String(value.dropFirst())
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let packed = UInt32(digits, radix: 16) else { return nil }
        r = Double((packed >> 16) & 0xFF) / 255
        g = Double((packed >> 8) & 0xFF) / 255
        b = Double(packed & 0xFF) / 255
    }

    func blended(with other: RGB, by amount: Double) -> RGB {
        RGB(r: r + (other.r - r) * amount,
            g: g + (other.g - g) * amount,
            b: b + (other.b - b) * amount)
    }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

/// How far a facet colour sits from the body, as a signed fraction: positive
/// towards white, negative towards black.
///
/// Restating a facet this way is what lets four differently-painted sets share
/// one renderer. The artist's `#CCCCCC` on a white body and their translucent
/// white over a grey one are the same statement — *this face is a fifth of the
/// way lighter* — and the app can make that statement in any theme's colours.
func facetStrength(of colour: RGB, over body: RGB, opacity: Double) -> Double {
    let composited = body.blended(with: colour, by: opacity)
    let difference = composited.luminance - body.luminance
    guard abs(difference) > 0.001 else { return 0 }
    let headroom = difference > 0 ? (1 - body.luminance) : body.luminance
    guard headroom > 0.001 else { return difference > 0 ? 1 : -1 }
    return max(-1, min(1, difference / headroom))
}

// MARK: - Path geometry

enum Element {
    case move(CGPoint)
    case line(CGPoint)
    case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    case close
}

/// A full SVG path reader: every command, absolute and relative, with arcs
/// raised to cubics.
///
/// The first version of this handled only the six commands Caliente happened to
/// use. Staunty is written in relative commands with elliptical arcs and smooth
/// curves, so "the commands this one file uses" turned out not to be a spec.
struct PathReader {
    private var elements: [Element] = []
    private var cursor = CGPoint.zero
    private var subpathStart = CGPoint.zero
    /// The previous curve's second control point, reflected by `S` and `T`.
    private var lastCubicControl: CGPoint?
    private var lastQuadControl: CGPoint?

    /// `context` names the layer, so a malformed path says which piece of
    /// which set it came from rather than just which command it choked on.
    static func read(_ data: String, context: String) -> [Element] {
        var reader = PathReader()
        reader.context = context
        reader.run(Tokeniser(data, context: context))
        return reader.elements
    }

    private var context = ""

    /// Splits path data into commands and numbers. SVG number syntax is looser
    /// than it looks: `1-2` is two numbers, `.5.5` is two numbers, and
    /// separators are optional wherever they are unambiguous.
    struct Tokeniser {
        enum Token { case command(Character), number(Double) }
        private(set) var tokens: [Token] = []

        init(_ data: String, context: String) {
            var buffer = ""
            func flush() {
                guard !buffer.isEmpty else { return }
                guard let value = Double(buffer) else { fail("\(context): bad number \(buffer)") }
                tokens.append(.number(value))
                buffer = ""
            }
            for character in data {
                // `e` has to be tested before "is this a letter", or the
                // exponent in `1e-4` reads as a command and silently truncates
                // the number before it. There is no `e` command in SVG, so a
                // bare one is malformed and falls through to the command case.
                if character == "e" || character == "E",
                   !buffer.isEmpty, !buffer.lowercased().contains("e") {
                    buffer.append(character)
                } else if character.isLetter {
                    flush()
                    tokens.append(.command(character))
                } else if character == "-" || character == "+" {
                    // A sign starts a new number unless it is an exponent's.
                    if !buffer.isEmpty, !buffer.lowercased().hasSuffix("e") { flush() }
                    buffer.append(character)
                } else if character == "." {
                    // A second dot starts a new number: `.5.5` is two numbers.
                    if buffer.contains(".") { flush() }
                    buffer.append(character)
                } else if character.isNumber {
                    buffer.append(character)
                } else {
                    flush()
                }
            }
            flush()
        }
    }

    private mutating func run(_ tokeniser: Tokeniser) {
        var tokens = tokeniser.tokens[...]
        var command: Character = " "

        func number() -> CGFloat {
            guard case .number(let value)? = tokens.first else {
                fail("\(context): \(command) is missing a number")
            }
            tokens = tokens.dropFirst()
            return CGFloat(value)
        }
        func flag() -> Bool { number() != 0 }
        func point(_ relative: Bool) -> CGPoint {
            let x = number(), y = number()
            return relative ? CGPoint(x: cursor.x + x, y: cursor.y + y) : CGPoint(x: x, y: y)
        }
        func hasNumber() -> Bool {
            if case .number? = tokens.first { return true }
            return false
        }

        while !tokens.isEmpty {
            if case .command(let next)? = tokens.first {
                tokens = tokens.dropFirst()
                command = next
            } else if command == "M" || command == "m" {
                // Repeated pairs after a moveto are implicit linetos.
                command = command == "M" ? "L" : "l"
            } else if command == " " {
                fail("path data starts without a command")
            }

            let relative = command.isLowercase
            switch Character(command.uppercased()) {
            case "M":
                let destination = point(relative)
                cursor = destination
                subpathStart = destination
                elements.append(.move(destination))
                lastCubicControl = nil; lastQuadControl = nil
            case "L":
                let destination = point(relative)
                cursor = destination
                elements.append(.line(destination))
                lastCubicControl = nil; lastQuadControl = nil
            case "H":
                let x = number()
                cursor = CGPoint(x: relative ? cursor.x + x : x, y: cursor.y)
                elements.append(.line(cursor))
                lastCubicControl = nil; lastQuadControl = nil
            case "V":
                let y = number()
                cursor = CGPoint(x: cursor.x, y: relative ? cursor.y + y : y)
                elements.append(.line(cursor))
                lastCubicControl = nil; lastQuadControl = nil
            case "C":
                let control1 = point(relative), control2 = point(relative)
                let destination = point(relative)
                addCurve(to: destination, control1: control1, control2: control2)
            case "S":
                let control1 = lastCubicControl.map {
                    CGPoint(x: 2 * cursor.x - $0.x, y: 2 * cursor.y - $0.y)
                } ?? cursor
                let control2 = point(relative)
                let destination = point(relative)
                addCurve(to: destination, control1: control1, control2: control2)
            case "Q":
                let control = point(relative), destination = point(relative)
                addQuadCurve(to: destination, control: control)
            case "T":
                let control = lastQuadControl.map {
                    CGPoint(x: 2 * cursor.x - $0.x, y: 2 * cursor.y - $0.y)
                } ?? cursor
                addQuadCurve(to: point(relative), control: control)
            case "A":
                let radii = CGPoint(x: number(), y: number())
                let rotation = number()
                let largeArc = flag(), sweep = flag()
                let destination = point(relative)
                addArc(to: destination, radii: radii, rotation: rotation,
                       largeArc: largeArc, sweep: sweep)
            case "Z":
                elements.append(.close)
                cursor = subpathStart
                lastCubicControl = nil; lastQuadControl = nil
            default:
                fail("\(context): unsupported path command \(command)")
            }

            // A command repeats while its arguments keep coming.
            if !hasNumber(), case .command? = tokens.first {} else if !hasNumber() { break }
        }
    }

    private mutating func addCurve(to destination: CGPoint, control1: CGPoint, control2: CGPoint) {
        elements.append(.curve(to: destination, control1: control1, control2: control2))
        cursor = destination
        lastCubicControl = control2
        lastQuadControl = nil
    }

    /// Quadratics are raised to cubics so the whole pipeline — the union, the
    /// stored strings, the runtime reader — speaks one curve type.
    private mutating func addQuadCurve(to destination: CGPoint, control: CGPoint) {
        let control1 = CGPoint(x: cursor.x + 2.0 / 3 * (control.x - cursor.x),
                               y: cursor.y + 2.0 / 3 * (control.y - cursor.y))
        let control2 = CGPoint(x: destination.x + 2.0 / 3 * (control.x - destination.x),
                               y: destination.y + 2.0 / 3 * (control.y - destination.y))
        elements.append(.curve(to: destination, control1: control1, control2: control2))
        cursor = destination
        lastQuadControl = control
        lastCubicControl = control2
    }

    /// Endpoint-parameterised elliptical arc, converted to cubics through the
    /// centre parameterisation in the SVG specification's implementation notes.
    private mutating func addArc(
        to destination: CGPoint,
        radii: CGPoint,
        rotation: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        let start = cursor
        guard start != destination else { return }
        var rx = abs(radii.x), ry = abs(radii.y)
        guard rx > 0, ry > 0 else {
            elements.append(.line(destination))
            cursor = destination
            return
        }

        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (start.x - destination.x) / 2, dy2 = (start.y - destination.y) / 2
        let x1 = cosPhi * dx2 + sinPhi * dy2
        let y1 = -sinPhi * dx2 + cosPhi * dy2

        // Scale radii up if they are too small to span the chord.
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 {
            rx *= sqrt(lambda)
            ry *= sqrt(lambda)
        }

        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let factor = (largeArc == sweep ? -1 : 1) * sqrt(denominator == 0 ? 0 : numerator / denominator)
        let cx1 = factor * rx * y1 / ry
        let cy1 = -factor * ry * x1 / rx
        let centre = CGPoint(
            x: cosPhi * cx1 - sinPhi * cy1 + (start.x + destination.x) / 2,
            y: sinPhi * cx1 + cosPhi * cy1 + (start.y + destination.y) / 2
        )

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            let value = length == 0 ? 0 : max(-1, min(1, dot / length))
            return (ux * vy - uy * vx < 0 ? -1 : 1) * acos(value)
        }

        let start1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var sweepAngle = angle((x1 - cx1) / rx, (y1 - cy1) / ry,
                               (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        // One cubic per quarter turn keeps the error far below a device pixel.
        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let delta = sweepAngle / CGFloat(segments)
        let alpha = 4.0 / 3 * tan(delta / 4)

        func onArc(_ theta: CGFloat) -> (point: CGPoint, derivative: CGPoint) {
            let cosT = cos(theta), sinT = sin(theta)
            return (
                CGPoint(x: centre.x + rx * cosPhi * cosT - ry * sinPhi * sinT,
                        y: centre.y + rx * sinPhi * cosT + ry * cosPhi * sinT),
                CGPoint(x: -rx * cosPhi * sinT - ry * sinPhi * cosT,
                        y: -rx * sinPhi * sinT + ry * cosPhi * cosT)
            )
        }

        var theta = start1
        for _ in 0 ..< segments {
            let from = onArc(theta)
            let to = onArc(theta + delta)
            elements.append(.curve(
                to: to.point,
                control1: CGPoint(x: from.point.x + alpha * from.derivative.x,
                                  y: from.point.y + alpha * from.derivative.y),
                control2: CGPoint(x: to.point.x - alpha * to.derivative.x,
                                  y: to.point.y - alpha * to.derivative.y)
            ))
            theta += delta
        }
        cursor = destination
        lastCubicControl = nil
        lastQuadControl = nil
    }
}

func scaled(_ elements: [Element], by scale: CGFloat) -> [Element] {
    func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * scale, y: p.y * scale) }
    return elements.map { element in
        switch element {
        case .move(let p): .move(point(p))
        case .line(let p): .line(point(p))
        case .curve(let p, let c1, let c2): .curve(to: point(p), control1: point(c1), control2: point(c2))
        case .close: .close
        }
    }
}

func makePath(_ elements: [Element]) -> CGPath {
    let path = CGMutablePath()
    for element in elements {
        switch element {
        case .move(let point): path.move(to: point)
        case .line(let point): path.addLine(to: point)
        case .curve(let point, let control1, let control2):
            path.addCurve(to: point, control1: control1, control2: control2)
        case .close: path.closeSubpath()
        }
    }
    return path
}

// MARK: - Reading a sprite sheet

/// The painting state a child inherits from its ancestors.
struct Style {
    /// SVG's initial fill is black, not "nothing". Caliente, Alfarishy and
    /// Alpha all set `fill="none"` on their groups, so an absent fill *looks*
    /// like it paints nothing — until Staunty, which leaves the fill to
    /// default and states four of the knight's nine layers that way. Defaulting
    /// to `nil` silently dropped every one of them.
    var fill: String? = "black"
    var stroke: String? = nil
    var strokeWidth: CGFloat = 1
    var opacity: Double = 1
    var evenOdd = false
    var roundCap = false
    var miterLimit: CGFloat = 10
    var scale: CGFloat = 1

    /// Presentation attributes first, then `style`, which overrides them.
    mutating func apply(_ attributes: [String: String], elementID: String) {
        var declarations: [String: String] = [:]
        for key in ["fill", "stroke", "stroke-width", "opacity", "fill-rule",
                    "stroke-linecap", "stroke-miterlimit"] {
            if let value = attributes[key] { declarations[key] = value }
        }
        for pair in (attributes["style"] ?? "").split(separator: ";") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            declarations[parts[0].trimmingCharacters(in: .whitespaces)] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }

        if let value = declarations["fill"] { fill = value }
        if let value = declarations["stroke"] { stroke = value == "none" ? nil : value }
        if let value = declarations["stroke-width"], let width = Double(value) {
            strokeWidth = CGFloat(width)
        }
        // Opacity multiplies down the tree.
        if let value = declarations["opacity"], let alpha = Double(value) { opacity *= alpha }
        if let value = declarations["fill-rule"] { evenOdd = value == "evenodd" }
        if let value = declarations["stroke-linecap"] { roundCap = value == "round" }
        if let value = declarations["stroke-miterlimit"], let limit = Double(value) {
            miterLimit = CGFloat(limit)
        }
        if let transform = attributes["transform"] {
            scale *= Style.uniformScale(transform, of: elementID)
        }
    }

    /// Baking a transform into coordinates is only sound while it is a uniform
    /// scale; anything else would also have to be applied to stroke widths and
    /// to the arc conversion.
    static func uniformScale(_ transform: String, of id: String) -> CGFloat {
        guard !transform.isEmpty else { return 1 }
        let numbers = transform
            .components(separatedBy: CharacterSet(charactersIn: "scale(), "))
            .compactMap(Double.init)
        guard transform.hasPrefix("scale("), numbers.count == 2, numbers[0] == numbers[1] else {
            fail("\(id): unsupported transform \(transform)")
        }
        return CGFloat(numbers[0])
    }
}

struct SourceLayer {
    var elements: [Element]
    var style: Style
}

final class SpriteSheetReader: NSObject, XMLParserDelegate {
    private(set) var groups: [(id: String, layers: [SourceLayer])] = []
    private var stack: [Style] = [Style()]
    /// The id of the enclosing piece group, if any. Anything outside one is
    /// scaffolding — `<metadata>`, a wrapper `<g>` — and is ignored.
    private var pieceID: String?
    private var pieceDepth = 0
    private var depth = 0
    private var layers: [SourceLayer] = []

    func parser(
        _ parser: XMLParser,
        didStartElement element: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        depth += 1
        var style = stack.last ?? Style()
        style.apply(attributes, elementID: attributes["id"] ?? element)
        stack.append(style)

        switch element {
        case "g":
            if pieceID == nil, let id = attributes["id"], id.count == 2 {
                pieceID = id
                pieceDepth = depth
                layers = []
            }
        case "path":
            guard pieceID != nil, let data = attributes["d"] else { return }
            layers.append(SourceLayer(
                elements: PathReader.read(data, context: "\(pieceID ?? "?") layer \(layers.count + 1)"),
                style: style
            ))
        case "rect":
            guard pieceID != nil else { return }
            layers.append(SourceLayer(elements: Self.rect(attributes), style: style))
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement element: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if element == "g", let id = pieceID, depth == pieceDepth {
            groups.append((id: id, layers: layers))
            pieceID = nil
            layers = []
        }
        stack.removeLast()
        depth -= 1
    }

    /// `<rect>` with optional rounded corners, written out as a path so the
    /// rest of the pipeline only ever sees one kind of geometry.
    private static func rect(_ attributes: [String: String]) -> [Element] {
        func value(_ key: String) -> CGFloat { CGFloat(Double(attributes[key] ?? "0") ?? 0) }
        let x = value("x"), y = value("y")
        let width = value("width"), height = value("height")
        // SVG lets either radius stand in for the other.
        let declaredRX: CGFloat? = attributes["rx"].flatMap { Double($0) }.map { CGFloat($0) }
        let declaredRY: CGFloat? = attributes["ry"].flatMap { Double($0) }.map { CGFloat($0) }
        var rx: CGFloat = declaredRX ?? declaredRY ?? 0
        var ry: CGFloat = declaredRY ?? rx
        rx = min(rx, width / 2)
        ry = min(ry, height / 2)

        guard rx > 0, ry > 0 else {
            return [
                .move(CGPoint(x: x, y: y)),
                .line(CGPoint(x: x + width, y: y)),
                .line(CGPoint(x: x + width, y: y + height)),
                .line(CGPoint(x: x, y: y + height)),
                .close
            ]
        }

        // A quarter ellipse as one cubic; the error is far below a pixel at
        // the corner radii these files use.
        let k: CGFloat = 0.5522847498
        return [
            .move(CGPoint(x: x + rx, y: y)),
            .line(CGPoint(x: x + width - rx, y: y)),
            .curve(to: CGPoint(x: x + width, y: y + ry),
                   control1: CGPoint(x: x + width - rx + rx * k, y: y),
                   control2: CGPoint(x: x + width, y: y + ry - ry * k)),
            .line(CGPoint(x: x + width, y: y + height - ry)),
            .curve(to: CGPoint(x: x + width - rx, y: y + height),
                   control1: CGPoint(x: x + width, y: y + height - ry + ry * k),
                   control2: CGPoint(x: x + width - rx + rx * k, y: y + height)),
            .line(CGPoint(x: x + rx, y: y + height)),
            .curve(to: CGPoint(x: x, y: y + height - ry),
                   control1: CGPoint(x: x + rx - rx * k, y: y + height),
                   control2: CGPoint(x: x, y: y + height - ry + ry * k)),
            .line(CGPoint(x: x, y: y + ry)),
            .curve(to: CGPoint(x: x + rx, y: y),
                   control1: CGPoint(x: x, y: y + ry - ry * k),
                   control2: CGPoint(x: x + rx - rx * k, y: y)),
            .close
        ]
    }
}

// MARK: - Serialising

/// Four decimals in the 40-unit frame is a forty-thousandth of a board square:
/// far below a device pixel, and short enough to stay readable.
func format(_ value: CGFloat) -> String {
    var text = String(format: "%.4f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text == "-0" ? "0" : text
}

func format(_ value: Double) -> String { format(CGFloat(value)) }

func serialise(_ path: CGPath) -> String {
    var parts: [String] = []
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        let points = element.points
        switch element.type {
        case .moveToPoint:
            parts.append("M \(format(points[0].x)) \(format(points[0].y))")
        case .addLineToPoint:
            parts.append("L \(format(points[0].x)) \(format(points[0].y))")
        case .addQuadCurveToPoint:
            parts.append("Q \(format(points[0].x)) \(format(points[0].y)) "
                         + "\(format(points[1].x)) \(format(points[1].y))")
        case .addCurveToPoint:
            parts.append("C \(format(points[0].x)) \(format(points[0].y)) "
                         + "\(format(points[1].x)) \(format(points[1].y)) "
                         + "\(format(points[2].x)) \(format(points[2].y))")
        case .closeSubpath:
            parts.append("Z")
        @unknown default:
            fail("unknown CGPath element")
        }
    }
    return parts.joined(separator: " ")
}

// MARK: - Conversion

struct Drawing {
    var box: CGRect
    var layers: [String]
    var silhouette: String
    var carriesOwnContour: Bool
}

let letterToKind = ["p": "pawn", "r": "rook", "n": "knight", "b": "bishop", "q": "queen", "k": "king"]
let order = ["wk", "wq", "wr", "wb", "wn", "wp", "bk", "bq", "br", "bb", "bn", "bp"]

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let requested = Set(CommandLine.arguments.dropFirst())

func convert(_ spec: SetSpec) {
    let sourceURL = repositoryRoot.appendingPathComponent("Pieces/\(spec.name).svg")
    guard let data = try? Data(contentsOf: sourceURL) else {
        fail("cannot read \(sourceURL.path) — run this from the repository root")
    }

    let reader = SpriteSheetReader()
    let parser = XMLParser(data: data)
    parser.delegate = reader
    guard parser.parse() else { fail("\(spec.name).svg is not well-formed XML") }
    guard Set(reader.groups.map(\.id)) == Set(order) else {
        fail("\(spec.name).svg does not hold exactly the twelve expected piece groups")
    }

    var drawings: [String: Drawing] = [:]
    for group in reader.groups {
        let army = String(group.id.prefix(1))
        guard let roles = spec.roles[army] else { fail("\(spec.name): no roles for army \(army)") }

        func role(of colour: String, in id: String) -> Role {
            guard let declared = roles[canonical(colour)] else {
                fail("\(spec.name) \(id): colour \(colour) has no declared role")
            }
            return declared
        }

        // The body colour is what every facet is measured against.
        guard let bodyKey = roles.first(where: { $0.value == .body })?.key,
              let bodyColour = RGB(bodyKey) else {
            fail("\(spec.name) \(army): no usable body colour declared")
        }

        var layerSource: [String] = []
        var solids: [(CGPath, Bool)] = []
        var paintsContour = false
        // A layer that paints nothing at all is a converter bug, not artwork:
        // it means an inherited fill or stroke was not resolved.
        var silentLayers = 0

        for layer in group.layers {
            let elements = scaled(layer.elements, by: layer.style.scale)
            guard !elements.isEmpty else { continue }
            let paintsFill = (layer.style.fill.map { $0 != "none" }) ?? false
            if !paintsFill && layer.style.stroke == nil { silentLayers += 1 }
            let path = makePath(elements)
            let text = serialise(path)
            let fillRule = layer.style.evenOdd ? ", evenOdd: true" : ""

            if let fill = layer.style.fill, fill != "none" {
                switch role(of: fill, in: group.id) {
                case .body:
                    layerSource.append("PieceLayer(\"\(text)\", .fill(.body)\(fillRule))")
                    solids.append((path, layer.style.evenOdd))
                case .outline:
                    layerSource.append("PieceLayer(\"\(text)\", .fill(.outline)\(fillRule))")
                    solids.append((path, layer.style.evenOdd))
                    paintsContour = true
                case .facet:
                    // The layer's own opacity is folded into the measured
                    // strength, so the app paints one opaque colour instead of
                    // stacking translucency it would have to guess about.
                    guard let colour = RGB(fill) else { fail("\(spec.name): unreadable fill \(fill)") }
                    let strength = facetStrength(of: colour, over: bodyColour,
                                                 opacity: layer.style.opacity)
                    layerSource.append(
                        "PieceLayer(\"\(text)\", .fill(.facet(\(format(strength))))\(fillRule))"
                    )
                    solids.append((path, layer.style.evenOdd))
                case .groundShadow:
                    layerSource.append("PieceLayer(\"\(text)\", .fill(.groundShadow)\(fillRule))")
                }
            }

            if let stroke = layer.style.stroke {
                guard case .outline = role(of: stroke, in: group.id) else {
                    fail("\(spec.name) \(group.id): stroke \(stroke) is not the contour")
                }
                let width = layer.style.strokeWidth * layer.style.scale
                layerSource.append(
                    "PieceLayer(\"\(text)\", .stroke(.outline, width: \(format(width)), "
                    + "roundCap: \(layer.style.roundCap), "
                    + "miterLimit: \(format(layer.style.miterLimit))))"
                )
                paintsContour = true
                // A contour the artist drew as a line is part of the piece's
                // outline: Caliente states the king's cross and the rook's
                // battlements only in stroke, so a fills-only silhouette would
                // lose them entirely.
                solids.append((
                    path.copy(
                        strokingWithWidth: width,
                        lineCap: layer.style.roundCap ? .round : .butt,
                        lineJoin: .round,
                        miterLimit: layer.style.miterLimit
                    ),
                    false
                ))
            }
        }

        guard silentLayers == 0 else {
            fail("\(spec.name) \(group.id): \(silentLayers) layers paint neither fill nor stroke")
        }
        guard let first = solids.first else { fail("\(spec.name) \(group.id) paints nothing") }
        var silhouette = first.0
        for (solid, evenOdd) in solids.dropFirst() {
            silhouette = silhouette.union(solid, using: evenOdd ? .evenOdd : .winding)
        }

        drawings[group.id] = Drawing(
            box: silhouette.boundingBoxOfPath,
            layers: layerSource,
            silhouette: serialise(silhouette),
            carriesOwnContour: paintsContour
        )
    }

    // MARK: Output

    let typeName = spec.name.prefix(1).uppercased() + spec.name.dropFirst()
    var output = """
    // Generated by Pieces/GeneratePieceArt.swift from Pieces/\(spec.name).svg.
    // Do not edit by hand: re-run the generator instead.
    //
    // Provenance and licence: Pieces/README.md and COPYRIGHT.md.
    //
    // Coordinates are in the set's own 40-unit frame, which is one board square.
    // `box` is the exact bounding box of everything the drawing paints, so a
    // piece mapped from its box into its drawing rect fills that rect precisely.

    import CoreGraphics

    nonisolated enum \(typeName)PieceArt {

    """

    for id in order {
        guard let drawing = drawings[id] else { fail("\(spec.name): missing \(id)") }
        let colour = id.hasPrefix("w") ? "white" : "black"
        let kind = letterToKind[String(id.suffix(1))]!
        output += """
            static let \(colour)\(kind.prefix(1).uppercased() + kind.dropFirst()) = PieceDrawing(
                box: CGRect(x: \(format(drawing.box.minX)), y: \(format(drawing.box.minY)), \
        width: \(format(drawing.box.width)), height: \(format(drawing.box.height))),
                carriesOwnContour: \(drawing.carriesOwnContour),
                silhouette: "\(drawing.silhouette)",
                layers: [

        """
        for layer in drawing.layers {
            output += "            \(layer),\n"
        }
        output += "        ]\n    )\n\n"
    }

    output += """
        static let all: [PieceColor: [PieceKind: PieceDrawing]] = [
            .white: [
                .king: whiteKing, .queen: whiteQueen, .rook: whiteRook,
                .bishop: whiteBishop, .knight: whiteKnight, .pawn: whitePawn
            ],
            .black: [
                .king: blackKing, .queen: blackQueen, .rook: blackRook,
                .bishop: blackBishop, .knight: blackKnight, .pawn: blackPawn
            ]
        ]
    }

    """

    let outputURL = repositoryRoot
        .appendingPathComponent("ios/Oddfish/DesignSystem/PieceArt/\(typeName)PieceArt.swift")
    try? FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try? output.write(to: outputURL, atomically: true, encoding: .utf8)

    print("\(spec.name) → \(outputURL.lastPathComponent)")
    for id in order {
        let drawing = drawings[id]!
        print(String(
            format: "  %@  box %6.3f x %6.3f at (%6.3f, %6.3f)  foot %6.3f  %2d layers%@",
            id, drawing.box.width, drawing.box.height, drawing.box.minX, drawing.box.minY,
            drawing.box.maxY, drawing.layers.count,
            drawing.carriesOwnContour ? "" : "  (no contour of its own)"
        ))
    }
}

for spec in specs where requested.isEmpty || requested.contains(spec.name) {
    convert(spec)
}
