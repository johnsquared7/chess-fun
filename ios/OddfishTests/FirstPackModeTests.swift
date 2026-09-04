import Foundation
import Testing
import UIKit
@testable import Oddfish

/// The first themed expansion pack: two more strange armies, a matched pair of
/// capture rules, a live-Elo rubber band, and a deterministic mood swing.
struct FirstPackModeTests {
    private func ply(
        fen: String,
        playerColor: PieceColor = .white,
        choosing choose: (Move, Position) -> Bool
    ) throws -> GimmickPly {
        let before = try #require(Position(fen: fen))
        let move = try #require(ChessEngine.legalMoves(in: before).first { choose($0, before) })
        let after = try #require(ChessEngine.apply(move, to: before))
        let movingPiece = try #require(before.piece(at: move.from))
        return GimmickPly(
            move: move,
            movingPiece: movingPiece,
            positionBefore: before,
            positionAfter: after,
            ply: 1,
            wasCapture: move.isCapture,
            givesCheck: ChessEngine.isInCheck(after.sideToMove, in: after),
            analysis: nil,
            playerColor: playerColor
        )
    }

    private func line(rank: Int, move: Move, score: AnalysisScore) -> AnalysisLine {
        AnalysisLine(
            rank: rank,
            depth: 12,
            selectiveDepth: 16,
            move: move,
            score: score,
            principalVariation: [move],
            elapsedMilliseconds: 10,
            nodes: 100,
            nodesPerSecond: 10_000,
            tablebaseHits: 0,
            hashFull: 0
        )
    }

    private func context(sample: UInt64 = 1, engineTurn: Int = 0) -> GimmickEngineContext {
        GimmickEngineContext(
            playerColor: .white,
            lastPlayerMove: nil,
            randomSample: sample,
            engineTurn: engineTurn
        )
    }

    // MARK: - Strange armies

    @Test func theTwoNewArmiesReplaceOnlyTheOpponentBackRank() {
        let fortressWhite = FortressFishRule().startingPosition(playerColor: .white)
        #expect(fortressWhite.piece(at: Square("d8")!)?.kind == .rook)
        #expect(fortressWhite.piece(at: Square("e8")!)?.kind == .king)
        #expect(fortressWhite.piece(at: Square("b1")!)?.kind == .knight)

        let royalWhite = RoyalFishRule().startingPosition(playerColor: .white)
        #expect(royalWhite.piece(at: Square("a8")!)?.kind == .queen)
        #expect(royalWhite.piece(at: Square("e8")!)?.kind == .king)
        #expect(royalWhite.piece(at: Square("d1")!)?.kind == .queen)
        #expect(royalWhite.piece(at: Square("a1")!)?.kind == .rook)

        // Mirrored, the odd rank moves to rank 1 and the opponent still moves
        // first: these are handicaps, not a lost tempo.
        let fortressBlack = FortressFishRule().startingPosition(playerColor: .black)
        #expect(fortressBlack.piece(at: Square("d1")!)?.kind == .rook)
        #expect(fortressBlack.piece(at: Square("a8")!)?.kind == .rook)
        #expect(fortressBlack.piece(at: Square("b8")!)?.kind == .knight)
        #expect(fortressBlack.sideToMove == .white)

        let royalBlack = RoyalFishRule().startingPosition(playerColor: .black)
        #expect(royalBlack.piece(at: Square("h1")!)?.kind == .queen)
        #expect(royalBlack.piece(at: Square("h8")!)?.kind == .rook)
        #expect(royalBlack.sideToMove == .white)
    }

