import SwiftUI

/// The big beats: Gil takes the whole screen.
///
/// Reserved for moments that are already a stopping point — the end of a game —
/// never for an interruption mid-play. The losing board stays visible behind the
/// scrim on purpose: it is the evidence for what he is about to say.
nonisolated struct GuideMoment: Equatable, Sendable, Identifiable {
    /// What the secondary button does. The hinge arrives after a game is over,
    /// so declining it starts a fresh board. The escape hatch and the
    /// introduction both arrive *mid-game*, where restarting would throw away
    /// the game the player just chose to keep.
    enum DeclineAction: Hashable, Sendable {
        case dismiss
        case restart
    }

    let id: String
    let headline: String
    let subline: String
    let turn: String
    /// The handicaps on offer. Empty makes this a plain message.
    let offers: [GameMode]
    let declineTitle: String
    var declineAction: DeclineAction = .restart
    /// How Gil looks on arrival, before the turn. The hinge opens on sympathy;
    /// the introduction has nothing to commiserate about yet.
    var arrivalExpression: GilExpression = .wince

    static func hinge(result: GameResult, opponentRating: Int? = nil) -> GuideMoment {
        return GuideMoment(
            id: "hinge.\(result.rawValue)",
            headline: GuideCopy.hingeHeadline(for: result, opponentRating: opponentRating),
            subline: GuideCopy.hingeSubline(for: result, opponentRating: opponentRating),
            turn: GuideCopy.hingeTurn,
            offers: GameMode.hingeOffers,
            declineTitle: GuideCopy.hingeDecline,
            declineAction: .restart
        )
    }

    /// The first thing a new player is told, and the frame for everything after
    /// it. This was a timed speech bubble, which meant it could expire before a
    /// cold launch had finished settling and the player would never see the one
    /// line the whole product is built on.
    static let introduction = GuideMoment(
        id: GuideCopy.bossIntro.id,
        headline: GuideCopy.bossIntro.text,
        subline: GuideCopy.bossIntroFollow.text,
        turn: "",
        offers: [],
        declineTitle: "Play it",
        declineAction: .dismiss,
        arrivalExpression: .sly
    )

    /// Offered when the introduction game has run long. Being stuck in a losing
    /// position you cannot see the end of is the one thing worse than losing, so
    /// this is the only unprompted line in the app that offers to end what the
    /// player is currently doing.
    static let escapeHatch = GuideMoment(
        id: "hinge.escape",
        headline: "This one's going long.",
        subline: "You've seen what it does. Pride is optional; battery life is not.",
        turn: GuideCopy.hingeTurn,
        offers: GameMode.hingeOffers,
        declineTitle: "Keep playing",
        // Mid-game. "Keep playing" restarted the board, which is the opposite
        // of what it says.
        declineAction: .dismiss,
        arrivalExpression: .sly
    )
}

struct GuideMomentView: View {
    let moment: GuideMoment
    let onChoose: (GameMode) -> Void
    let onDecline: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage = .arriving
    @AccessibilityFocusState private var isHeadlineFocused: Bool

    /// The screen is deliberately built in two acts. Sympathy lands first and is
    /// allowed to sit; the offer only appears afterwards. Offering the fix in
    /// the same breath as the commiseration makes the commiseration read as a
    /// sales technique.
    private enum Stage {
        case arriving
        case sympathising
        case offering
    }

