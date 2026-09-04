import CoreGraphics
import SwiftUI
import Testing
@testable import Oddfish

/// Guards the visual grammar of the board's most important controls. These
/// tests deliberately sample at roughly phone-board resolution: differences
/// that only exist in a large vector preview do not help during play.
struct ChessPieceShapeTests {
    private let kinds: [PieceKind] = [.pawn, .rook, .knight, .bishop, .queen, .king]

    /// There used to be a strict pawn-to-king ramp here, because the Staunton
    /// table was chosen by this app and could be held to one. That set is
    /// retired, and a ramp now belongs to whichever artist drew the set:
    /// Caliente's bishop is taller than its queen, which is an authored
    /// decision and not one worth overruling by stretching someone else's
    /// drawing.
    ///
    /// What has to hold for *every* set is the part a player reads: a king is
    /// never shorter than a pawn, and no piece is so slight or so wide that a
    /// square stops looking like it holds one thing.
    @Test func everySetKeepsItsKingAboveItsPawn() {
        for set in PieceSet.allCases {
            let metrics = kinds.map { PieceMetrics.metrics(for: $0, set: set) }

            #expect(
                metrics.last!.height > metrics.first!.height,
                "\(set.title): the king does not stand taller than the pawn"
            )

            for (kind, metric) in zip(kinds, metrics) {
                #expect(
                    (0.45 ... 0.88).contains(metric.width),
                    "\(set.title) \(kind.rawValue) is too narrow or wide"
                )
                #expect(
                    (0.55 ... 0.92).contains(metric.height),
                    "\(set.title) \(kind.rawValue) is too short or tall"
                )
            }
        }
    }

    /// Both armies are the same drawing in two inks. A set whose black king
    /// stood a different height from its white one would break the row without
    /// breaking a single shape — and because the app renders one silhouette for
    /// both colours, it would also crop the odd one out.
    @Test func bothArmiesShareOneSilhouette() {
        for set in PieceSet.allCases {
            for kind in kinds {
                guard let white = PieceArtwork.drawing(set, kind: kind, color: .white),
                      let black = PieceArtwork.drawing(set, kind: kind, color: .black) else {
                    Issue.record("\(set.title) \(kind.rawValue) has no drawing")
                    continue
                }
                #expect(
                    white.box.size == black.box.size,
                    "\(set.title) \(kind.rawValue) differs in size by colour"
                )
                #expect(
                    white.box.maxY == black.box.maxY,
                    "\(set.title) \(kind.rawValue) differs in footing by colour"
                )
                #expect(!white.layers.isEmpty && !black.layers.isEmpty)
            }
        }
    }

    /// A piece whose artist drew no contour cannot be told apart from a dark
    /// square unless the app supplies one, so the flag that triggers that has to
    /// keep meaning what it says.
    ///
    /// Every drawing shipping today carries its own contour, so nothing
    /// currently takes that path — which is exactly why the flag needs a test
    /// rather than a comment. It was written for Alpha's black pawn, a flat
    /// silhouette with nothing around it, and the next set to arrive may well
    /// need it again.
    @Test func aDrawingKnowsWhetherItCarriesItsOwnContour() {
        var checked = 0
        for set in PieceSet.allCases {
            for kind in kinds {
                for color in PieceColor.allCases {
                    guard let drawing = PieceArtwork.drawing(set, kind: kind, color: color) else { continue }
                    let paintsOutline = drawing.layers.contains { $0.ink == .outline }
                    #expect(
                        drawing.carriesOwnContour == paintsOutline,
                        "\(set.title) \(color.rawValue) \(kind.rawValue) disagrees about its contour"
                    )
                    checked += 1
                }
            }
        }
        #expect(checked == PieceSet.allCases.count * kinds.count * PieceColor.allCases.count)
    }

    @Test func silhouettesStayInsideTheirDrawingRect() {
        let drawingRect = CGRect(x: 0, y: 0, width: 100, height: 100)

        for set in PieceSet.allCases {
            for kind in kinds {
                let bounds = ChessPieceShape(kind: kind, set: set).path(in: drawingRect).boundingRect
                #expect(!bounds.isEmpty, "\(set.title) \(kind.rawValue) has no visible silhouette")
                #expect(drawingRect.insetBy(dx: -0.01, dy: -0.01).contains(bounds))
                #expect(
                    bounds.height > drawingRect.height * 0.95,
                    "\(set.title) \(kind.rawValue) lost its full-height signature"
                )
                #expect(
                    bounds.width > drawingRect.width * 0.70,
                    "\(set.title) \(kind.rawValue) became too visually slight"
                )
            }
        }
    }

    @Test func everyPieceRemainsDistinctAtPhoneBoardScale() {
        #expect(Set(kinds) == Set(PieceKind.allCases), "Add every new piece kind to the silhouette audit")
        // The supplied king and queen deliberately share their lower plinth
        // and tapered body; their identifying difference is concentrated in
        // the crown. Twenty samples keeps that exact family resemblance while
        // still catching a lost crown, cross, mitre, horse head, or battlement.
        let minimumDifferentSamples = 20
        for set in PieceSet.allCases {
            let silhouettes = Dictionary(uniqueKeysWithValues: kinds.map {
                ($0, sampledSilhouette(for: $0, set: set, columns: 24, rows: 24))
            })

            for firstIndex in kinds.indices {
                for secondIndex in kinds.indices where secondIndex > firstIndex {
                    let first = kinds[firstIndex]
                    let second = kinds[secondIndex]
                    let difference = zip(silhouettes[first]!, silhouettes[second]!)
                        .reduce(into: 0) { count, pixels in
                            if pixels.0 != pixels.1 { count += 1 }
                        }

                    #expect(
                        difference >= minimumDifferentSamples,
                        "\(set.title): \(first.rawValue) and \(second.rawValue) differ in only \(difference) of 576 samples"
                    )
                }
            }
        }
    }

    /// The silhouette is a union of the artwork's fills *and* its stroked
    /// lines, because Caliente draws the king's cross and the rook's
    /// battlements only in stroke. A silhouette rebuilt from fills alone would
    /// lose both and still pass every other test in this file, so this measures
    /// the two pieces where the strokes actually change the outline.
    @Test func theSilhouetteKeepsWhatTheArtistDrewOnlyInStroke() {
        for set in PieceSet.allCases {
            for kind in [PieceKind.king, .rook] {
                guard let drawing = PieceArtwork.drawing(set, kind: kind, color: .white) else {
                    Issue.record("\(set.title) \(kind.rawValue) has no drawing")
                    continue
                }
                let strokeOnly = drawing.layers.contains {
                    if case .stroke = $0.paint { return true }
                    return false
                }
                #expect(strokeOnly, "\(set.title) \(kind.rawValue) no longer states anything in stroke")

                // Every filled layer's own extent, unioned by bounding box.
                var filled = CGRect.null
                for layer in drawing.layers where !layer.isFacet && layer.ink != .groundShadow {
                    guard case .fill = layer.paint else { continue }
                    let box = PiecePath.path(
                        PiecePath.elements(layer.data),
                        from: drawing.box,
                        into: drawing.box
                    ).boundingRect
                    filled = filled.union(box)
                }
                #expect(
                    drawing.box.height > filled.height + 0.5,
                    "\(set.title) \(kind.rawValue): the silhouette is no taller than its fills, so the stroked contour is no longer part of it"
                )
            }
        }
    }

    /// Every set stands its pieces on one foot line, which is what makes a back
    /// rank read as one army rather than as eight unrelated objects. A set that
    /// floated above the floor, or stood on a different one, would break the
    /// row without breaking a single shape.
    @Test func everySetStandsOnTheSameFloor() {
        for set in PieceSet.allCases {
            let feet = kinds.map { kind -> CGFloat in
                let metrics = PieceMetrics.metrics(for: kind, set: set)
                let rect = CGRect(
                    x: 0,
                    y: 100 * PieceMetrics.footLine - 100 * metrics.height,
                    width: 100 * metrics.width,
                    height: 100 * metrics.height
                )
                return ChessPieceShape(kind: kind, set: set).path(in: rect).boundingRect.maxY
            }
            for foot in feet {
                #expect(
                    abs(foot - 100 * PieceMetrics.footLine) < 0.5,
                    "\(set.title) does not stand on the shared foot line"
                )
            }
        }
    }

    private func sampledSilhouette(
        for kind: PieceKind,
        set: PieceSet = .caliente,
        columns: Int,
        rows: Int
    ) -> [Bool] {
        let squareWidth = CGFloat(columns)
        let squareHeight = CGFloat(rows)
        let metrics = PieceMetrics.metrics(for: kind, set: set)
        let pieceWidth = squareWidth * metrics.width
        let pieceHeight = squareHeight * metrics.height
        let drawingRect = CGRect(
            x: (squareWidth - pieceWidth) / 2,
            y: squareHeight * PieceMetrics.footLine - pieceHeight,
            width: pieceWidth,
            height: pieceHeight
        )
        let path = ChessPieceShape(kind: kind, set: set).path(in: drawingRect).cgPath

        return (0 ..< rows).flatMap { row in
            (0 ..< columns).map { column in
                path.contains(
                    CGPoint(x: CGFloat(column) + 0.5, y: CGFloat(row) + 0.5),
                    using: .winding,
                    transform: .identity
                )
            }
        }
    }
}
