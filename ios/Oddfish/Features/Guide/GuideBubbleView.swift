import SwiftUI

/// Gil saying one thing, over the game screen.
///
/// This is an **overlay**, never a member of the game screen's stack. The board
/// is sized from the space the fixed chrome leaves it, so a view that took part
/// in that layout would shrink the board every time Gil opened his mouth. On a
/// current phone there is roughly 80pt of clearance above the board and 36pt
/// below; the bubble floats in the upper gap and is allowed to overlap the top
/// ranks rather than push anything.
struct GuideBubbleView: View {
    let utterance: GuideUtterance
    let expression: GilExpression
    var barLevels: [Double] = [0.80, 0.92, 0.84]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var gilSize: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: OddfishTheme.Spacing.tight) {
            GilView(
                size: min(gilSize, 62),
                expression: expression,
                barLevels: barLevels
            )

            Text(utterance.line.text)
                .font(.oddfishBody)
                .foregroundStyle(OddfishTheme.ivory)
                .fixedSize(horizontal: false, vertical: true)
                // Hard cap. A guide who can produce a paragraph will eventually
                // cover the board.
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, OddfishTheme.Spacing.snug)
        .padding(.vertical, OddfishTheme.Spacing.hairline + 2)
        .background {
            RoundedRectangle(cornerRadius: OddfishTheme.Radius.card, style: .continuous)
                .fill(OddfishTheme.surfaceTop)
                .overlay {
                    RoundedRectangle(cornerRadius: OddfishTheme.Radius.card, style: .continuous)
                        .strokeBorder(OddfishTheme.Guide.body.opacity(0.45), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        }
        .frame(maxWidth: 460)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    // Entrances overshoot, exits do not. A bouncy exit reads as
                    // a bug rather than as personality.
                    insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                    removal: .opacity
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gil says: \(utterance.line.text)")
        .accessibilityHint("Double tap to dismiss")
        .accessibilityAddTraits(.isButton)
        .onAppear(perform: announceUtterance)
        .onChange(of: utterance.id) { _, _ in announceUtterance() }
    }

    private func announceUtterance() {
        OddfishAccessibility.announce(
            GameAccessibilityCopy.guide(utterance.line.text),
            priority: utterance.priority >= .consequence ? .default : .low
        )
    }
}

/// Gil sitting in the navigation bar for the whole game. Tapping him dismisses
/// whatever he is saying.
struct GuidePerchButton: View {
    let expression: GilExpression
    var barLevels: [Double] = [0.80, 0.92, 0.84]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GilView(
                size: 32,
                expression: expression,
                barLevels: barLevels,
                // Halved, or he looks like he is climbing out of the nav bar.
                motionScale: 0.5
            )
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Gil, your guide")
    }
}

#Preview("Bubble") {
    VStack(spacing: 20) {
        GuideBubbleView(
            utterance: GuideUtterance(line: GuideCopy.bossIntro, priority: .moment),
            expression: .sly,
            onDismiss: {}
        )
        GuideBubbleView(
            utterance: GuideUtterance(line: GuideCopy.bigCapture, priority: .consequence),
            expression: .cheer,
            onDismiss: {}
        )
    }
    .padding()
    .background(OddfishTheme.canvas)
}
