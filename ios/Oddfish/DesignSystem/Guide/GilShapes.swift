import SwiftUI

// Gil's parts. Each is normalized to its own box — x 0→1 left to right, y 0→1
// top to bottom — following the same discipline as `ChessPieceShapes.swift`.
//
// `PieceOutline` is deliberately not reused: it builds mirror-symmetric lathe
// profiles, and a fish seen from the side is asymmetric. Gil gets his own
// vocabulary but keeps the same normalized-box convention.
//
// Every animatable shape exposes a SINGLE scalar `animatableData` wherever it
// can. That is what lets a pose change interpolate instead of snapping.

/// The body: a teardrop, nose to the right.
nonisolated struct GilBodyShape: Shape, Sendable {
    /// −1 slumped, +1 puffed up.
    var arch: Double = 0

    var animatableData: Double {
        get { arch }
        set { arch = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: p(0.955, 0.480))
        // Over the crown to the tail root.
        path.addCurve(to: p(0.62, 0.145 - arch * 0.05), control1: p(0.93, 0.27), control2: p(0.80, 0.155))
        path.addCurve(to: p(0.235, 0.295), control1: p(0.47, 0.135), control2: p(0.33, 0.20))
        // The flat hinge the tail pivots on.
        path.addLine(to: p(0.235, 0.735))
        // The belly control sits lower than the back control is high. A rounder
        // underside is what makes a shape read as friendly rather than fast.
        path.addCurve(to: p(0.955, 0.480), control1: p(0.40, 0.960 + arch * 0.06), control2: p(0.86, 0.800))
        path.closeSubpath()
        return path
    }
}

/// The tail, hinged at the body's flat edge.
nonisolated struct GilTailShape: Shape, Sendable {
    var sweep: Double = 0

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: p(0.235, 0.515))
        path.addLine(to: p(0.045, 0.235 + sweep * 0.05))
        // Concave inner edge, which is what makes it a crescent and not a wedge.
        path.addQuadCurve(to: p(0.045, 0.795 + sweep * 0.05), control: p(0.155 + sweep * 0.055, 0.515))
        path.closeSubpath()
        return path
    }
}

/// The dorsal fin. The cheapest whole-body emotion in the drawing: a dropped
/// dorsal reads as deflated before the face has registered at all.
nonisolated struct GilDorsalShape: Shape, Sendable {
    var raise: Double = 0.35

    var animatableData: Double {
        get { raise }
        set { raise = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: p(0.34, 0.270))
        path.addQuadCurve(to: p(0.68, 0.170), control: p(0.46, 0.130 - raise * 0.310))
        path.addLine(to: p(0.60, 0.225))
        path.closeSubpath()
        return path
    }
}

/// The pectoral fin — his hand. It waves, it gestures at the board, and it
/// tucks in when he is unhappy. Rotated rather than reshaped.
nonisolated struct GilPectoralShape: Shape, Sendable {
    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: p(0.66, 0.640))
        path.addQuadCurve(to: p(0.50, 0.850), control: p(0.535, 0.700))
        path.addQuadCurve(to: p(0.675, 0.705), control: p(0.625, 0.825))
        path.closeSubpath()
        return path
    }
}

/// One stroked brow. Two numbers here carry most of the readable emotion in the
/// whole character.
nonisolated struct GilBrowShape: Shape, Sendable {
    var arch: Double = 0

    var animatableData: Double {
        get { arch }
        set { arch = newValue }
    }

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: p(0.02, 0.62))
        path.addQuadCurve(to: p(0.98, 0.42), control: p(0.50, 0.62 - arch * 0.55))
        return path
    }
}

/// The mouth is always a closed lens, never a stroke, so there is no mode switch
/// to interpolate across. Its thickness never reaches zero, so a closed mouth
/// still reads as a line.
nonisolated struct GilMouthShape: Shape, Sendable {
    var curve: Double = 0.28
    var open: Double = 0
    var skew: Double = 0

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(curve, AnimatablePair(open, skew)) }
        set {
            curve = newValue.first
            open = newValue.second.first
            skew = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        // y grows downward, so a smile needs its control point BELOW the corners.
        // Positive `curve` must therefore ADD to y; subtracting drew a frown for
        // every happy pose.
        let upperControlY = 0.50 + curve * 0.44
        let lowerControlY = upperControlY + max(0.20, open * 1.00)

        var path = Path()
        path.move(to: p(0.02, 0.50))
        path.addQuadCurve(to: p(0.98, 0.42), control: p(0.50 + skew * 0.28, upperControlY))
        path.addQuadCurve(to: p(0.02, 0.50), control: p(0.50, lowerControlY))
        path.closeSubpath()
        return path
    }
}