    /// ChapelFish and StableFish lose their castling rights because they have no
    /// rooks left to castle with. FortressFish has eight of them, so keeping the
    /// right is the honest position rather than a stray inconsistency.
    @Test func onlyTheArmyThatKeptItsCornerRooksKeepsCastling() {
        #expect(FortressFishRule().startingPosition(playerColor: .white).castlingRights == .initial)
        #expect(FortressFishRule().startingPosition(playerColor: .black).castlingRights == .initial)
        #expect(
            RoyalFishRule().startingPosition(playerColor: .white).castlingRights
                == [.whiteKingside, .whiteQueenside]
        )
        #expect(
            RoyalFishRule().startingPosition(playerColor: .black).castlingRights
                == [.blackKingside, .blackQueenside]
        )
    }

    @Test func bothNewArmiesStartFromALegalPlayablePosition() {
        let rules: [(name: String, rule: any GimmickRule)] = [
            ("FortressFish", FortressFishRule()),
            ("RoyalFish", RoyalFishRule())
        ]
        for (name, rule) in rules {
            for playerColor in [PieceColor.white, .black] {
                let position = rule.startingPosition(playerColor: playerColor)
                #expect(position != .starting, "\(name) fell back to the standard board")
                #expect(position.sideToMove == .white)
                #expect(!ChessEngine.isInCheck(.white, in: position))
                #expect(!ChessEngine.isInCheck(.black, in: position))
                #expect(!ChessEngine.legalMoves(in: position).isEmpty)
            }

            // The player's own army is untouched, so a player on White still
            // opens with the standard twenty moves.
            #expect(ChessEngine.legalMoves(in: rule.startingPosition(playerColor: .white)).count == 20)
        }
    }

    // MARK: - The capture pair

    @Test func pacifishTakesOnlyWhenNothingQuietIsLeft() throws {
        let position = try #require(Position(fen: "4k3/8/8/3p4/4P3/8/8/4K3 b - - 0 1"))
        let candidates = ChessEngine.legalMoves(in: position)
        #expect(candidates.contains { $0.isCapture })

        let quiet = PacifishRule().allowedEngineMoves(
            in: position,
            candidates: candidates,
            context: context(),
            parameters: .init()
        )
        #expect(!quiet.isEmpty)
        #expect(quiet.allSatisfy { !$0.isCapture })
        #expect(quiet.count == candidates.count - 1)

        // Pacifism is a preference, not a way to run out of moves.
        let cornered = try #require(Position(fen: "k7/PP6/8/8/8/8/8/K7 b - - 0 1"))
        let forced = ChessEngine.legalMoves(in: cornered)
        #expect(!forced.isEmpty)
        #expect(forced.allSatisfy { $0.isCapture })
        #expect(
            PacifishRule().allowedEngineMoves(
                in: cornered,
                candidates: forced,
                context: context(),
                parameters: .init()
            ) == forced
        )
    }

    @Test func piranhaFishBitesWheneverItCan() throws {
        let position = try #require(Position(fen: "4k3/8/8/3p4/4P3/8/8/4K3 b - - 0 1"))
        let candidates = ChessEngine.legalMoves(in: position)
        let bites = PiranhaFishRule().allowedEngineMoves(
            in: position,
            candidates: candidates,
            context: context(),
            parameters: .init()
        )
        #expect(bites.count == 1)
        #expect(bites.allSatisfy { $0.isCapture })
        #expect(bites.first?.to == Square("e4")!)

        let peaceful = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K3 b - - 0 1"))
        let quietOnly = ChessEngine.legalMoves(in: peaceful)
        #expect(!quietOnly.contains { $0.isCapture })
        #expect(
            PiranhaFishRule().allowedEngineMoves(
                in: peaceful,
                candidates: quietOnly,
                context: context(),
                parameters: .init()
            ) == quietOnly
        )
    }

    /// The two rules are exact inverses on the same board, and between them they
    /// account for every legal move.
    @Test func theCapturePairPartitionsTheSamePosition() throws {
        // White has just played d2-d4, so the only capture on the board is an
        // en passant one — which is exactly the capture a flag check could miss.
        let position = try #require(Position(fen: "r3k2r/pp3ppp/8/8/3Pp3/8/PP3PPP/R3K2R b KQkq d3 0 1"))
        let candidates = ChessEngine.legalMoves(in: position)
        #expect(candidates.contains { $0.flags.contains(.enPassant) })
        let quiet = PacifishRule().allowedEngineMoves(in: position, candidates: candidates, context: context(), parameters: .init())
        let bites = PiranhaFishRule().allowedEngineMoves(in: position, candidates: candidates, context: context(), parameters: .init())

        #expect(!quiet.isEmpty)
        #expect(!bites.isEmpty)
        #expect(Set(quiet).isDisjoint(with: Set(bites)))
        #expect(Set(quiet).union(bites) == Set(candidates))
    }

    // MARK: - ComebackFish

    @Test func comebackFishRisesWithTheMaterialYouAreAheadBy() throws {
        let rule = ComebackFishRule()
        #expect(rule.startingRating == .minimum)

        // Bxe3 puts the player three points up: 3 × 250.
        let capture = try ply(fen: "4k3/8/8/8/8/4n3/3B4/4K3 w - - 0 1") { move, _ in move.isCapture }
        #expect(rule.rating(after: capture, currentRating: .minimum, parameters: .init()) == OpponentRating(750))

        // A promotion is a material swing too: pawn out, queen in.
        let promotion = try ply(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1") { move, _ in move.promotion == .queen }
        #expect(rule.rating(after: promotion, currentRating: .minimum, parameters: .init()) == OpponentRating(2_000))
    }

    /// The mechanic is a rubber band, not a ratchet. Winning the material back
    /// has to relax it again, or one exchange would leave the fish permanently
    /// stronger than the board says it should be.
    @Test func comebackFishRelaxesWhenItWinsTheMaterialBack() throws {
        let rule = ComebackFishRule()
        let recapture = try ply(fen: "4k3/8/8/8/8/5n2/3R4/4K3 b - - 0 1") { move, _ in move.isCapture }
        #expect(rule.rating(after: recapture, currentRating: OpponentRating(750), parameters: .init()) == OpponentRating(250))
    }

    @Test func comebackFishIsNotFedByItsOwnLead() throws {
        let rule = ComebackFishRule()
        let alreadyAhead = try ply(fen: "4k3/8/8/8/8/8/3rP3/4K3 b - - 0 1") { move, _ in move.isCapture }
        #expect(rule.rating(after: alreadyAhead, currentRating: OpponentRating(400), parameters: .init()) == OpponentRating(400))

        let quiet = try ply(fen: "4k3/8/8/8/8/4n3/3B4/4K3 w - - 0 1") { move, _ in !move.isCapture }
        #expect(rule.rating(after: quiet, currentRating: OpponentRating(400), parameters: .init()) == OpponentRating(400))
    }

    @Test func comebackFishHonoursItsTunedRate() throws {
        let rule = ComebackFishRule()
        let definition = try #require(rule.parameterDefinitions.first)
        #expect(definition.id == GimmickParameterKey.amount)

        let capture = try ply(fen: "4k3/8/8/8/8/4n3/3B4/4K3 w - - 0 1") { move, _ in move.isCapture }
        let steep = GimmickParameters(values: [GimmickParameterKey.amount: 500])
        #expect(rule.rating(after: capture, currentRating: .minimum, parameters: steep) == OpponentRating(1_500))
    }

    // MARK: - MoodSwingFish

    @Test func moodSwingFishAlternatesBestAndWorstFromItsFirstReply() throws {
        let moves = ChessEngine.legalMoves(in: .starting)
        let best = try #require(moves.first)
        let middle = try #require(moves.dropFirst().first)
        let worst = try #require(moves.dropFirst(2).first)
        let analysis = PositionAnalysis(position: .starting, lines: [
            line(rank: 1, move: best, score: .centipawns(120)),
            line(rank: 2, move: middle, score: .centipawns(20)),
            line(rank: 3, move: worst, score: .centipawns(-260))
        ])

        let rule = MoodSwingFishRule()
        #expect(rule.requiresEngineAnalysis)
        // Genius first — the disaster has to be earned.
        #expect(rule.selectEngineMove(from: analysis, context: context(engineTurn: 0), parameters: .init()) == best)
        #expect(rule.selectEngineMove(from: analysis, context: context(engineTurn: 1), parameters: .init()) == worst)
        #expect(rule.selectEngineMove(from: analysis, context: context(engineTurn: 2), parameters: .init()) == best)
        #expect(rule.selectEngineMove(from: analysis, context: context(engineTurn: 3), parameters: .init()) == worst)
    }

    /// Unlike FumbleFish, the pattern must not depend on the random sample: the
    /// player is meant to be able to count turns and plan around the bad one.
    @Test func moodSwingFishIgnoresTheRandomSample() throws {
        let moves = ChessEngine.legalMoves(in: .starting)
        let best = try #require(moves.first)
        let worst = try #require(moves.dropFirst().first)
        let analysis = PositionAnalysis(position: .starting, lines: [
            line(rank: 1, move: best, score: .centipawns(90)),
            line(rank: 2, move: worst, score: .centipawns(-90))
        ])

        let rule = MoodSwingFishRule()
        for sample in [UInt64(0), 1, 2, 7, 4_096, .max] {
            #expect(rule.selectEngineMove(from: analysis, context: context(sample: sample, engineTurn: 0), parameters: .init()) == best)
            #expect(rule.selectEngineMove(from: analysis, context: context(sample: sample, engineTurn: 1), parameters: .init()) == worst)
        }
    }

    @Test func moodSwingFishFallsBackToTheOrdinaryOpponentWithNoAnalysis() {
        let empty = PositionAnalysis(position: .starting, lines: [])
        #expect(MoodSwingFishRule().selectEngineMove(from: empty, context: context(), parameters: .init()) == nil)
    }

    // MARK: - Catalogue wiring

    @Test func thePackIsWiredIntoTheCatalogue() {
        let pack: [GameMode] = [.fortressFish, .royalFish, .pacifish, .piranhaFish, .comebackFish, .moodSwingFish]
        #expect(Set(pack).count == pack.count)
        #expect(pack.allSatisfy { GameMode.allCases.contains($0) })

        #expect(GameMode.fortressFish.category == .armies)
        #expect(GameMode.royalFish.category == .armies)
        #expect(GameMode.pacifish.category == .constraints)
        #expect(GameMode.piranhaFish.category == .constraints)
        #expect(GameMode.comebackFish.category == .growing)
        #expect(GameMode.moodSwingFish.category == .chance)

        // Identifiers are what persisted records, snapshots and PGN tags are
        // keyed by, so they are part of the contract rather than a detail.
        #expect(GameMode.fortressFish.rawValue == "fortressfish")
        #expect(GameMode.royalFish.rawValue == "royalfish")
        #expect(GameMode.pacifish.rawValue == "pacifish")
        #expect(GameMode.piranhaFish.rawValue == "piranhafish")
        #expect(GameMode.comebackFish.rawValue == "comebackfish")
        #expect(GameMode.moodSwingFish.rawValue == "moodswingfish")

        for mode in pack {
            #expect(GuideCopy.teaching(for: mode) != nil, "\(mode.title) never teaches its rule")
            #expect(!mode.tagline.isEmpty)
            #expect(!mode.ruleSummary.isEmpty)
            #expect(!mode.inGameCue.isEmpty)
            #expect(type(of: mode.gimmickRule) != ExistingModeGimmickRule.self, "\(mode.title) has no rule of its own")
        }
    }

    /// A misspelled SF Symbol renders as nothing at all, and the mode glyph is
    /// how the catalogue tells one fish from another.
    @Test @MainActor func everyModeGlyphNamesARealSymbol() {
        for mode in GameMode.allCases {
            #expect(
                UIImage(systemName: mode.systemImage) != nil,
                "\(mode.title) points at a missing symbol: \(mode.systemImage)"
            )
        }
    }
}

