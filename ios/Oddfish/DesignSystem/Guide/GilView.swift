import SwiftUI

/// Gil: a small gold pilot fish who swims alongside the boss and takes your side.
///
/// Pilot fish swim next to sharks and do not get eaten, because they know the
/// big fish's habits. That is the character in one image — he has been swimming
/// next to Stockfish for years, he is not impressed by it, and he will tell you
/// what he knows. It is also why he belongs in a chess app rather than being a
/// cheerleader glued on top of one.
///
/// He is drawn entirely from `Shape` geometry, like everything else in this app.
/// The boss, by contrast, is never drawn at all: Stockfish has no face, no
/// avatar and no voice, only its name in the header. All the warmth in the app
/// is Gil's, and that contrast is the point.
struct GilView: View {
    var size: CGFloat = 64
    var expression: GilExpression = .idle
    /// Overrides `expression` when the caller wants to drive the numbers itself.
    var pose: GilPose?
    /// Mirrors him to face left, for a trailing-edge perch.
    var facesLeading: Bool = false
    /// The three body bars. Their independent opacities let a mode's rule show
    /// on the character rather than only in his speech.
    var barLevels: [Double] = [0.80, 0.92, 0.84]
    var barTint: Color = OddfishTheme.Guide.bar
    /// Halved on a toolbar perch so he does not look like he is climbing out
    /// of the navigation bar.
    var motionScale: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var flowing = false
    @State private var blink: Double = 1

