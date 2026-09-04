import Foundation
import Testing
@testable import Oddfish

/// Pure parsing checks. These need no engine, so they run everywhere.
struct StockfishNotationTests {
    @Test func aMoveIsWrittenInPlainUCI() throws {
        let move = try #require(ChessEngine.legalMoves(in: .starting).first {
            $0.from == Square("e2")! && $0.to == Square("e4")!
        })
        #expect(StockfishOpponent.uciString(for: move) == "e2e4")
    }

    @Test func promotionsCarryALowercaseSuffix() throws {
        let position = try #require(Position(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"))
        let move = try #require(ChessEngine.legalMoves(in: position).first {
            $0.to == Square("a8")! && $0.promotion == .queen
        })
        #expect(StockfishOpponent.uciString(for: move) == "a7a8q")
    }

    @Test func castlingUsesTheKingsOwnDestination() throws {
        let position = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R w K - 0 1"))
        let move = try #require(ChessEngine.legalMoves(in: position).first { $0.isCastle })
        #expect(StockfishOpponent.uciString(for: move) == "e1g1")
    }

    @Test func aReplyIsMatchedAgainstTheMovesWeOffered() {
        let allowed = ChessEngine.legalMoves(in: .starting)
        let move = StockfishOpponent.move(fromBestMoveLine: "bestmove e2e4 ponder e7e5", allowedMoves: allowed)
        #expect(move?.from == Square("e2")!)
        #expect(move?.to == Square("e4")!)
    }

    @Test func aReplyOutsideTheOfferedMovesIsRefusedRatherThanGuessed() {
        // The engine must never be able to smuggle in a move the variant banned.
        let allowed = ChessEngine.legalMoves(in: .starting).filter { $0.from == Square("d2")! }
        #expect(StockfishOpponent.move(fromBestMoveLine: "bestmove e2e4", allowedMoves: allowed) == nil)
    }

    @Test func malformedRepliesAreRefused() {
        let allowed = ChessEngine.legalMoves(in: .starting)
        #expect(StockfishOpponent.move(fromBestMoveLine: "bestmove (none)", allowedMoves: allowed) == nil)
        #expect(StockfishOpponent.move(fromBestMoveLine: "bestmove", allowedMoves: allowed) == nil)
        #expect(StockfishOpponent.move(fromBestMoveLine: "", allowedMoves: allowed) == nil)
    }
}

/// Live engine tests. They share one process-wide engine, so they are
/// serialized — Stockfish keeps its state in globals and its output stream has
/// a single consumer.
@Suite(.serialized)
struct StockfishEngineTests {
    private func engine() async -> (any ChessOpponent)? {
        let opponent = await OpponentProvider.shared()
        return opponent is StockfishOpponent ? opponent : nil
    }

    @Test func theEngineBootsAndCompletesItsHandshake() async {
        let opponent = await OpponentProvider.shared()
        #expect(opponent is StockfishOpponent, "Stockfish did not boot; the app fell back to \(opponent.name)")
        #expect(opponent.name == "Stockfish")
    }

