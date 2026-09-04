import Foundation

/// A continuous, live opponent rating shared by settings, sessions, and opponents.
///
/// Oddfish deliberately exposes the entire product range. Stockfish's measured
/// limiter only covers 1320...3190, so the engine mapping below also records
/// which parts of the dial are uncalibrated.
nonisolated public struct OpponentRating: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    public static let minimum = OpponentRating(unchecked: 0)
    public static let maximum = OpponentRating(unchecked: 3_600)
    public static let lowestCalibrated = OpponentRating(unchecked: 1_320)
    public static let highestCalibrated = OpponentRating(unchecked: 3_190)
    /// New games begin with Stockfish unrestricted unless a mode's mechanic
    /// deliberately defines another starting point.
    public static let `default` = OpponentRating.maximum

    public let rawValue: Int

    /// Public construction is always safe: values clamp to the product range
    /// instead of overflowing or wrapping around it.
    public init(rawValue: Int) {
        self.rawValue = min(max(rawValue, Self.minimum.rawValue), Self.maximum.rawValue)
    }

    public init(_ value: Int) {
        self.init(rawValue: value)
    }

    private init(unchecked value: Int) {
        rawValue = value
    }

    public static func < (lhs: OpponentRating, rhs: OpponentRating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public func adjusted(by delta: Int) -> OpponentRating {
        let result = rawValue.addingReportingOverflow(delta)
        if result.overflow {
            return delta >= 0 ? .maximum : .minimum
        }
        return OpponentRating(result.partialValue)
    }

    func clamped(to bounds: ClosedRange<OpponentRating>) -> OpponentRating {
        min(max(self, bounds.lowerBound), bounds.upperBound)
    }

    /// The three explicit Stockfish bands used by the structured bridge.
    var engineBand: OpponentEngineBand {
        if self < Self.lowestCalibrated {
            // Skill 0 is Stockfish 18's weakest supported playing style. Ratings
            // below 1320 are differentiated further by their shorter move time;
            // assigning a higher skill here would create a strength cliff at 1320.
            return .skillLevel(0)
        }
        if self <= Self.highestCalibrated {
            return .calibratedElo(rawValue)
        }
        return .fullStrength
    }

    /// The share of moves replaced by an ordinary legal move picked at random.
    ///
    /// Skill Level 0 is the weakest setting Stockfish has, and it still plays at
    /// roughly `lowestCalibrated`. Everything below that would otherwise be the
    /// same opponent with a shorter clock, which makes GluttonFish's "starving"
    /// opening and BabyFish's "total beginner" opening indistinguishable from a
    /// club player. Randomising a share of its moves is what actually makes the
    /// bottom of the dial weak.
    var uncalibratedRandomness: Double {
        guard self < Self.lowestCalibrated else { return 0 }
        let shortfall = Double(Self.lowestCalibrated.rawValue - rawValue)
        let span = Double(Self.lowestCalibrated.rawValue - Self.minimum.rawValue)
        return min(0.85, (shortfall / span) * 0.85)
    }

    /// Think time is part of the product dial outside Stockfish's calibrated
    /// range, and keeps the three familiar preset timings unchanged.
    var thinkingTime: Duration {
        let milliseconds: Int
        switch rawValue {
        case ...Self.lowestCalibrated.rawValue:
            milliseconds = interpolate(
                value: rawValue,
                input: Self.minimum.rawValue...Self.lowestCalibrated.rawValue,
                output: 50...200
            )
        case ...OpponentPreset.balanced.rating.rawValue:
            milliseconds = interpolate(
                value: rawValue,
                input: Self.lowestCalibrated.rawValue...OpponentPreset.balanced.rating.rawValue,
                output: 200...500
            )
        case ...Self.highestCalibrated.rawValue:
            milliseconds = interpolate(
                value: rawValue,
                input: OpponentPreset.balanced.rating.rawValue...Self.highestCalibrated.rawValue,
                output: 500...1_000
            )
        default:
            milliseconds = interpolate(
                value: rawValue,
                input: Self.highestCalibrated.rawValue...Self.maximum.rawValue,
                output: 1_000...2_000
            )
        }
        return .milliseconds(milliseconds)
    }

    private func interpolate(value: Int, input: ClosedRange<Int>, output: ClosedRange<Int>) -> Int {
        guard input.lowerBound != input.upperBound else { return output.upperBound }
        let progress = Double(value - input.lowerBound) / Double(input.upperBound - input.lowerBound)
        return output.lowerBound + Int((Double(output.upperBound - output.lowerBound) * progress).rounded())
    }
}

/// How a continuous rating is represented by Stockfish itself.
nonisolated enum OpponentEngineBand: Hashable, Sendable {
    case skillLevel(Int)
    case calibratedElo(Int)
    case fullStrength
}

/// Human-friendly shortcuts on top of the continuous dial.
nonisolated public enum OpponentPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case gentle
    case balanced
    case sharp

    public var title: String {
        switch self {
        case .gentle: "Gentle"
        case .balanced: "Balanced"
        case .sharp: "Sharp"
        }
    }

    public var rating: OpponentRating {
        switch self {
        case .gentle: .lowestCalibrated
        case .balanced: OpponentRating(2_200)
        case .sharp: .highestCalibrated
        }
    }

}
