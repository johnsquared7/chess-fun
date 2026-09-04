import Foundation
import Observation

/// How far a player has come through the introduction.
///
/// The first launch deliberately skips the home screen and drops the player
/// straight into a game against the full-strength opponent; everything after
/// that is driven by which of these stages the install is in.
nonisolated public enum OnboardingStage: String, Codable, CaseIterable, Hashable, Sendable {
    /// Nothing has happened yet. The next launch starts the introduction game.
    case notStarted
    /// The introduction game has begun but has not finished. Relaunching mid-game
    /// resumes the introduction rather than dropping the player on the home screen.
    case bossGameInProgress
    /// The introduction game is over and the player has not yet been offered the
    /// variants that follow it.
    case bossGameFinished
    /// The introduction is done. Launch goes to the home screen from here on.
    case completed
}

/// Main-actor owner for the small amount of durable application state.
///
/// UserDefaults writes are intentionally compact and best-effort. A malformed
/// payload is treated as a fresh install; persistence must never block launch.
@Observable
@MainActor
public final class AppStateStore {
    nonisolated public static let defaultHistoryLimit = 100

    public var settings: AppSettings {
        didSet { persist() }
    }
    public private(set) var stats: PlayerStats
    public private(set) var history: [GameRecord]
    public private(set) var onboardingStage: OnboardingStage
    /// Modes whose rule the guide has already explained. An explanation is shown
    /// once per install, not once per game.
    private(set) var taughtModes: Set<GameMode>
    /// Identifiers of guide lines that are only ever said once per install.
    public private(set) var seenBeats: Set<String>
    /// The game in progress, if there is one worth resuming.
    private(set) var activeGame: GameSnapshot?

    public var hasCompletedOnboarding: Bool { onboardingStage == .completed }

    private let userDefaults: UserDefaults
    private let historyLimit: Int

    private enum Keys {
        static let payload = "oddfish.appStore.payload"
        /// One-time migration: the in-game side switch used to persist into the
        /// global default, leaking Black into the next mode's game.
        static let sidePreferenceSessionOnlyMigration = "oddfish.migrated.sidePreferenceSessionOnly.v1"
    }

    private struct Payload: Codable {
        let settings: AppSettings
        let stats: PlayerStats
        let history: [GameRecord]
        let onboardingStage: OnboardingStage
        let taughtModes: Set<GameMode>
        let seenBeats: Set<String>
        let activeGame: GameSnapshot?
    }

    /// Launch arguments the UI tests use to get a deterministic app.
    ///
    /// Without these, tests share one container: "once ever" state set by an
    /// earlier test silently changes what a later test sees, which is exactly
    /// the kind of order-dependence that makes a suite untrustworthy.
    public enum LaunchArgument {
        /// Start from a clean install.
        public static let reset = "-oddfishUITestReset"
        /// Start with the guide muted, for tests about the plain game surfaces.
        public static let silentGuide = "-oddfishUITestSilentGuide"
        /// Start as a player who has already been through the introduction, for
        /// tests about the home screen and everything reachable from it.
        public static let skipIntroduction = "-oddfishUITestSkipIntroduction"
        /// Start with the Stage 4 assistance layer visible so UI evidence can
        /// wait through a cold network boot without racing a live toggle.
        public static let evaluation = "-oddfishUITestEvaluation"
        /// Seed one deterministic crowned game for Stage 6 home/history review.
        public static let historySample = "-oddfishUITestHistorySample"
    }

    public init(
        userDefaults: UserDefaults = .standard,
        historyLimit: Int = AppStateStore.defaultHistoryLimit
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(LaunchArgument.reset) {
            userDefaults.removeObject(forKey: Keys.payload)
        }
        self.userDefaults = userDefaults
        self.historyLimit = max(1, historyLimit)

        if let data = userDefaults.data(forKey: Keys.payload),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            self.settings = payload.settings
            self.stats = payload.stats
            self.history = Array(payload.history.prefix(max(1, historyLimit)))
            self.onboardingStage = payload.onboardingStage
            self.taughtModes = payload.taughtModes
            self.seenBeats = payload.seenBeats
            self.activeGame = payload.activeGame.flatMap { $0.isResumable ? $0 : nil }
        } else {
            self.settings = .default
            self.stats = PlayerStats()
            self.history = []
            self.taughtModes = []
            self.seenBeats = []
            self.activeGame = nil
            self.onboardingStage = .notStarted
        }

        // The side choice is now session-only: switching sides restarts the
        // current game but never rewrites the global default, so a new mode
        // always starts White unless the Settings toggle explicitly says
        // otherwise. Clear any default previously polluted by the old
        // behaviour, exactly once — future explicit Settings choices persist.
        if !userDefaults.bool(forKey: Keys.sidePreferenceSessionOnlyMigration) {
            if settings.playAsBlack {
                settings.playAsBlack = false
            }
            userDefaults.set(true, forKey: Keys.sidePreferenceSessionOnlyMigration)
            persist()
        }

