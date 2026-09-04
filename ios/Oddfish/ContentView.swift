import SwiftUI

struct ContentView: View {
    private enum Sheet: Identifiable {
        case settings
        case history
        case fullUnlock(GameMode?)

        var id: String {
            switch self {
            case .settings: "settings"
            case .history: "history"
            case .fullUnlock(let mode): "full-unlock-\(mode?.rawValue ?? "all")"
            }
        }
    }

    /// Where the player was headed when a locked route opened the paywall.
    /// This makes every entry point use the same access decision instead of
    /// teaching individual screens how to infer what should happen next.
    private enum UnlockDestination {
        case modeDetail(GameMode)
        case newGame(GameMode)
        case resumedGame(GameMode)

        var mode: GameMode {
            switch self {
            case .modeDetail(let mode), .newGame(let mode), .resumedGame(let mode):
                mode
            }
        }
    }

    @State private var path: [OddfishRoute] = []
    @State private var sheet: Sheet?
    @State private var requestedUnlockDestination: UnlockDestination?
    @State private var destinationAfterUnlock: UnlockDestination?
    @State private var feedback = SystemFeedbackService()
    @State private var didRouteLaunch = false
    @Environment(AppStateStore.self) private var appState
    @Environment(PurchaseManager.self) private var purchases

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                onSelectMode: selectMode,
                onSettings: { sheet = .settings },
                onHistory: { sheet = .history },
                onQuickPlay: { startMode(.classic) }
            )
            .navigationDestination(for: OddfishRoute.self) { route in
                switch route {
                case .modeDetail(let mode):
                    ModeDetailView(mode: mode) { selectedMode in
                        startMode(selectedMode)
                    }
                case .introduction:
                    // The first game is the product's argument: you cannot
                    // out-calculate this thing. It is therefore always the boss
                    // at full strength, whatever the settings say.
                    GameView(
                        mode: .classic,
                        settings: appState.settings,
                        playerColor: .white,
                        rating: .maximum,
                        feedback: feedback,
                        opponent: { await OpponentProvider.shared() },
                        onRecord: appState.recordCompletedGame,
                        onExit: { finishIntroduction() },
                        onChangeMode: { finishIntroduction() },
                        onPickMode: { picked in startOfferedMode(picked) },
                        onDeclineOffer: { appState.advanceOnboarding(to: .completed) },
                        onSettingsChange: appState.saveSettings,
                        onSnapshot: { appState.setActiveGame($0) }
                    )

                case .resumedGame(let mode):
                    GameView(
                        mode: mode,
                        settings: appState.settings,
                        feedback: feedback,
                        opponent: { await OpponentProvider.shared() },
                        onRecord: appState.recordCompletedGame,
                        onExit: { path = [] },
                        onChangeMode: { path = [] },
                        onPickMode: { picked in startOfferedMode(picked) },
                        onDeclineOffer: { appState.advanceOnboarding(to: .completed) },
                        onSettingsChange: appState.saveSettings,
                        onSnapshot: { appState.setActiveGame($0) },
                        restoring: appState.activeGame
                    )

                case .game(let mode):
                    GameView(
                        mode: mode,
                        settings: appState.settings,
                        feedback: feedback,
                        opponent: { await OpponentProvider.shared() },
                        onRecord: appState.recordCompletedGame,
                        // Home is the canonical launcher. Returning to the root
                        // keeps the three variant discovery stops visible.
                        onExit: { path = [] },
                        onChangeMode: { path = [] },
                        // Gil's offer changes the rules, not the engine's
                        // default strength.
                        onPickMode: { picked in startOfferedMode(picked) },
                        onDeclineOffer: { appState.advanceOnboarding(to: .completed) },
                        onSettingsChange: appState.saveSettings,
                        onSnapshot: { appState.setActiveGame($0) }
                    )
                }
            }
        }
        // One place applies the chosen appearance, so every board, promotion
        // sheet, and mode glyph in the app agrees without threading it through.
        .boardAppearance(
            theme: appState.settings.boardTheme,
            pieceSet: appState.settings.pieceSet,
            pieceStyle: appState.settings.pieceStyle,
            decoration: appState.settings.boardDecoration
        )
        .tint(OddfishTheme.seaGlass)
        // Boot the engine alongside the first screen so the opening move of the
        // first game does not pay for the UCI handshake.
        .task {
            guard !isHostedUnitTest else { return }
            OpponentProvider.warmUp()
            await purchases.prepare()
            routeLaunch()
        }
        .onAppear(perform: routeLaunch)
        .onChange(of: purchases.entitlement) { _, _ in routeLaunch() }
        .sheet(item: $sheet, onDismiss: finishSheetDismissal) { selectedSheet in
            switch selectedSheet {
            case .settings:
                SettingsView(settings: settingsBinding)
            case .history:
                HistoryView(
                    records: appState.history,
                    stats: appState.stats,
                    onClear: appState.clearHistory,
                    onImport: appState.importGame
                )
            case .fullUnlock(let mode):
                PaywallView(requestedMode: mode) {
                    destinationAfterUnlock = requestedUnlockDestination
                    requestedUnlockDestination = nil
                    sheet = nil
                }
            }
        }
    }

    /// A first launch never sees the home screen. It goes straight into a game
    /// against the boss, because the point of the introduction is the experience
    /// of losing to it, and a menu in front of that only delays the argument.
    ///
    /// A launch that lands mid-introduction resumes it rather than quietly
    /// dropping the player somewhere else.
    private func routeLaunch() {
        guard !didRouteLaunch else { return }

        // Unit tests are hosted *inside* this app. Starting a game on launch
        // would have the app driving the one shared chess engine at the same
        // time as the tests that are examining it.
        guard !isHostedUnitTest else {
            didRouteLaunch = true
            return
        }

        // An interrupted game outranks everything else: the player was in the
        // middle of it, and it is the thing they will expect to see.
        if let resumable = appState.activeGame, let mode = resumable.mode {
            // StoreKit entitlement resolution is asynchronous. Waiting here
            // prevents a paid saved game from briefly bypassing the paywall.
            guard !mode.requiresFullUnlock || purchases.entitlement != .checking else { return }
            didRouteLaunch = true

            if purchases.canPlay(mode) {
                path = [.resumedGame(mode)]
            } else {
                presentPaywall(for: mode, destination: .resumedGame(mode))
            }
            return
        }

        didRouteLaunch = true
        switch appState.onboardingStage {
        case .notStarted, .bossGameInProgress:
            appState.advanceOnboarding(to: .bossGameInProgress)
            path = [.introduction]
        case .bossGameFinished, .completed:
            break
        }
    }

    /// Leaving the introduction any way at all ends it. Somebody who walks out
    /// of their first game should not be handed it again on the next launch.
    private func finishIntroduction() {
        appState.advanceOnboarding(to: .completed)
        path = []
    }

    /// A handicap chosen from Gil's offer changes mode without silently
    /// weakening Stockfish. The selected mode owns any strength changes that
    /// are part of its actual rules.
    private func startOfferedMode(_ mode: GameMode) {
        appState.advanceOnboarding(to: .completed)
        startMode(mode, replacingPath: true)
    }

    private var settingsBinding: Binding<AppSettings> {
        Binding(
            get: { appState.settings },
            set: { appState.saveSettings($0) }
        )
    }

    private var isHostedUnitTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func selectMode(_ mode: GameMode) {
        guard purchases.canPlay(mode) else {
            presentPaywall(for: mode, destination: .modeDetail(mode))
            return
        }
        path.append(.modeDetail(mode))
    }

    private func startMode(_ mode: GameMode, replacingPath: Bool = false) {
        guard purchases.canPlay(mode) else {
            presentPaywall(for: mode, destination: .newGame(mode))
            return
        }

        appState.saveOnboarding()
        if replacingPath {
            path = [.game(mode)]
        } else {
            path.append(.game(mode))
        }
    }

    private func presentPaywall(for mode: GameMode, destination: UnlockDestination) {
        requestedUnlockDestination = destination
        sheet = .fullUnlock(mode)
    }

    private func finishSheetDismissal() {
        guard let destination = destinationAfterUnlock else {
            requestedUnlockDestination = nil
            return
        }

        destinationAfterUnlock = nil
        // Access may change while the success alert or sheet dismissal is in
        // flight (for example, a StoreKit revocation update). Never let that
        // narrow timing window bypass the same gate used by every launcher.
        guard purchases.canPlay(destination.mode) else { return }

        switch destination {
        case .modeDetail(let mode):
            path.append(.modeDetail(mode))
        case .newGame(let mode):
            appState.saveOnboarding()
            path.append(.game(mode))
        case .resumedGame(let mode):
            path = [.resumedGame(mode)]
        }
    }
}

/// A small route wrapper keeps the game hand-off explicit. The real session/board can
/// replace this destination without changing mode browsing or onboarding.
enum OddfishRoute: Hashable {
    case modeDetail(GameMode)
    case game(GameMode)
    /// A game continued from a snapshot, rather than started fresh.
    case resumedGame(GameMode)
    /// The first-run game against the boss, at full strength.
    case introduction
}

#Preview("Home") {
    let store = AppStateStore()
    return ContentView()
        .environment(store)
        .environment(GuideDirector(store: store))
        .environment(PurchaseManager())
}
