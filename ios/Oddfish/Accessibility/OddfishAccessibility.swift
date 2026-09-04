import Accessibility
import UIKit

/// Short, state-based VoiceOver copy for the live game.
///
/// These strings are kept outside the views so a move is described from the
/// event that actually happened, not reconstructed from whatever the board
/// happens to look like by the time SwiftUI renders it.
nonisolated enum GameAccessibilityCopy {
    static func move(
        _ event: MoveEvent,
        opponentName: String,
        isBonusMove: Bool
    ) -> String? {
        // VoiceOver already speaks the square the player activated. Repeating
        // every ordinary player move is noisy; only announce the state changes
        // they cannot discover from the control they just used.
        if event.isPlayerMove {
            var updates: [String] = []
            if event.givesCheck { updates.append("Check.") }
            if isBonusMove { updates.append("Bonus move. You move again.") }
            return updates.isEmpty ? nil : updates.joined(separator: " ")
        }

        let moveDescription: String
        if event.move.flags.contains(.castleKingside) {
            moveDescription = "castled kingside"
        } else if event.move.flags.contains(.castleQueenside) {
            moveDescription = "castled queenside"
        } else {
            var detail = "moved \(event.pieceKind.rawValue) from \(spoken(event.move.from)) to \(spoken(event.move.to))"
            if let captured = event.capturedKind {
                detail += ", capturing your \(captured.rawValue)"
            }
            if let promotion = event.move.promotion {
                detail += ", promoting to \(promotion.rawValue)"
            }
            moveDescription = detail
        }

        let turnUpdate = event.givesCheck ? "Your king is in check." : "Your move."
        return "\(opponentName) \(moveDescription). \(turnUpdate)"
    }

    static func guide(_ line: String) -> String {
        "Gil says, \(line)"
    }

    private static func spoken(_ square: Square) -> String {
        // A small pause between file and rank is more reliable than asking
        // every installed VoiceOver voice to pronounce a chess coordinate.
        let file = Array("abcdefgh")[square.file]
        return "\(file) \(square.rank + 1)"
    }
}

/// One boundary for transient accessibility speech.
///
/// Low-priority announcements queue behind the square or button VoiceOver is
/// already speaking. That preserves the player's context and prevents a fast
/// engine response or a Gil reaction from cutting off their last action.
@MainActor
enum OddfishAccessibility {
    enum Priority {
        case low
        case `default`
        case high
    }

    private static var lastAnnouncement: (text: String, at: ContinuousClock.Instant)?

    static var isVoiceOverRunning: Bool { UIAccessibility.isVoiceOverRunning }

    static func announce(_ text: String, priority: Priority = .low) {
        guard isVoiceOverRunning, !text.isEmpty else { return }

        let now = ContinuousClock.now
        if let lastAnnouncement,
           lastAnnouncement.text == text,
           now - lastAnnouncement.at < .seconds(1) {
            return
        }
        lastAnnouncement = (text, now)

        var announcement = AttributedString(text)
        switch priority {
        case .low:
            announcement.accessibilitySpeechAnnouncementPriority = .low
        case .default:
            announcement.accessibilitySpeechAnnouncementPriority = .default
        case .high:
            announcement.accessibilitySpeechAnnouncementPriority = .high
        }
        AccessibilityNotification.Announcement(announcement).post()
    }
}