    var body: some View {
        ZStack {
            // The losing board is meant to stay faintly visible — it is the
            // evidence for what he is about to say — but at 0.62 the pieces and
            // the controls bled through into the copy and made both unreadable.
            Color.black.opacity(0.82).ignoresSafeArea()

            ScrollView {
                VStack(spacing: OddfishTheme.Spacing.regular) {
                    GilView(
                        size: 104,
                        expression: stage == .offering ? .sly : moment.arrivalExpression
                    )
                    .padding(.top, OddfishTheme.Spacing.regular)

                    Text(moment.headline)
                        .font(.oddfishTitle)
                        .foregroundStyle(OddfishTheme.ivory)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isHeadlineFocused)
                        .accessibilityIdentifier("guide-moment-headline")

                    Text(moment.subline)
                        .font(.oddfishBody)
                        .foregroundStyle(OddfishTheme.mutedInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if stage == .offering {
                        if !moment.offers.isEmpty {
                            Text(moment.turn)
                                .font(.oddfishHeadline)
                                .foregroundStyle(OddfishTheme.Guide.body)
                                .multilineTextAlignment(.center)
                                .padding(.top, OddfishTheme.Spacing.tight)

                            VStack(spacing: OddfishTheme.Spacing.snug) {
                                ForEach(moment.offers) { mode in
                                    offerCard(mode)
                                }
                            }
                        }

                        Button(moment.declineTitle, action: onDecline)
                            .font(.oddfishControl)
                            .foregroundStyle(OddfishTheme.mutedInk)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("guide-moment-decline")
                    }
                }
                .padding(.horizontal, OddfishTheme.Spacing.regular)
                .padding(.vertical, OddfishTheme.Spacing.loose)
                // Its own ground, so no line of copy is ever read against a
                // chess piece or a button underneath it.
                .background {
                    RoundedRectangle(cornerRadius: OddfishTheme.Radius.panel, style: .continuous)
                        .fill(OddfishTheme.canvas.opacity(0.96))
                        .overlay {
                            RoundedRectangle(cornerRadius: OddfishTheme.Radius.panel, style: .continuous)
                                .stroke(OddfishTheme.Guide.body.opacity(0.28), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                }
                .padding(.horizontal, OddfishTheme.Spacing.snug)
                .padding(.vertical, OddfishTheme.Spacing.regular)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            // Let the modal enter the accessibility tree before moving focus.
            await Task.yield()
            isHeadlineFocused = true
            await runBeats()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("guide-moment")
    }

    private func offerCard(_ mode: GameMode) -> some View {
        let copy = GuideCopy.hingePitch(for: mode)
        return Button { onChoose(mode) } label: {
            HStack(alignment: .top, spacing: OddfishTheme.Spacing.snug) {
                OddfishModeGlyph(mode: mode, size: 44)
                VStack(alignment: .leading, spacing: OddfishTheme.Spacing.hairline) {
                    Text(mode.title)
                        .font(.oddfishHeadline)
                        .foregroundStyle(OddfishTheme.ivory)
                    Text(copy.pitch)
                        .font(.oddfishBody)
                        .foregroundStyle(OddfishTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    // The line that makes the promise checkable rather than
                    // rhetorical. It is why the offer is believable at all.
                    Text(copy.whatChanges)
                        .font(.oddfishCaption)
                        .foregroundStyle(OddfishTheme.seaGlass)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(OddfishTheme.Spacing.snug)
            .frame(maxWidth: .infinity, alignment: .leading)
            .oddfishSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title). \(copy.pitch) \(copy.whatChanges)")
        .accessibilityHint("Double tap to play \(mode.title)")
    }

    private func runBeats() async {
        guard !reduceMotion else {
            stage = .offering
            return
        }
        withAnimation(OddfishTheme.Motion.guideSettle) { stage = .sympathising }
        // He takes the loss too, and is allowed half a second to.
        try? await Task.sleep(for: .milliseconds(900))
        guard !Task.isCancelled else { return }
        // Sympathy becomes conspiracy. Because a pose is only a struct of
        // numbers, this whole turn is one interpolation.
        withAnimation(OddfishTheme.Motion.guidePose) { stage = .offering }
        if !moment.offers.isEmpty, !moment.turn.isEmpty {
            OddfishAccessibility.announce(moment.turn)
        }
    }
}

#Preview("Hinge") {
    GuideMomentView(moment: .hinge(result: .loss), onChoose: { _ in }, onDecline: {})
        .background(OddfishTheme.canvas)
}
