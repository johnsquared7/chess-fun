import Foundation
import Testing
@testable import Oddfish

/// Persistence tests are serialized because they intentionally exercise the
/// app's real UserDefaults keys in the isolated test-host domain.
@Suite(.serialized)
@MainActor
struct AppStateStoreTests {
    private static let payloadKey = "oddfish.appStore.payload"

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.payloadKey)
        return defaults
    }

    @Test func defaultsAreFreshAndSettingsRoundTrip() {
        let defaults = makeDefaults()
        let store = AppStateStore(userDefaults: defaults)

        #expect(store.settings == .default)
        #expect(!store.hasCompletedOnboarding)
        store.saveSettings(AppSettings(soundEnabled: false, hapticsEnabled: true))
        store.completeOnboarding()

        let restored = AppStateStore(userDefaults: defaults)
        #expect(!restored.settings.soundEnabled)
        #expect(restored.settings.hapticsEnabled)
        #expect(restored.hasCompletedOnboarding)
    }

    @Test func eachModePersistsItsOwnStartingRating() {
        let defaults = makeDefaults()
        let store = AppStateStore(userDefaults: defaults)
        var settings = store.settings
        settings.setRating(OpponentRating(2_800), for: .classic)
        settings.setRating(OpponentRating(3_600), for: .restfish)
        store.saveSettings(settings)

        let restored = AppStateStore(userDefaults: defaults)
        #expect(restored.settings.rating(for: .classic) == OpponentRating(2_800))
        #expect(restored.settings.rating(for: .restfish) == OpponentRating(3_600))
        #expect(restored.settings.rating(for: .stableFish) == .default)
    }

    @Test func historyIsNewestFirstAndBounded() {
        let store = AppStateStore(userDefaults: makeDefaults(), historyLimit: 2)
        let first = GameRecord(modeID: "classic", result: .win, duration: 1, moveCount: 2)
        let second = GameRecord(modeID: "tempofish", result: .loss, duration: 2, moveCount: 4)
        let third = GameRecord(modeID: "flinchfish", result: .draw, duration: 3, moveCount: 6)

        store.recordCompletedGame(first)
        store.recordCompletedGame(second)
        store.recordCompletedGame(third)

        #expect(store.history.count == 2)
        #expect(store.history.map(\.id) == [third.id, second.id])
        #expect(store.stats.gamesPlayed == 3)
        #expect(store.stats.wins == 1)
        #expect(store.stats.losses == 1)
        #expect(store.stats.draws == 1)
    }

    @Test func clearHistoryAndResetStatsAreIndependent() {
        let store = AppStateStore(userDefaults: makeDefaults())
        store.recordCompletedGame(GameRecord(modeID: "classic", result: .win, duration: 0, moveCount: 0))

        store.clearHistory()
        #expect(store.history.isEmpty)
        #expect(store.stats.gamesPlayed == 1)

        store.resetStats()
        #expect(store.stats == PlayerStats())
    }
}

/// Onboarding state decides whether launch drops the player into the
/// introduction game or onto the home screen.
@Suite(.serialized)
@MainActor
struct OnboardingStageTests {
    private static let payloadKey = "oddfish.appStore.payload"

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.payloadKey)
        return defaults
    }

    @Test func afreshInstallStartsBeforeTheIntroduction() {
        let store = AppStateStore(userDefaults: makeDefaults())
        #expect(store.onboardingStage == .notStarted)
        #expect(store.taughtModes.isEmpty)
        #expect(!store.hasCompletedOnboarding)
    }

    @Test func stageAndTaughtModesSurviveARelaunch() {
        let defaults = makeDefaults()
        let store = AppStateStore(userDefaults: defaults)
        store.advanceOnboarding(to: .bossGameFinished)
        store.markModeTaught(.restfish)
        store.markModeTaught(.rattleFish)

        let reloaded = AppStateStore(userDefaults: defaults)
        #expect(reloaded.onboardingStage == .bossGameFinished)
        #expect(reloaded.taughtModes == [.restfish, .rattleFish])
        #expect(reloaded.hasTaught(.restfish))
        #expect(!reloaded.hasTaught(.flinchFish))
    }

    @Test func teachingTheSameModeTwiceIsNotRecordedTwice() {
        let store = AppStateStore(userDefaults: makeDefaults())
        store.markModeTaught(.flinchFish)
        store.markModeTaught(.flinchFish)
        #expect(store.taughtModes == [.flinchFish])
    }
}
