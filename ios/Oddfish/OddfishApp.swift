import SwiftUI

@main
struct OddfishApp: App {
    @State private var appState: AppStateStore
    @State private var guide: GuideDirector
    @State private var purchases: PurchaseManager

    init() {
        let store = AppStateStore()
        _appState = State(initialValue: store)
        _purchases = State(initialValue: PurchaseManager())
        // App-level on purpose. `restart()` clears the event log and re-emits
        // `.gameStarted`, so anything that must be remembered across a restart
        // — once-ever beats, how much he has already said — cannot live in a view.
        _guide = State(initialValue: GuideDirector(store: store))
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            OddfishStartupGate {
                ContentView()
                    .environment(appState)
                    .environment(guide)
                    .environment(purchases)
            }
            .preferredColorScheme(.dark)
            // The engine thread has no idea the app left the screen. Stopping
            // its search on the way out keeps it from holding a core behind the
            // home screen; the engine itself stays loaded so coming back is
            // instant.
            .onChange(of: scenePhase) { _, phase in
                guard phase != .active else { return }
                Task { await OpponentProvider.suspendSearches() }
            }
        }
    }
}

/// Keeps the first SwiftUI frame visually continuous with the static launch screen
/// while keeping the expensive home hierarchy out of that first commit. This is
/// presentation-only: it does not load data or gate any business logic.
struct OddfishStartupGate<Content: View>: View {
    /// Gives UI evidence enough time to capture the branded handoff without
    /// slowing a real launch.
    private static var brandEvidenceArgument: String { "-oddfishUITestHoldBrand" }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: OddfishStartupPhase = .brandOnly
    @State private var homeHandoffScheduled = false
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            // `content` is deliberately invoked only after the brand-only root
            // committed. Constructing it in the initial phase lets Home's first
            // layout delay the very first SwiftUI frame.
            if phase.showsHome {
                content()
                    .onAppear(perform: homeDidAppear)
                    .zIndex(0)
            }

            if phase.showsBrand {
                OddfishStartupBrand()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // Fill the root while the launch storyboard hands control to SwiftUI.
        // The brand also paints this color, but this protects the window-sized
        // container during the phase changes.
        .background(OddfishTheme.canvas.ignoresSafeArea())
        .onAppear(perform: scheduleHomePreparation)
    }

    @MainActor
    private func scheduleHomePreparation() {
        guard phase == .brandOnly else { return }

        // Keep the brand-only root for a bounded 120 ms so it can reach the screen
        // before ContentView is constructed. The complete handoff, including the
        // 160 ms fade, remains well below the launch budget.
        let delay = ProcessInfo.processInfo.arguments.contains(Self.brandEvidenceArgument) ? 2.0 : 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard phase == .brandOnly else { return }
            phase = .preparingHome
        }
    }

    @MainActor
    private func homeDidAppear() {
        guard phase == .preparingHome, !homeHandoffScheduled else { return }
        homeHandoffScheduled = true

        // Let the inserted subtree reach its first compositor commit before the
        // lockup changes. Reduce Motion skips only the fade, after this commit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard phase == .preparingHome else { return }

            if reduceMotion {
                phase = .home
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    phase = .home
                }
            }
        }
    }
}

/// Explicit launch presentation states. Kept separate from the view so the
/// sequencing contract can be tested without a timing-sensitive UI test.
enum OddfishStartupPhase: Equatable {
    case brandOnly
    case preparingHome
    case home

    var showsBrand: Bool { self != .home }
    var showsHome: Bool { self != .brandOnly }
}

private struct OddfishStartupBrand: View {
    // Keep these values in lockstep with LaunchScreen.storyboard. Both surfaces
    // render the exact Split O asset at the same size and anchor.
    private enum Metrics {
        static let markWidth: CGFloat = 120
        static let markHeight: CGFloat = markWidth
        static let wordmarkHeight: CGFloat = 41
        static let ruleWidth: CGFloat = 66
        static let ruleHeight: CGFloat = 2
        static let taglineHeight: CGFloat = 18
        static let markCenterYOffset: CGFloat = -109
        static let wordmarkTop: CGFloat = 18
        static let ruleTop: CGFloat = 13
        static let taglineTop: CGFloat = 18

        static let lockupHeight = markHeight + wordmarkTop + wordmarkHeight
            + ruleTop + ruleHeight + taglineTop + taglineHeight
    }

    var body: some View {
        GeometryReader { container in
            ZStack {
                OddfishTheme.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    OddfishBrandMark(size: Metrics.markWidth)

                    Text("ODDFISH")
                        .font(.system(size: 31, weight: .black, design: .default))
                        .tracking(1.4)
                        .foregroundStyle(OddfishTheme.ivory)
                        .frame(maxWidth: .infinity, minHeight: Metrics.wordmarkHeight, maxHeight: Metrics.wordmarkHeight)
                        .padding(.top, Metrics.wordmarkTop)

                    Capsule()
                        .fill(OddfishTheme.seaGlass)
                        .frame(width: Metrics.ruleWidth, height: Metrics.ruleHeight)
                        .padding(.top, Metrics.ruleTop)

                    Text("CHESS, BUT A LITTLE STRANGER")
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .tracking(0.7)
                        .foregroundStyle(OddfishTheme.seaGlass)
                        .frame(maxWidth: .infinity, minHeight: Metrics.taglineHeight, maxHeight: Metrics.taglineHeight)
                        .padding(.top, Metrics.taglineTop)
                }
                // Anchor the mark center at container midpoint - 109pt, exactly
                // matching LaunchScreenMarkCenterY in LaunchScreen.storyboard.
                .frame(maxWidth: .infinity)
                .position(
                    x: container.size.width / 2,
                    y: container.size.height / 2 + Metrics.markCenterYOffset
                        + (Metrics.lockupHeight - Metrics.markHeight) / 2
                )
                .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }
}
