import Testing
@testable import Oddfish

/// The end of a game is a sequence, and the bug it was written to fix is a
/// timing bug: the result scrim used to be drawn the instant the position
/// became terminal, on top of a mating piece that was still travelling.
///
/// These tests assert the order and the gaps, not the pixels.
struct EndgameChoreographyTests {
    @Test @MainActor func stagesArriveInOrder() async {
        var stages: [EndgameChoreography.Stage] = []
        await EndgameChoreography.play(
            travel: .milliseconds(10),
            hold: .milliseconds(10)
        ) { stage in
            stages.append(stage)
        }
        #expect(stages == [.boardFinale, .curtain])
    }

    /// The board must own the screen for the whole hold. If this gap ever
    /// collapses, the checkmate is again invisible.
    @Test @MainActor func theBoardKeepsTheScreenForTheWholeHold() async {
        let clock = ContinuousClock()
        var finaleAt: ContinuousClock.Instant?
        var curtainAt: ContinuousClock.Instant?
        await EndgameChoreography.play(
            travel: .milliseconds(20),
            hold: .milliseconds(120)
        ) { stage in
            switch stage {
            case .boardFinale: finaleAt = clock.now
            case .curtain: curtainAt = clock.now
            case .idle: break
            }
        }
        let finale = try! #require(finaleAt)
        let curtain = try! #require(curtainAt)
        #expect(finale.duration(to: curtain) >= .milliseconds(110))
    }

    /// Cancelling — a rematch tapped mid-sequence — must not deliver a curtain
    /// onto the fresh board that replaced the finished one.
    @Test @MainActor func cancellationStopsBeforeTheCurtain() async {
        var stages: [EndgameChoreography.Stage] = []
        let task = Task { @MainActor in
            await EndgameChoreography.play(
                travel: .milliseconds(10),
                hold: .seconds(5)
            ) { stage in
                stages.append(stage)
            }
        }
        try? await Task.sleep(for: .milliseconds(60))
        task.cancel()
        await task.value
        #expect(stages == [.boardFinale])
    }

    /// The shipped values, checked as values. A hold shorter than half a second
    /// is not long enough to read a word on the board.
    @Test func shippedBeatsLeaveTheBoardVisible() {
        #expect(OddfishTheme.Beat.terminalHold >= 0.5)
        #expect(OddfishTheme.Beat.resultCurtain >= 0.8)
        #expect(OddfishTheme.Beat.pieceTravel >= 0.25)
    }
}
