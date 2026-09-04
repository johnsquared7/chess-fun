import SwiftUI

/// The home screen for a returning player. A first launch never sees it — the
/// introduction goes straight into a game.
///
/// Two rebuilds have happened here. The first replaced a hand-positioned
/// nautical chart that only survived one text size. The second — this one —
/// replaced six accordions with a pinned primary action, a record strip, and
/// horizontally scrolling category rows.
///
/// The accordions were the problem worth naming: eighteen modes behind six
/// closed doors meant the screen's answer to "what can I play" was "open
/// something and find out". Rows show every category at once, cost one swipe
/// each to read, and put the modes at a size where the glyph does the
/// identifying. The one action almost everybody wants is no longer somewhere in
/// the scroll — it is pinned to the bottom where a thumb already is.
struct HomeView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AppStateStore.self) private var appState
    @Environment(PurchaseManager.self) private var purchases

    @ScaledMetric(relativeTo: .body) private var scaledModeTileWidth: CGFloat = 146
    @ScaledMetric(relativeTo: .caption2) private var scaledCrownTrackSize: CGFloat = 9

    let onSelectMode: (GameMode) -> Void
    let onSettings: () -> Void
    let onHistory: () -> Void
    let onQuickPlay: () -> Void

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }
    private var edge: CGFloat {
        isRegularWidth ? OddfishTheme.Spacing.screenEdgeRegular : OddfishTheme.Spacing.screenEdge
    }
    private var modeTileWidth: CGFloat { min(scaledModeTileWidth, 224) }
    private var crownTrackSize: CGFloat { min(scaledCrownTrackSize, 16) }

    /// Classic is reachable from the pinned button and does not need a row of
    /// its own. Restfish now lives with the other rules that constrain moves.
    private let catalogueCategories: [GameModeCategory] = [
        .weakening, .growing, .chance, .constraints, .armies
    ]

    /// Modes announced but not yet playable. Static copy only — deliberately
    /// not `GameMode` cases, so they cannot be selected, persisted, or drawn
    /// into stats, crowns, history, or the paywall until their rules land.
    private let upcomingModes: [UpcomingMode] = [
        UpcomingMode(
            id: "baitfish",
            titleLead: "Bait",
            titleFamily: "Fish",
            tagline: "Punish its appetite",
            ruleSummary: "Stockfish loses 150 Elo every time it captures.",
            systemImage: "fish.fill"
        ),
        UpcomingMode(
            id: "grudgefish",
            titleLead: "Grudge",
            titleFamily: "Fish",
            tagline: "Miss, and it remembers",
            ruleSummary: "Stockfish loses 100 Elo every time you miss a best move.",
            systemImage: "flag.fill"
        ),
        UpcomingMode(
            id: "reeffish",
            titleLead: "Reef",
            titleFamily: "Fish",
            tagline: "Hold the middle",
            ruleSummary: "Stockfish loses 50 Elo when you occupy e4, d4, e5 or d5.",
            systemImage: "square.grid.3x3.fill"
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: OddfishTheme.Spacing.loose) {
                    header
                    guideRow
                    recordStrip
                    catalogueSection
                    comingSoonSection
                }
                .padding(.horizontal, edge)
                .padding(.top, OddfishTheme.Spacing.tight)
                .padding(.bottom, OddfishTheme.Spacing.tight)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            playBar
        }
        // Keeping the action as a real sibling gives the catalogue a clipped
        // viewport. Readable text can never sit underneath the bar's fade.
        // The screen draws its own header instead of a navigation bar, so it
        // also has to own the strip behind the status bar. Without this, a mode
        // tile scrolls up under the clock and the two overlap.
        .overlay(alignment: .top) { statusBarScrim }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        // A solid ground gives every catalogue label one measurable contrast
        // pair; the prior near-black gradient was visually subtle but made
        // automated contrast sampling treat otherwise identical subtitles as
        // text over an indeterminate background.
        .oddfishScreenBackground()
    }

    // MARK: - Sections

    private var statusBarScrim: some View {
        LinearGradient(
            colors: [OddfishTheme.canvas, OddfishTheme.canvas, OddfishTheme.canvas.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 14)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: OddfishTheme.Spacing.tight) {
                ViewThatFits(in: .horizontal) {
                    brandTitle(includesMark: true)
                    brandTitle(includesMark: false)
                }
                HStack(spacing: OddfishTheme.Spacing.tight) {
                    Spacer(minLength: 0)
                    headerActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: OddfishTheme.Spacing.snug) {
                brandTitle(includesMark: true)
                Spacer(minLength: OddfishTheme.Spacing.tight)
                headerActions
            }
        }
    }

    private func brandTitle(includesMark: Bool) -> some View {
        HStack(alignment: .center, spacing: OddfishTheme.Spacing.snug) {
            if includesMark {
                OddfishBrandMark(size: 46)
            }

            Text("ODDFISH")
                .font(.oddfishWordmark)
                .tracking(1.4)
                .foregroundStyle(OddfishTheme.ivory)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var headerActions: some View {
        HStack(spacing: OddfishTheme.Spacing.tight) {
            OddfishIconButton(systemImage: "clock.arrow.circlepath", label: "Game history", action: onHistory)
                .accessibilityIdentifier("home-history")
            OddfishIconButton(systemImage: "gearshape.fill", label: "Settings", action: onSettings)
        }
    }

    /// Gil's resting presence, drawn as something he is saying rather than as a
    /// row he occupies. Not a button: the home screen is not somewhere he needs
    /// to interrupt, he just happens to be here.
    private var guideRow: some View {
        HStack(alignment: .top, spacing: 10) {
            GilView(size: 48, expression: .idle)
            Text(GuideCopy.homeGreeting(gamesPlayed: appState.stats.gamesPlayed))
                .font(.oddfishBody)
                .foregroundStyle(OddfishTheme.ivory)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OddfishTheme.surface, in: SpeechBubble())
                .padding(.top, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gil says: \(GuideCopy.homeGreeting(gamesPlayed: appState.stats.gamesPlayed))")
    }

    /// Three figures, evenly weighted. A record is the one thing a returning
    /// player checks before they decide what to play, and it takes a line.
    private var recordStrip: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: OddfishTheme.Spacing.tight) {
                    statTile(value: "\(appState.stats.gamesPlayed)", label: "Played", tint: OddfishTheme.ivory)
                    statTile(value: "\(appState.stats.wins)", label: "Won", tint: OddfishTheme.seaGlass)
                    statTile(value: crownTotalText, label: "Crowns", tint: OddfishTheme.gold)
                }
            } else {
                HStack(spacing: OddfishTheme.Spacing.tight) {
                    statTile(value: "\(appState.stats.gamesPlayed)", label: "Played", tint: OddfishTheme.ivory)
                    statTile(value: "\(appState.stats.wins)", label: "Won", tint: OddfishTheme.seaGlass)
                    statTile(value: crownTotalText, label: "Crowns", tint: OddfishTheme.gold)
                }
            }
        }
        .accessibilityIdentifier("home-record-strip")
    }

    private var crownTotalText: String {
        let total = GameMode.allCases.reduce(0) { sum, mode in
            sum + (appState.personalBest(for: mode)?.crownTier ?? 0)
        }
        return "\(total)"
    }

    private func statTile(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.black))
                .monospacedDigit()
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Text(label.uppercased())
                .font(.oddfishOverline)
                .foregroundStyle(OddfishTheme.faintInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .oddfishSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var catalogueSection: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.loose) {
            ForEach(catalogueCategories) { category in
                VStack(alignment: .leading, spacing: OddfishTheme.Spacing.snug) {
                    VStack(alignment: .leading, spacing: OddfishTheme.Spacing.hairline) {
                        Text(category.title)
                            .font(.oddfishHeadline)
                            .foregroundStyle(OddfishTheme.ivory)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(category.subtitle)
                            .font(.oddfishCaption)
                            .foregroundStyle(OddfishTheme.mutedInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    modeRow(category.modes)
                }
            }
        }
    }

    private func modeRow(_ modes: [GameMode]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: OddfishTheme.Spacing.snug) {
                ForEach(modes) { mode in
                    modeTile(mode)
                }
            }
            .padding(.horizontal, edge)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        // Cancels the parent's inset so a row can scroll from edge to edge and
        // still start where the headings start.
        .padding(.horizontal, -edge)
    }

    /// Announced modes. Same tile grammar as the playable catalogue so the row
    /// reads as one object, but intentionally not buttons: there is no detail
    /// screen or game behind them yet.
    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.snug) {
            VStack(alignment: .leading, spacing: OddfishTheme.Spacing.hairline) {
                Text("Coming soon")
                    .font(.oddfishHeadline)
                    .foregroundStyle(OddfishTheme.ivory)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("In the next shoal")
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: OddfishTheme.Spacing.snug) {
                    ForEach(upcomingModes) { mode in
                        upcomingTile(mode)
                    }
                }
                .padding(.horizontal, edge)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -edge)
        }
        .accessibilityIdentifier("home-coming-soon")
    }

    private func upcomingTile(_ mode: UpcomingMode) -> some View {
        VStack(spacing: OddfishTheme.Spacing.tight) {
            Image(systemName: mode.systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(mode.tint)
                .frame(height: 46)
                .accessibilityHidden(true)

            VStack(spacing: OddfishTheme.Spacing.hairline) {
                VStack(spacing: 0) {
                    modeTitleLine(mode.titleLead)
                    modeTitleLine(mode.titleFamily)
                }

                upcomingTagline(mode.tagline, tint: mode.tint)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            Text("SOON")
                .font(.oddfishOverline)
                .foregroundStyle(OddfishTheme.faintInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OddfishTheme.Spacing.snug)
        .frame(width: modeTileWidth, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .oddfishSurface()
        .overlay(alignment: .topTrailing) {
            Text("SOON")
                .font(.caption2.weight(.black))
                .foregroundStyle(OddfishTheme.canvas)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(OddfishTheme.faintInk, in: Capsule())
                .padding(8)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mode.titleLead)\(mode.titleFamily). \(mode.ruleSummary) Coming soon.")
        .accessibilityIdentifier("home-coming-soon-\(mode.id)")
    }

    @ViewBuilder
    private func upcomingTagline(_ text: String, tint: Color) -> some View {
        let line = Text(text)
            .font(.oddfishCaption.weight(.semibold))
            .foregroundStyle(tint)
            .multilineTextAlignment(.center)

        if dynamicTypeSize.isAccessibilitySize {
            line.fixedSize(horizontal: false, vertical: true)
        } else {
            line.lineLimit(2, reservesSpace: true).minimumScaleFactor(0.8)
        }
    }

    /// Every tile is the same five rows, in the same places: glyph, lead word,
    /// family word, tagline, crowns. Each row holds its height whether or not
    /// the mode has anything to put in it, which is the whole trick. The
    /// catalogue used to let a three-word name like MoodSwingFish push its own
    /// tagline and crowns down past its neighbour's, and a mode with no crowns
    /// yet drew no footer at all — so no two cards in a row agreed on where
    /// anything went. Reserving the rows costs a little space on the short
    /// names and buys a row that reads as one object.
    ///
    /// Accessibility sizes opt out of the reservation and let the text wrap as
    /// far as it needs to. Symmetry is worth a blank line; it is not worth
    /// clipping a name.
    private func modeTile(_ mode: GameMode) -> some View {
        let isLocked = !purchases.canPlay(mode)

        return Button { onSelectMode(mode) } label: {
            VStack(spacing: OddfishTheme.Spacing.tight) {
                OddfishModeGlyph(mode: mode, size: 46)

                VStack(spacing: OddfishTheme.Spacing.hairline) {
                    // The names are camel-case compounds that nearly all end in
                    // the same word, so the split writes itself: what makes the
                    // mode different on the first line, the family it belongs
                    // to on the second. Restfish and Pacifish have no
                    // family word and leave the second line empty rather than
                    // pulling the rest of the card up.
                    VStack(spacing: 0) {
                        modeTitleLine(mode.titleLead)
                        modeTitleLine(mode.titleFamily)
                    }

                    modeTagline(mode)
                }
                .frame(maxWidth: .infinity)

                // Contributes nothing to the tile's own height, so ordinary
                // text sizes still land on one shared footer line. It only does
                // work when a card has been stretched to match a taller
                // neighbour, where it keeps the crowns on the floor rather than
                // leaving them stranded under the tagline.
                Spacer(minLength: 0)

                // Three slots on every tile, filled or not, so the footer is a
                // line the eye can run along rather than a detail that only
                // appears once a mode has been beaten.
                CrownTrack(
                    tier: appState.personalBest(for: mode)?.crownTier ?? 0,
                    size: crownTrackSize
                )
                .accessibilityIdentifier("home-best-\(mode.rawValue)")
            }
            .padding(OddfishTheme.Spacing.snug)
            .frame(width: modeTileWidth, alignment: .top)
            // Reserved rows already give every card the same height at ordinary
            // text sizes. Accessibility sizes let the text wrap as far as it
            // needs to, so the cards match the tallest one in their row instead.
            .frame(maxHeight: .infinity, alignment: .top)
            .oddfishSurface()
            .overlay(alignment: .topTrailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(OddfishTheme.canvas)
                        .frame(width: 26, height: 26)
                        .background(OddfishTheme.gold, in: Circle())
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(OddfishPressableStyle())
        .accessibilityLabel(variantAccessibilityLabel(mode, isLocked: isLocked))
        .accessibilityHint(
            isLocked
                ? "Requires the one-time Full Oddfish unlock"
                : "Double tap to read the rule and start"
        )
        .accessibilityIdentifier("home-mode-\(mode.rawValue)")
    }

    /// One row of a mode name. `reservesSpace` is what stops an empty family
    /// word from collapsing its row, and the single line is what stops a long
    /// lead word from claiming two.
    @ViewBuilder
    private func modeTitleLine(_ text: String) -> some View {
        let line = Text(text)
            .font(.oddfishHeadline)
            .foregroundStyle(OddfishTheme.ivory)
            .multilineTextAlignment(.center)

        if dynamicTypeSize.isAccessibilitySize {
            // A name is one unbreakable word. Let it shrink rather than run off
            // the side of its card.
            line.fixedSize(horizontal: false, vertical: true).minimumScaleFactor(0.6)
        } else {
            line.lineLimit(1, reservesSpace: true).minimumScaleFactor(0.65)
        }
    }

    /// Two rows, always, for a line of copy that is sometimes one.
    @ViewBuilder
    private func modeTagline(_ mode: GameMode) -> some View {
        let line = Text(mode.tagline)
            .font(.oddfishCaption.weight(.semibold))
            .foregroundStyle(mode.tint)
            .multilineTextAlignment(.center)

        if dynamicTypeSize.isAccessibilitySize {
            line.fixedSize(horizontal: false, vertical: true)
        } else {
            line.lineLimit(2, reservesSpace: true).minimumScaleFactor(0.8)
        }
    }

    private func variantAccessibilityLabel(_ mode: GameMode, isLocked: Bool) -> String {
        let access = isLocked ? " Locked." : ""
        guard let best = appState.personalBest(for: mode),
              let score = best.score,
              let crowns = best.crownTier else {
            return "\(mode.title). \(mode.ruleSummary)\(access)"
        }
        return "\(mode.title). \(mode.ruleSummary) Personal best: \(crowns) crowns, \(score.formatted).\(access)"
    }

    /// The one action the screen exists to offer, kept under the thumb and out
    /// of the scroll. Because it is a layout sibling rather than an overlay,
    /// catalogue text is clipped cleanly above it instead of fading underneath.
    private var playBar: some View {
        VStack(spacing: 6) {
            Button("Play Classic", systemImage: "play.fill", action: onQuickPlay)
                .buttonStyle(OddfishPrimaryButtonStyle())
                .accessibilityHint("Starts a classic game immediately")
            // A Classic best replaces the strapline once there is one. The
            // record strip at the top already carries the running totals,
            // so repeating them here bought nothing.
            if let best = appState.personalBest(for: .classic) {
                PersonalBestBadge(record: best)
                    .accessibilityIdentifier("home-best-classic")
            } else {
                Text(recordLine)
                    .font(.oddfishCaption.weight(.semibold))
                    .foregroundStyle(OddfishTheme.faintInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, edge)
        .padding(.top, OddfishTheme.Spacing.tight)
        .padding(.bottom, 4)
        .background(OddfishTheme.canvas)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
    }

    private var recordLine: String {
        let stats = appState.stats
        guard stats.gamesPlayed > 0 else { return "Standard rules. No handicap." }
        return "\(stats.gamesPlayed) played · \(stats.wins) won · \(stats.losses) lost"
    }
}

/// A mode announced on Home before its rule exists. Presentation copy only —
/// never a `GameMode`, so nothing in the session, persistence, or paywall can
/// mistake it for something playable.
private struct UpcomingMode: Identifiable {
    let id: String
    let titleLead: String
    let titleFamily: String
    let tagline: String
    let ruleSummary: String
    let systemImage: String

    /// All three launch teasers weaken the engine, so they wear the weakening
    /// tint rather than borrowing a playable mode's colour.
    var tint: Color { OddfishTheme.coral }
}

/// A rounded rectangle with a small tail on its leading edge, so what Gil says
/// is drawn as speech rather than as another card.
struct SpeechBubble: Shape {
    var tail: CGFloat = 7
    var radius: CGFloat = OddfishTheme.Radius.card

    func path(in rect: CGRect) -> Path {
        var path = Path(
            roundedRect: CGRect(x: rect.minX + tail, y: rect.minY, width: rect.width - tail, height: rect.height),
            cornerRadius: radius,
            style: .continuous
        )
        let anchor = min(rect.minY + radius + 6, rect.maxY - 6)
        path.move(to: CGPoint(x: rect.minX, y: anchor - tail))
        path.addLine(to: CGPoint(x: rect.minX + tail + 1, y: anchor - tail - 3))
        path.addLine(to: CGPoint(x: rect.minX + tail + 1, y: anchor + tail))
        path.closeSubpath()
        return path
    }
}

#Preview("Home") {
    let store = AppStateStore()
    return NavigationStack {
        HomeView(onSelectMode: { _ in }, onSettings: {}, onHistory: {}, onQuickPlay: {})
            .environment(store)
            .environment(PurchaseManager())
    }
}
