import SwiftUI

struct CrownIcons: View {
    let tier: Int
    var size: CGFloat = 13
    var tint: Color = OddfishTheme.Guide.body

    var body: some View {
        HStack(spacing: max(2, size * 0.18)) {
            ForEach(0..<min(max(tier, 0), 3), id: \.self) { _ in
                Image(systemName: "crown.fill")
                    .font(.system(size: size, weight: .bold))
            }
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tier) \(tier == 1 ? "crown" : "crowns")")
    }
}

/// The three crowns a mode is worth, all three always drawn: earned ones
/// filled, the rest left as faint outlines.
///
/// `CrownIcons` draws only what has been won, which is right inside a result
/// card but wrong in a catalogue where the row is a slot every tile owns. A
/// mode with one crown and a mode with none used to render footers of different
/// widths — or no footer at all — and the eye read that as the cards being
/// misaligned. Three fixed slots make the footer identical on every tile and
/// say what is still there to win.
struct CrownTrack: View {
    let tier: Int
    var size: CGFloat = 10
    var tint: Color = OddfishTheme.Guide.body
    var capacity: Int = 3

    private var earned: Int { min(max(tier, 0), capacity) }

    var body: some View {
        HStack(spacing: max(2, size * 0.42)) {
            ForEach(0..<capacity, id: \.self) { slot in
                Image(systemName: slot < earned ? "crown.fill" : "crown")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(tint.opacity(slot < earned ? 1 : 0.22))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            earned == 0
                ? "No crowns yet, \(capacity) available"
                : "\(earned) of \(capacity) crowns"
        )
    }
}

struct PersonalBestBadge: View {
    let record: GameRecord

    var body: some View {
        if let score = record.score, let tier = record.crownTier {
            HStack(spacing: 7) {
                // The same three slots the catalogue tiles use, so crowns mean
                // one thing on this screen: filled is won, outlined is left.
                CrownTrack(tier: tier, size: 10)
                Text("BEST · \(score.formatted.uppercased())")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.35)
            }
            .foregroundStyle(OddfishTheme.Guide.body)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(OddfishTheme.Guide.body.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(OddfishTheme.Guide.body.opacity(0.28), lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Personal best, \(tier) crowns, \(score.formatted)")
        }
    }
}

struct CrownAwardSummary: View {
    let award: CrownAward
    var prominent = false

    var body: some View {
        VStack(spacing: prominent ? 7 : 3) {
            CrownIcons(tier: award.tier, size: prominent ? 22 : 13)
            Text("\(award.tier) \(award.tier == 1 ? "crown" : "crowns")")
                .font(prominent ? .oddfishHeadline : .oddfishCaption)
                .foregroundStyle(OddfishTheme.ivory)
            Text("\(award.score.metric.label) · \(award.score.formatted)")
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.Guide.body)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}