    @Test func bothBundledNetworksArePresentAndVerified() async {
        let bundle = Bundle.main
        #expect(bundle.url(
            forResource: StockfishProcess.bigNetworkName,
            withExtension: "nnue"
        ) != nil)
        #expect(bundle.url(
            forResource: StockfishProcess.smallNetworkName,
            withExtension: "nnue"
        ) != nil)

        _ = await OpponentProvider.shared()
        #expect(StockfishProcess.shared.networksLoaded)
    }

    @Test func itReturnsALegalOpeningMove() async throws {
        let booted = await engine()
        let engine = try #require(booted, "Stockfish is not available")
        let allowed = ChessEngine.legalMoves(in: .starting)
        let move = await engine.bestMove(for: OpponentRequest(
            position: .starting,
            allowedMoves: allowed,
            rating: OpponentPreset.sharp.rating
        ))
        let chosen = try #require(move)
        #expect(allowed.contains(chosen))
    }

    /// Black to move with a back-rank mate available: Ra1#. White has only
    /// pawns on f2/g2/h2 and a king on g1, so nothing blocks or escapes.
    private static let mateInOneFEN = "r5k1/8/8/8/8/8/5PPP/6K1 b - - 0 1"

    /// Finds the mating move using our own engine, so the test does not depend
    /// on the author's analysis being right.
    private func mateInOne(in position: Position) throws -> Move {
        let mates = ChessEngine.legalMoves(in: position).filter { move in
            guard let next = ChessEngine.apply(move, to: position) else { return false }
            if case .checkmate = ChessEngine.outcome(for: next, history: [position]) { return true }
            return false
        }
        #expect(mates.count == 1, "The fixture should have exactly one mate in one")
        return try #require(mates.first)
    }

    /// The whole variant contract in one test: the engine is given a position
    /// where the crushing move exists, but is not offered it.
    @Test func itNeverPlaysOutsideTheMovesItWasOffered() async throws {
        let booted = await engine()
        let engine = try #require(booted, "Stockfish is not available")
        let position = try #require(Position(fen: Self.mateInOneFEN))
        let all = ChessEngine.legalMoves(in: position)
        let mate = try mateInOne(in: position)
        let restricted = all.filter { $0.from != mate.from }
        #expect(!restricted.isEmpty)
        #expect(!restricted.contains(mate))

        for _ in 0..<3 {
            let move = await engine.bestMove(for: OpponentRequest(
                position: position,
                allowedMoves: restricted,
                rating: OpponentPreset.sharp.rating
            ))
            let chosen = try #require(move, "The engine gave no move for a position with legal replies")
            #expect(restricted.contains(chosen))
            #expect(chosen != mate, "searchmoves did not bind the engine")
        }
    }

    /// Proof that a real search is running, not just something that returns a
    /// legal move. A mate in one is unmissable at full strength.
    @Test func itFindsMateInOne() async throws {
        let booted = await engine()
        let engine = try #require(booted, "Stockfish is not available")
        let position = try #require(Position(fen: Self.mateInOneFEN))
        let mate = try mateInOne(in: position)

        let move = await engine.bestMove(for: OpponentRequest(
            position: position,
            allowedMoves: ChessEngine.legalMoves(in: position),
            rating: OpponentPreset.sharp.rating
        ))
        #expect(move == mate, "A full-strength engine must not miss mate in one")
    }

    @Test func aSingleAllowedMoveIsPlayedWithoutAskingTheEngine() async throws {
        let booted = await engine()
        let engine = try #require(booted, "Stockfish is not available")
        let position = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R w K - 0 1"))
        let only = try #require(ChessEngine.legalMoves(in: position).first)
        let move = await engine.bestMove(for: OpponentRequest(
            position: position,
            allowedMoves: [only],
            rating: OpponentPreset.sharp.rating
        ))
        #expect(move == only)
    }

    @Test func itHonoursAShortThinkingTime() async throws {
        let booted = await engine()
        let engine = try #require(booted, "Stockfish is not available")
        let started = ContinuousClock.now
        _ = await engine.bestMove(for: OpponentRequest(
            position: .starting,
            allowedMoves: ChessEngine.legalMoves(in: .starting),
            rating: OpponentPreset.sharp.rating,
            thinkingTime: .milliseconds(300)
        ))
        let elapsed = ContinuousClock.now - started
        // A short request must remain short enough for responsive play.
        #expect(elapsed < .seconds(3), "Reply took \(elapsed)")
    }

    /// Actors are reentrant, so a search that awaits can be interrupted by
    /// another caller. If the two exchanges interleave, the engine answers about
    /// whichever board was written last.
    @Test func aSearchIsNotCorruptedByConcurrentEngineUse() async throws {
        let booted = await engine()
        let engine = try #require(booted, "Stockfish is not available")
        let position = try #require(Position(fen: Self.mateInOneFEN))
        let mate = try mateInOne(in: position)

        async let search = engine.bestMove(for: OpponentRequest(
            position: position,
            allowedMoves: ChessEngine.legalMoves(in: position),
            rating: OpponentPreset.sharp.rating
        ))
        // Exactly what a restart does while a bot search is still in flight.
        async let reset: Void = engine.newGame()
        async let other = engine.bestMove(for: OpponentRequest(
            position: .starting,
            allowedMoves: ChessEngine.legalMoves(in: .starting),
            rating: OpponentPreset.sharp.rating
        ))

        let (found, _, opening) = await (search, reset, other)
        #expect(found == mate, "A concurrent ucinewgame or search corrupted this one")
        let openingMove = try #require(opening)
        #expect(ChessEngine.legalMoves(in: .starting).contains(openingMove))
    }

    @Test func everyRatingBandIsAcceptedByTheLiveEngine() async throws {
        let booted = await engine()
        let engine = try #require(booted, "Stockfish is not available")
        // Exercise both uncalibrated ends as well as the limiter boundaries.
        // Skill play is deliberately randomized, so move quality cannot be
        // ordered reliably from one position; the root contract remains exact.
        let ratings: [OpponentRating] = [
            .minimum,
            .lowestCalibrated,
            .default,
            .highestCalibrated,
            .maximum,
        ]
        for rating in ratings {
            let allowed = ChessEngine.legalMoves(in: .starting)
            let move = await engine.bestMove(for: OpponentRequest(
                position: .starting,
                allowedMoves: allowed,
                rating: rating
            ))
            let chosen = try #require(move)
            #expect(allowed.contains(chosen), "Illegal move at \(rating.rawValue)")
        }
    }
}

/// The session must survive an opponent that says nothing useful.
@MainActor
struct OpponentFallbackTests {
    private struct SilentOpponent: ChessOpponent {
        let name = "Silent"
        func bestMove(for request: OpponentRequest) async -> Move? { nil }
    }

    private struct CheatingOpponent: ChessOpponent {
        let name = "Cheat"
        func bestMove(for request: OpponentRequest) async -> Move? {
            // A move that is legal chess but was excluded by the variant.
            ChessEngine.legalMoves(in: request.position).first { !request.allowedMoves.contains($0) }
        }
    }

    private func waitForReply(_ game: GameSession, timeout: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if game.moveHistory.count >= 2 { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test func anOpponentWithNoOpinionStillGetsAMovePlayed() async {
        let game = GameSession(mode: .classic, opponent: { SilentOpponent() })
        #expect(game.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(await waitForReply(game), "The game stalled when the opponent returned nil")
        #expect(game.position.sideToMove == .white)
    }

    @Test func anOpponentCannotPlayAMoveTheVariantExcluded() async {
        let game = GameSession(mode: .restfish, opponent: { CheatingOpponent() })
        #expect(game.attemptMove(from: Square("e2")!, to: Square("e4")!))
        #expect(await waitForReply(game), "The game stalled")

        let reply = game.moveHistory[1]
        // Whatever the opponent proposed, what landed on the board came from the
        // session's own validated list.
        #expect(ChessEngine.legalMoves(in: game.positionHistory[1]).contains(reply))
    }
}