    private var activePose: GilPose { pose ?? expression.pose }
    private var contour: CGFloat { max(1, size * 0.022) }
    private var tailSweep: Double { flowing ? 0.55 : -0.55 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            tail
            dorsal
            bodyWithBars
            pectoral
            face
        }
        .frame(width: size, height: size * 0.80)
        .rotationEffect(.degrees(activePose.tilt))
        // Volume-preserving, non-uniform: a uniform scale reads as zooming,
        // this reads as breathing.
        .scaleEffect(
            x: breathing ? 0.982 : 1.018,
            y: breathing ? 1.018 : 0.982,
            anchor: .bottom
        )
        .offset(y: (breathing ? -size * 0.035 : size * 0.035) * motionScale)
        .scaleEffect(x: facesLeading ? -1 : 1)
        // Gold on a light board square is only about 2.4:1, so he always carries
        // his own separation from whatever is behind him.
        .shadow(color: OddfishTheme.canvas.opacity(0.5), radius: size * 0.10, y: size * 0.05)
        .animation(reduceMotion ? nil : OddfishTheme.Motion.guidePose, value: activePose)
        .onAppear(perform: startDrivers)
        .task { await blinkLoop() }
        .accessibilityHidden(true)
    }

    // MARK: - Parts

    private var tail: some View {
        GilTailShape(sweep: tailSweep)
            .fill(OddfishTheme.Guide.bodyDeep)
            .frame(width: size, height: size * 0.80)
            .animation(OddfishTheme.Motion.guideFlow(reduceMotion: reduceMotion), value: flowing)
    }

    private var dorsal: some View {
        GilDorsalShape(raise: activePose.dorsal)
            .fill(OddfishTheme.Guide.bodyDeep)
            .frame(width: size, height: size * 0.80)
    }

    private var bodyWithBars: some View {
        let shape = GilBodyShape(arch: activePose.bodyArch)
        return shape
            .fill(
                LinearGradient(
                    colors: [OddfishTheme.Guide.body, OddfishTheme.Guide.bodyDeep],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                // Clipped to the body so a bar can never spill past the outline.
                GilBars(size: size, levels: barLevels, tint: barTint)
                    .frame(width: size, height: size * 0.80)
                    .clipShape(shape)
            }
            .overlay {
                shape.stroke(OddfishTheme.Guide.ink.opacity(0.75), lineWidth: contour)
            }
            .frame(width: size, height: size * 0.80)
    }

    private var pectoral: some View {
        GilPectoralShape()
            .fill(OddfishTheme.Guide.bodyDeep)
            .overlay {
                GilPectoralShape().stroke(OddfishTheme.Guide.ink.opacity(0.5), lineWidth: contour * 0.7)
            }
            .frame(width: size, height: size * 0.80)
            .rotationEffect(.degrees(activePose.pectoral), anchor: UnitPoint(x: 0.60, y: 0.72))
    }

    /// Two eyes in a three-quarter view, not one in profile.
    ///
    /// This was the single change the design review insisted on: at toolbar size
    /// a one-eyed profile fish reads as an *icon*, while two eyes read as a
    /// *character*. Every mascot that clears the bar — Duo included — faces you.
    private var face: some View {
        let nearDiameter = size * 0.190
        let farDiameter = size * 0.116
        return ZStack(alignment: .topLeading) {
            // No brow over the far eye: at this scale the two brows sit close
            // enough to fuse into a single bar across the whole head. In a
            // three-quarter view the far brow would be largely hidden anyway.
            eye(diameter: farDiameter, centre: CGPoint(x: 0.848, y: 0.352), isFar: true)

            eye(diameter: nearDiameter, centre: CGPoint(x: 0.706, y: 0.392), isFar: false)
            brow(width: size * 0.162, centre: CGPoint(x: 0.706, y: 0.268), isFar: false)

            GilMouthShape(
                curve: activePose.mouthCurve,
                open: activePose.mouthOpen,
                skew: activePose.mouthSkew
            )
            .fill(OddfishTheme.Guide.ink)
            .frame(width: size * 0.150, height: size * 0.120)
            .position(x: size * 0.812, y: size * 0.80 * 0.638)
        }
        .frame(width: size, height: size * 0.80)
    }

    private func eye(diameter: CGFloat, centre: CGPoint, isFar: Bool) -> some View {
        GilEye(diameter: diameter, pose: activePose, blink: blink, isFar: isFar)
            .position(x: size * centre.x, y: size * 0.80 * centre.y)
    }

    private func brow(width: CGFloat, centre: CGPoint, isFar: Bool) -> some View {
        GilBrowShape(arch: activePose.browLift)
            .stroke(
                OddfishTheme.Guide.ink.opacity(isFar ? 0.6 : 0.95),
                style: StrokeStyle(lineWidth: max(1, size * 0.028), lineCap: .round)
            )
            .frame(width: width, height: size * 0.070)
            // Anchored at the tail-side end, so tilt pivots the nose-side end
            // up for worry and down for mischief.
            .rotationEffect(.degrees(activePose.browTilt * 16), anchor: .leading)
            .position(
                x: size * centre.x,
                y: size * 0.80 * centre.y - CGFloat(activePose.browLift) * size * 0.020
            )
    }

    // MARK: - Drivers

    private func startDrivers() {
        guard !reduceMotion else { return }
        withAnimation(OddfishTheme.Motion.guideIdle(reduceMotion: false)) { breathing = true }
        withAnimation(OddfishTheme.Motion.guideFlow(reduceMotion: false)) { flowing = true }
    }

    /// Blinking is the highest charm-per-line animation in the character, and it
    /// is deliberately not part of the pose: it has to keep going while he holds
    /// any expression.
    private func blinkLoop() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 2.8...6.5)))
            guard !Task.isCancelled else { return }
            await closeAndOpenLids()
            // Occasionally twice, which is what stops the rhythm reading as a timer.
            if Double.random(in: 0...1) < 0.18 {
                try? await Task.sleep(for: .milliseconds(160))
                await closeAndOpenLids()
            }
        }
    }

    private func closeAndOpenLids() async {
        withAnimation(OddfishTheme.Motion.guideBlinkClose) { blink = 0.04 }
        try? await Task.sleep(for: .milliseconds(90))
        withAnimation(OddfishTheme.Motion.guideBlinkOpen) { blink = 1.0 }
    }
}

#Preview("Gil — every expression") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(GilExpression.allCases, id: \.self) { expression in
                HStack(spacing: 20) {
                    GilView(size: 104, expression: expression)
                    GilView(size: 52, expression: expression)
                    GilView(size: 34, expression: expression)
                    Text(expression.rawValue)
                        .font(.oddfishBody)
                        .foregroundStyle(OddfishTheme.mutedInk)
                }
            }
        }
        .padding(28)
    }
    .background(OddfishTheme.canvas)
}
