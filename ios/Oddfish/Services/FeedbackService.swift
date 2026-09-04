import AVFoundation
import Foundation
import UIKit

public enum FeedbackEvent: Hashable, Sendable {
    case selection
    case move
    case capture
    case invalid
    case check
    case win
    case loss
}

/// Coordinates native feedback after a committed state change.
@MainActor
public protocol FeedbackService: AnyObject {
    func play(_ event: FeedbackEvent, settings: AppSettings)
}

public extension FeedbackService {
    func play(_ event: FeedbackEvent) {
        play(event, settings: .default)
    }
}

/// A no-op implementation useful for previews and deterministic tests.
@MainActor
public final class NullFeedbackService: FeedbackService {
    public init() {}
    public func play(_ event: FeedbackEvent, settings: AppSettings) {}
}

/// Generates short, original tones in memory and uses UIKit's native haptics.
/// Audio setup is lazy and every hardware operation is best-effort so this is
/// safe in Simulator, with audio unavailable, or while an interruption is active.
@MainActor
public final class SystemFeedbackService: FeedbackService {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioUnavailable = false

    public init() {}

    public func play(_ event: FeedbackEvent, settings: AppSettings) {
        if settings.soundEnabled {
            playTone(for: event)
        }
        if settings.hapticsEnabled {
            playHaptic(for: event)
        }
    }

    public func play(_ event: FeedbackEvent) {
        play(event, settings: .default)
    }

    private func playHaptic(for event: FeedbackEvent) {
        switch event {
        case .selection:
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        case .move:
            impact(.light)
        case .capture:
            impact(.medium)
        case .invalid:
            notification(.error)
        case .check:
            notification(.warning)
        case .win:
            notification(.success)
        case .loss:
            notification(.error)
        }
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    private func playTone(for event: FeedbackEvent) {
        guard !audioUnavailable else { return }
        guard let node = ensureAudioNode() else {
            audioUnavailable = true
            return
        }

        let tone = Tone(for: event)
        let outputFormat = node.outputFormat(forBus: 0)
        let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100.0
        let frameCount = AVAudioFrameCount(max(1, Int(sampleRate * tone.duration)))
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: max(1, outputFormat.channelCount)
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
        let channels = buffer.floatChannelData else { return }

        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let progress = Double(frame) / sampleRate
            let envelope = envelopeValue(at: progress, duration: tone.duration)
            let sample = Float(sin(2.0 * .pi * tone.frequency * progress) * tone.amplitude * envelope)
            for channel in 0..<Int(format.channelCount) {
                channels[channel][frame] = sample
            }
        }
        node.scheduleBuffer(buffer, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    private func ensureAudioNode() -> AVAudioPlayerNode? {
        if let playerNode { return playerNode }

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: [.notifyOthersOnDeactivation])
            try engine.start()
        } catch {
            return nil
        }
        audioEngine = engine
        playerNode = node
        return node
    }

    private func envelopeValue(at time: Double, duration: Double) -> Double {
        let attack = min(0.008, duration * 0.2)
        let release = min(0.06, duration * 0.35)
        if time < attack { return time / max(attack, 0.001) }
        if time > duration - release { return max(0, (duration - time) / max(release, 0.001)) }
        return 1
    }

    private struct Tone {
        let frequency: Double
        let duration: Double
        let amplitude: Double

        init(for event: FeedbackEvent) {
            switch event {
            case .selection: frequency = 660; duration = 0.035; amplitude = 0.08
            case .move: frequency = 440; duration = 0.07; amplitude = 0.11
            case .capture: frequency = 185; duration = 0.105; amplitude = 0.13
            case .invalid: frequency = 120; duration = 0.08; amplitude = 0.1
            case .check: frequency = 760; duration = 0.13; amplitude = 0.1
            case .win: frequency = 523.25; duration = 0.24; amplitude = 0.11
            case .loss: frequency = 196; duration = 0.22; amplitude = 0.1
            }
        }
    }
}