@MainActor
struct FirstPackSessionTests {
    /// Ranks the allowed moves in the order the session offered them, so a test
    /// can name the best and worst line without running Stockfish.
    private struct RankedOpponent: ChessOpponent, ChessAnalysisService {
        let name = "Ranked Fish"

        func bestMove(for request: OpponentRequest) async -> Move? { request.allowedMoves.first }

        func analysisUpdates(for request: AnalysisRequest) async -> AsyncStream<PositionAnalysis> {
            AsyncStream { continuation in
                let lines = request.allowedMoves.enumerated().map { index, move in
                    AnalysisLine(
                        rank: index + 1,
                        depth: 12,
                        selectiveDepth: 14,
                        move: move,
                        score: .centipawns(200 - index * 10),
                        principalVariation: [move],
                        elapsedMilliseconds: 5,
                        nodes: 100,
                        nodesPerSecond: 20_000,
                        tablebaseHits: 0,
                        hashFull: 0
                    )
                }
                continuation.yield(PositionAnalysis(position: request.position, lines: lines))
                continuation.finish()
            }
        }

        func cancelAnalysis() async {}
    }

    /// A capture rule staged on a chosen board, so the filter can be observed
    /// through `GameSession.engineAllowedMoves` rather than in isolation.
    private struct StagedCaptureRule: GimmickRule {
        let fen: String
        let base: any GimmickRule

