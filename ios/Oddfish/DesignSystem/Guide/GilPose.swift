import Foundation

/// Gil's whole face and body, as numbers.
///
/// The central idea of the guide's drawing: there is ONE drawing, parameterised
/// by this struct, rather than one drawing per emotion. `switch state { case
/// .cheer: CheerFace() }` gives you six unrelated pictures that pop between each
/// other. A pose of `Double`s means `withAnimation { pose = .sly }` interpolates
/// brow, lids, mouth, fin and tilt together, which is what makes a mascot look
/// alive rather than like a slide deck.
///
/// Deliberately NOT `Animatable`. Fourteen fields would mean a nested
/// `AnimatablePair` pyramid. Instead each sub-shape carries a tiny
/// `animatableData` of its own one or two scalars and is fed the matching value
/// here; SwiftUI animates them independently under the same `Animation`, so they
/// still arrive together.
nonisolated struct GilPose: Equatable, Sendable {
    /// +1 raises the nose-end of the brow (worry), −1 lowers it (mischief).
    var browTilt: Double = 0
    /// 0 resting, 1 fully lifted.
    var browLift: Double = 0.10
    /// 0 shut, 1 normal, above 1 wide.
    var eyeOpen: Double = 1.0
    /// The lower lid. 0 flat, 1 a happy crescent.
    var squint: Double = 0.05
    /// Below 1 is a pinpoint pupil — the shock read.
    var irisScale: Double = 1.0
    /// −1 looks toward the board, +1 looks at the player.
    var gazeX: Double = 0
    var gazeY: Double = 0
    /// −1 frown, +1 grin.
    var mouthCurve: Double = 0.28
    var mouthOpen: Double = 0
    /// +1 pulls the smile toward the nose — a smirk.
    var mouthSkew: Double = 0
    /// −1 slumped, +1 puffed up.
    var bodyArch: Double = 0
    /// The dorsal fin. 0 flat, 1 perked. A dropped dorsal reads as deflated
    /// faster than any change to the face.
    var dorsal: Double = 0.35
    /// Pectoral fin rotation in degrees. This is his hand.
    var pectoral: Double = 0
    /// Whole-body lean, in degrees.
    var tilt: Double = 0

    static let idle = GilPose()

    /// Delivering a line. Lifted brows are how a face signals it is addressing
    /// you, and the lean toward the reader does the rest.
    static let talking = GilPose(
        browLift: 0.35,
        mouthCurve: 0.20,
        mouthOpen: 0.15,
        dorsal: 0.50,
        pectoral: 18,
        tilt: 3
    )

    /// Joy NARROWS the eyes. This is the detail most mascots get wrong: wide
    /// eyes read as fear. The upward crescent comes from the lower lid rising,
    /// not from the eye opening.
    static let cheer = GilPose(
        browTilt: -0.25,
        browLift: 1.0,
        eyeOpen: 0.35,
        squint: 0.85,
        mouthCurve: 1.0,
        mouthOpen: 0.55,
        bodyArch: 0.45,
        dorsal: 1.0,
        pectoral: 52,
        tilt: 6
    )

    /// He took the loss too. A lopsided grimace beats a symmetric frown.
    static let wince = GilPose(
        browTilt: 0.80,
        browLift: 0.20,
        eyeOpen: 0.18,
        squint: 0.50,
        mouthCurve: -0.65,
        mouthOpen: 0.18,
        mouthSkew: -0.40,
        bodyArch: -0.70,
        dorsal: 0.05,
        pectoral: -18,
        tilt: -7
    )

    /// A pinpoint iris inside a wide eye is what makes shock read instantly.
    static let surprised = GilPose(
        browLift: 1.0,
        eyeOpen: 1.25,
        squint: 0,
        irisScale: 0.72,
        mouthCurve: 0,
        mouthOpen: 0.90,
        bodyArch: 0.35,
        dorsal: 1.0,
        pectoral: 34
    )

    /// The conspiratorial one. Every other pose looks at the board; this is the
    /// only one that looks out at the player, and that is what sells it.
    static let sly = GilPose(
        browTilt: -0.70,
        browLift: 0,
        eyeOpen: 0.45,
        squint: 0.30,
        gazeX: 0.80,
        gazeY: -0.10,
        mouthCurve: 0.55,
        mouthSkew: 0.90,
        bodyArch: 0.10,
        dorsal: 0.55,
        pectoral: 26,
        tilt: 4
    )

    /// Asleep, for the pause overlay.
    static let napping = GilPose(
        browLift: 0,
        eyeOpen: 0.05,
        squint: 0.40,
        mouthCurve: 0.15,
        bodyArch: -0.25,
        dorsal: 0.10,
        tilt: -4
    )

    /// A small, cheap disapproval for a rejected tap, where a full expression
    /// change would be louder than what actually happened.
    static let doubtful = GilPose(
        browTilt: -0.20,
        browLift: -0.15,
        eyeOpen: 0.85,
        squint: 0.18,
        mouthCurve: 0.05,
        mouthSkew: -0.25,
        dorsal: 0.22
    )

    /// Points his eyes somewhere without changing what he is feeling.
    func looking(x: Double, y: Double = 0) -> GilPose {
        var pose = self
        pose.gazeX = x
        pose.gazeY = y
        return pose
    }
}

/// The named states the rest of the app refers to. Keeping the vocabulary
/// separate from the numbers means copy and director rules can name a feeling
/// without knowing any geometry.
nonisolated enum GilExpression: String, CaseIterable, Sendable {
    case idle
    case talking
    case cheer
    case wince
    case surprised
    case sly
    case napping
    case doubtful

    var pose: GilPose {
        switch self {
        case .idle: .idle
        case .talking: .talking
        case .cheer: .cheer
        case .wince: .wince
        case .surprised: .surprised
        case .sly: .sly
        case .napping: .napping
        case .doubtful: .doubtful
        }
    }
}