        if arguments.contains(LaunchArgument.silentGuide) {
            self.settings.guideChattiness = .off
        }
        if arguments.contains(LaunchArgument.skipIntroduction) {
            self.onboardingStage = .completed
        }
        if arguments.contains(LaunchArgument.evaluation) {
            self.settings.evaluationEnabled = true
        }
        if arguments.contains(LaunchArgument.historySample), history.isEmpty {
            let sample = GameRecord(
                modeID: GameMode.classic.rawValue,
                result: .win,
                duration: 184,
                moveCount: 6,
                notation: "e4 e5 Nf3 Nc6 Bb5 a6",
                startingFEN: Position.starting.fen,
                playerColorID: PieceColor.white.rawValue,
                startingRating: 1_600,
                endingRating: 1_600,
                award: CrownAward(
                    tier: 3,
                    score: CrownScore(value: 1_600, metric: .opponentElo)
                )
            )
            history = [sample]
            stats.record(.win)
        }
    }

    public func saveSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    public func saveOnboarding(_ completed: Bool = true) {
        advanceOnboarding(to: completed ? .completed : .notStarted)
    }

    /// Moves the introduction forward. The stage never moves backwards on its
    /// own, so a replayed game cannot demote a player who already finished.
    public func advanceOnboarding(to stage: OnboardingStage) {
        guard stage != onboardingStage else { return }
        onboardingStage = stage
        persist()
    }

    /// Records that the guide has explained this mode, so it is not explained again.
    func markModeTaught(_ mode: GameMode) {
        guard !taughtModes.contains(mode) else { return }
        taughtModes.insert(mode)
        persist()
    }

    func hasTaught(_ mode: GameMode) -> Bool {
        taughtModes.contains(mode)
    }

    /// Records the game in progress, or clears it when there is none.
    func setActiveGame(_ snapshot: GameSnapshot?) {
        let resumable = snapshot.flatMap { $0.isResumable ? $0 : nil }
        guard resumable != activeGame else { return }
        activeGame = resumable
        persist()
    }

    public func hasSeenBeat(_ id: String) -> Bool {
        seenBeats.contains(id)
    }

    public func markBeatSeen(_ id: String) {
        guard !seenBeats.contains(id) else { return }
        seenBeats.insert(id)
        persist()
    }

    public func completeOnboarding() {
        saveOnboarding(true)
    }

    public func recordCompletedGame(_ record: GameRecord) {
        history.insert(record, at: 0)
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
        if !record.isImported {
            stats.record(record.result)
        }
        persist()
    }

    /// Imported PGNs live in the same review history but never affect local
    /// play stats or crown records.
    public func importGame(_ record: GameRecord) {
        guard record.isImported else { return }
        recordCompletedGame(record)
    }

    func personalBests(for mode: GameMode) -> [GameRecord] {
        let candidates = history.filter {
            $0.modeID == mode.rawValue && !$0.isImported && $0.award != nil
        }
        let grouped = Dictionary(grouping: candidates, by: \.personalBestID)
        return grouped.values.compactMap { records in
            records.sorted(by: Self.isBetterRecord).first
        }.sorted { lhs, rhs in
            if lhs.personalBestVariant == rhs.personalBestVariant {
                return Self.isBetterRecord(lhs, rhs)
            }
            return (lhs.personalBestVariant ?? "") < (rhs.personalBestVariant ?? "")
        }
    }

    func personalBest(for mode: GameMode) -> GameRecord? {
        personalBests(for: mode).sorted(by: Self.isBetterRecord).first
    }

    public func record(game record: GameRecord) {
        recordCompletedGame(record)
    }

    public func recordCompletedGame(
        modeID: String,
        result: GameResult,
        duration: TimeInterval,
        moveCount: Int,
        date: Date = Date(),
        notation: String? = nil
    ) {
        recordCompletedGame(GameRecord(
            modeID: modeID,
            result: result,
            duration: duration,
            moveCount: moveCount,
            date: date,
            notation: notation
        ))
    }

    public func clearHistory() {
        history.removeAll(keepingCapacity: true)
        persist()
    }

    public func resetStats() {
        stats = PlayerStats()
        persist()
    }

    private func persist() {
        let payload = Payload(
            settings: settings,
            stats: stats,
            history: history,
            onboardingStage: onboardingStage,
            taughtModes: taughtModes,
            seenBeats: seenBeats,
            activeGame: activeGame
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        userDefaults.set(data, forKey: Keys.payload)
    }

    private nonisolated static func isBetterRecord(_ lhs: GameRecord, _ rhs: GameRecord) -> Bool {
        guard let left = lhs.score, let right = rhs.score else {
            return lhs.score != nil
        }
        if left.value != right.value, left.metric == right.metric {
            return left.isBetter(than: right)
        }
        if lhs.crownTier != rhs.crownTier {
            return (lhs.crownTier ?? 0) > (rhs.crownTier ?? 0)
        }
        return lhs.date > rhs.date
    }
}