        var startingRating: OpponentRating { .maximum }

        func startingPosition(playerColor: PieceColor) -> Position {
            Position(fen: fen) ?? .starting
        }

        func allowedEngineMoves(
            in position: Position,
            candidates: [Move],
            context: GimmickEngineContext,
            parameters: GimmickParameters
        ) -> [Move] {
            base.allowedEngineMoves(in: position, candidates: candidates, context: context, parameters: parameters)
        }
    }

    private func session(mode: GameMode, fen: String, base: any GimmickRule) -> GameSession {
        GameSession(
            mode: mode,
            rule: StagedCaptureRule(fen: fen, base: base),
            playerColor: .white,
            gameSeed: 11,
            opponent: { RankedOpponent() }
        )
    }

    @Test func theCaptureRulesReachTheEngineThroughTheSession() {
        // Black to move with exactly one capture available, plus quiet moves.
        let fen = "4k3/8/8/3p4/4P3/8/8/4K3 b - - 0 1"

        let piranha = session(mode: .piranhaFish, fen: fen, base: PiranhaFishRule())
        let bites = piranha.engineAllowedMoves
        #expect(bites.count == 1)
        #expect(bites.allSatisfy { $0.isCapture })
        piranha.exit()

        let pacifist = session(mode: .pacifish, fen: fen, base: PacifishRule())
        let quiet = pacifist.engineAllowedMoves
        #expect(!quiet.isEmpty)
        #expect(quiet.allSatisfy { !$0.isCapture })
        pacifist.exit()
    }

    @Test func moodSwingFishSwingsAcrossConsecutiveEngineTurns() async throws {
        let session = GameSession(mode: .moodSwingFish, gameSeed: 3, opponent: { RankedOpponent() })

        #expect(session.attemptMove(from: Square("e2")!, to: Square("e4")!))
        let genius = try #require(session.engineAllowedMoves.first)
        try await waitForReply(session, moves: 2)
        #expect(session.lastMove == genius)

        #expect(session.attemptMove(from: Square("d2")!, to: Square("d4")!))
        let disaster = try #require(session.engineAllowedMoves.last)
        try await waitForReply(session, moves: 4)
        #expect(session.lastMove == disaster)
        #expect(disaster != genius)

        session.exit()
    }

    private func waitForReply(_ session: GameSession, moves: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while session.moveHistory.count < moves, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(session.moveHistory.count >= moves)
    }
}