/// A pilot fish's stripes, which happen to look exactly like three board files.
///
/// They are also a three-segment display: each bar's opacity is independent, so
/// a mode's rule can be shown ON the character rather than only described by
/// him — Restfish extinguishes one per resting turn.
nonisolated struct GilBars: View {
    let size: CGFloat
    /// One opacity per bar, nose-ward last.
    var levels: [Double] = [0.80, 0.92, 0.84]
    var tint: Color = OddfishTheme.Guide.bar

    var body: some View {
        ZStack {
            ForEach(Array(levels.prefix(3).enumerated()), id: \.offset) { index, level in
                let x = [0.375, 0.475, 0.575][index]
                let height = [0.46, 0.52, 0.50][index]
                RoundedRectangle(cornerRadius: size * 0.026, style: .continuous)
                    .fill(tint.opacity(level))
                    .frame(width: size * 0.052, height: size * height)
                    .rotationEffect(.degrees(-6))
                    .position(x: size * x, y: size * 0.46)
            }
        }
        .frame(width: size, height: size)
    }
}

/// One eye, built from circles rather than paths.
///
/// Both lids are circles of the eye's own diameter, filled with the body colour
/// and clipped to the eye: circle-on-circle gives a true crescent with no path
/// arithmetic, and each lid animates as a plain offset.
/// The eye at its extremes: an upward arc for joy, a downward one for a
/// squeeze. A lid-crescent is correct in the middle of the range and turns into
/// an unreadable blank disc at the ends, which is where the emotion matters most.
nonisolated struct GilArcEyeShape: Shape, Sendable {
    /// +1 arcs upward (happy), −1 downward (squeezed).
    var direction: Double = 1

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        path.move(to: p(0.04, 0.5 + 0.16 * direction))
        path.addQuadCurve(
            to: p(0.96, 0.5 + 0.16 * direction),
            control: p(0.50, 0.5 - 0.62 * direction)
        )
        return path
    }
}

nonisolated struct GilEye: View {
    let diameter: CGFloat
    let pose: GilPose
    /// Multiplied into `eyeOpen`, so a blink works independently of the pose.
    var blink: Double = 1
    /// The far eye in the three-quarter view is smaller and dimmer.
    var isFar: Bool = false

    private var openness: Double { max(0, min(1.35, pose.eyeOpen * blink)) }

    /// How far toward a happy crescent this eye is.
    private var joy: Double { max(0, min(1, (pose.squint - 0.55) / 0.30)) }
    /// How far toward being squeezed shut, ignoring blinks — a blink should
    /// close the lids, not change the drawing.
    private var squeeze: Double {
        guard joy < 0.5 else { return 0 }
        return max(0, min(1, (0.30 - pose.eyeOpen) / 0.26))
    }
    private var arcWeight: Double { max(joy, squeeze) }

    var body: some View {
        ZStack {
            lidEye.opacity(1 - arcWeight)
            GilArcEyeShape(direction: joy >= squeeze ? 1 : -1)
                .stroke(
                    OddfishTheme.Guide.ink,
                    style: StrokeStyle(lineWidth: max(1.2, diameter * 0.17), lineCap: .round)
                )
                .frame(width: diameter * 1.05, height: diameter * 0.9)
                .opacity(arcWeight * blink)
        }
        .frame(width: diameter, height: diameter)
    }

    private var lidEye: some View {
        let iris = diameter * 0.54 * pose.irisScale
        return ZStack {
            Circle()
                .fill(OddfishTheme.Guide.sclera)

            Circle()
                .fill(OddfishTheme.Guide.ink)
                .frame(width: iris, height: iris)
                .offset(x: pose.gazeX * diameter * 0.14, y: pose.gazeY * diameter * 0.12)

            Circle()
                .fill(.white.opacity(0.92))
                .frame(width: diameter * 0.17, height: diameter * 0.17)
                .offset(x: diameter * 0.13 + pose.gazeX * diameter * 0.14,
                        y: -diameter * 0.14 + pose.gazeY * diameter * 0.12)

            // Upper lid comes down; lower lid comes up. The lower one is what
            // makes a happy crescent.
            Circle()
                .fill(OddfishTheme.Guide.body)
                .offset(y: -diameter + diameter * (1 - openness))
            Circle()
                .fill(OddfishTheme.Guide.body)
                .offset(y: diameter - diameter * pose.squint)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(OddfishTheme.Guide.ink.opacity(isFar ? 0.35 : 0.55), lineWidth: max(0.5, diameter * 0.05))
        }
        .opacity(isFar ? 0.9 : 1)
    }
}
