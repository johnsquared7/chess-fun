import Foundation
import Testing
@testable import Oddfish

/// The second wave: a pawn army, two mirrors of rules the catalogue already
/// had, a capture combo, an inverted rating rule, a forward-only board, and a
/// back rank that draws lots.
struct SecondWaveModeTests {
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

    private func context(lastPlayerMove: Move?, playerColor: PieceColor = .white) -> GimmickEngineContext {
        GimmickEngineContext(
            playerColor: playerColor,
            lastPlayerMove: lastPlayerMove,
            randomSample: 0,
            engineTurn: 0
        )
    }

    // MARK: - PawnFish

    @Test func pawnFishFieldsFifteenPawnsAndAKing() throws {
        let asWhite = PawnFishRule().startingPosition(playerColor: .white)
        for file in 0..<8 {
            #expect(asWhite.piece(at: Square(file: file, rank: 6)) == Piece(color: .black, kind: .pawn))
        }
        let backRank = (0..<8).map { asWhite.piece(at: Square(file: $0, rank: 7)) }
        #expect(backRank[4] == Piece(color: .black, kind: .king))
        #expect(
            backRank.enumerated().filter { $0.offset != 4 }
                .allSatisfy { $0.element == Piece(color: .black, kind: .pawn) }
        )
        // White's army is untouched, so its opening is the ordinary twenty.
        #expect(ChessEngine.legalMoves(in: asWhite).count == 20)
        // Black has no rook, so the right to castle is not offered.
        #expect(asWhite.fen.contains(" w KQ "))

        let asBlack = PawnFishRule().startingPosition(playerColor: .black)
        #expect(asBlack.fen.hasPrefix("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/PPPPKPPP w kq "))
    }

    /// The mode's defining feel: nothing on the back rank can move at all until
    /// the pawn standing in front of it does, and the king is walled in with it.
    @Test func theBackRankIsBlockedUntilThePawnsInFrontOfItMove() throws {
        let opening = PawnFishRule().startingPosition(playerColor: .white)
        let whiteMove = try #require(ChessEngine.legalMoves(in: opening).first)
        let blackToMove = try #require(ChessEngine.apply(whiteMove, to: opening))
        let replies = ChessEngine.legalMoves(in: blackToMove)
        #expect(!replies.isEmpty)
        #expect(replies.allSatisfy { $0.from.rank == 6 })
    }

    // MARK: - RevengeFish

    @Test func revengeFishAnswersOnTheSquareYouTookFrom() throws {
        // Black knight on c7 is the only piece that can answer on d5.
        let position = try #require(Position(fen: "4k3/2n5/8/3P4/8/8/8/4K3 b - - 0 1"))
        let candidates = ChessEngine.legalMoves(in: position)
        let rule = RevengeFishRule()

        let took = Move(from: Square("c4")!, to: Square("d5")!, flags: .capture)
        let forced = rule.allowedEngineMoves(
            in: position,
            candidates: candidates,
            context: context(lastPlayerMove: took),
            parameters: GimmickParameters()
        )
        #expect(forced.count == 1)
        #expect(forced.first?.to == Square("d5")!)
        #expect(forced.first?.isCapture == true)

        // No legal recapture leaves the whole list standing rather than
        // producing a move the position does not have.
        let unanswerable = Move(from: Square("g3")!, to: Square("h4")!, flags: .capture)
        #expect(
            rule.allowedEngineMoves(
                in: position,
                candidates: candidates,
                context: context(lastPlayerMove: unanswerable),
                parameters: GimmickParameters()
            ).count == candidates.count
        )

        // A quiet move demands nothing.
        let quiet = Move(from: Square("d4")!, to: Square("d5")!)
        #expect(
            rule.allowedEngineMoves(
                in: position,
                candidates: candidates,
                context: context(lastPlayerMove: quiet),
                parameters: GimmickParameters()
            ).count == candidates.count
        )
    }

    // MARK: - ContraryFish

    @Test func contraryFishIsMimicFishExactlyBackwards() throws {
        // White has just played Nf3, so the knight is the family in question.
        let position = try #require(Position(fen: "rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1"))
        let candidates = ChessEngine.legalMoves(in: position)
        let played = Move(from: Square("g1")!, to: Square("f3")!)
        let engineContext = context(lastPlayerMove: played)

        let contrary = ContraryFishRule().allowedEngineMoves(
            in: position, candidates: candidates, context: engineContext, parameters: GimmickParameters()
        )
        let mimic = MimicFishRule().allowedEngineMoves(
            in: position, candidates: candidates, context: engineContext, parameters: GimmickParameters()
        )
        #expect(!contrary.isEmpty)
        #expect(!mimic.isEmpty)
        #expect(contrary.count + mimic.count == candidates.count)
        #expect(Set(contrary).isDisjoint(with: Set(mimic)))
        #expect(contrary.allSatisfy { position.piece(at: $0.from)?.kind == .pawn })
    }

    @Test func contraryFishRulesOutBishopsAndKnightsTogether() throws {
        // White has just played Bc4. Banning only bishops would leave the
        // knight as the obvious answer, which is the mode read backwards.
        let position = try #require(Position(fen: "rnbqkbnr/pppp1ppp/8/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR b KQkq - 2 2"))
        let candidates = ChessEngine.legalMoves(in: position)
        #expect(candidates.contains { position.piece(at: $0.from)?.kind == .knight })
        #expect(candidates.contains { position.piece(at: $0.from)?.kind == .bishop })

        let allowed = ContraryFishRule().allowedEngineMoves(
            in: position,
            candidates: candidates,
            context: context(lastPlayerMove: Move(from: Square("f1")!, to: Square("c4")!)),
            parameters: GimmickParameters()
        )
        #expect(!allowed.isEmpty)
        #expect(
            allowed.allSatisfy { move in
                guard let kind = position.piece(at: move.from)?.kind else { return false }
                return kind != .bishop && kind != .knight
            }
        )
    }

    // MARK: - ComboFish

    @Test func comboFishPaysForAQuietCaptureOnly() throws {
        let rule = ComboFishRule()
        let parameters = GimmickParameters()
        let board = "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1"

        let quietCapture = try ply(fen: board) { move, _ in move.isCapture }
        #expect(quietCapture.wasCapture)
        #expect(!quietCapture.givesCheck)
        #expect(rule.grantsBonusMove(after: quietCapture, completedPlayerTurns: 1, parameters: parameters))

        // A capture that gives check pays nothing.
        let checkingCapture = try ply(fen: "4k3/4p3/8/8/8/8/8/4QK2 w - - 0 1") { move, _ in move.isCapture }
        #expect(checkingCapture.givesCheck)
        #expect(!rule.grantsBonusMove(after: checkingCapture, completedPlayerTurns: 1, parameters: parameters))

        // Nor does a quiet move, or the engine's own capture.
        let quietMove = try ply(fen: board) { move, _ in !move.isCapture }
        #expect(!rule.grantsBonusMove(after: quietMove, completedPlayerTurns: 1, parameters: parameters))
        let engineCapture = try ply(fen: board, playerColor: .black) { move, _ in move.isCapture }
        #expect(!rule.grantsBonusMove(after: engineCapture, completedPlayerTurns: 1, parameters: parameters))
    }

    // MARK: - LastStandFish

    @Test func lastStandFishRisesWithEveryPieceYouTake() throws {
        let rule = LastStandFishRule()
        let parameters = rule.defaultParameters
        let board = "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1"
        #expect(rule.startingRating == .minimum)

        let yourCapture = try ply(fen: board) { move, _ in move.isCapture }
        let fed = rule.rating(after: yourCapture, currentRating: .minimum, parameters: parameters)
        #expect(fed.rawValue == OpponentRating.minimum.rawValue + 200)

        // Only your captures feed it, and only captures do.
        let itsCapture = try ply(fen: board, playerColor: .black) { move, _ in move.isCapture }
        #expect(rule.rating(after: itsCapture, currentRating: .minimum, parameters: parameters) == .minimum)
        let quiet = try ply(fen: board) { move, _ in !move.isCapture }
        #expect(rule.rating(after: quiet, currentRating: .minimum, parameters: parameters) == .minimum)
    }

    // MARK: - UpstreamFish

    @Test func upstreamFishForbidsEveryRetreatButAKings() throws {
        let position = try #require(Position(fen: "4k3/8/8/8/3RK3/8/8/8 w - - 0 1"))
        let moves = VariantRules.legalMoves(in: position, state: .init(), configuration: .upstreamFish)

        let rookMoves = moves.filter { $0.from == Square("d4")! }
        #expect(rookMoves.contains { $0.to == Square("d5")! })
        #expect(rookMoves.contains { $0.to == Square("a4")! }, "sideways is not a retreat")
        #expect(!rookMoves.contains { $0.to == Square("d3")! })
        #expect(rookMoves.allSatisfy { $0.to.rank >= Square("d4")!.rank })

        let kingMoves = moves.filter { $0.from == Square("e4")! }
        #expect(kingMoves.contains { $0.to == Square("e3")! }, "the king is exempt")
    }

    @Test func upstreamFishBindsBothArmies() throws {
        let position = try #require(Position(fen: "4k3/3r4/8/8/8/8/8/4K3 b - - 0 1"))
        let moves = VariantRules.legalMoves(in: position, state: .init(), configuration: .upstreamFish)
        let rookMoves = moves.filter { $0.from == Square("d7")! }
        #expect(rookMoves.contains { $0.to == Square("d6")! })
        #expect(!rookMoves.contains { $0.to == Square("d8")! }, "d8 is back toward Black's own back rank")
    }

    /// White is checked along the first rank, has no king move, and the only
    /// block is a retreat. A mode rule may not turn that into a position with
    /// no legal move at all.
    @Test func upstreamFishNeverBlocksTheLastCheckEvasion() throws {
        let position = try #require(Position(fen: "4k3/1r6/8/8/3R4/8/6r1/K6r w - - 0 1"))
        let standard = ChessEngine.legalMoves(in: position)
        #expect(standard.count == 1)
        #expect(standard.first?.to == Square("d1")!)

        let evasions = VariantRules.legalMoves(in: position, state: .init(), configuration: .upstreamFish)
        #expect(evasions == standard)
    }

    // MARK: - ShuffleFish

    @Test func shuffleFishRebuildsTheSameRankForTheSameSeed() {
        let rule = ShuffleFishRule()
        #expect(
            rule.startingPosition(playerColor: .white, seed: 99)
                == rule.startingPosition(playerColor: .white, seed: 99)
        )

        let ranks = Set((0..<64).map { ShuffleFishRule.shuffledBackRank(seed: UInt64($0)) })
        #expect(ranks.count > 1, "sixty-four seeds produced one arrangement")
        for rank in ranks {
            #expect(rank.count == 8)
            #expect(Array(rank)[4] == "k", "the king never leaves the e-file")
            #expect(rank.filter { $0 == "r" }.count == 2)
            #expect(rank.filter { $0 == "n" }.count == 2)
            #expect(rank.filter { $0 == "b" }.count == 2)
            #expect(rank.filter { $0 == "q" }.count == 1)
        }
    }

    @Test func shuffleFishScramblesOneArmyAndOffersNoCastling() {
        let asWhite = ShuffleFishRule().startingPosition(playerColor: .white, seed: 7)
        #expect(asWhite.fen.contains("/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ "))

        let asBlack = ShuffleFishRule().startingPosition(playerColor: .black, seed: 7)
        #expect(asBlack.fen.hasPrefix("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/"))
        #expect(asBlack.fen.contains(" w kq "))
    }

    // MARK: - Catalogue

    @Test func theSecondWaveIsWiredIntoTheCatalogue() {
        let wave: [GameMode] = [
            .pawnFish, .revengeFish, .contraryFish, .comboFish,
            .lastStandFish, .upstreamFish, .shuffleFish
        ]
        #expect(wave.allSatisfy { GameMode.allCases.contains($0) })
        #expect(GameMode.allCases.count == 29)
        #expect(GameModeCategory.allCases.flatMap(\.modes).count == GameMode.allCases.count)

        for mode in wave {
            #expect(GuideCopy.teaching(for: mode) != nil, "\(mode.title) never teaches its rule")
            #expect(!mode.tagline.isEmpty)
            #expect(!mode.ruleSummary.isEmpty)
            #expect(!mode.inGameCue.isEmpty)
            #expect(!mode.crownRule.scoreDescription.isEmpty)
            #expect(
                type(of: mode.gimmickRule) != ExistingModeGimmickRule.self,
                "\(mode.title) has no rule of its own"
            )
        }

        #expect(GameMode.pawnFish.category == .armies)
        #expect(GameMode.shuffleFish.category == .armies)
        #expect(GameMode.lastStandFish.category == .growing)
        #expect(GameMode.upstreamFish.configuration.rule == .forwardOnly)
        #expect(GameMode.lastStandFish.crownRule.metric == .eloGainedPerPiece)
    }
}

/// Pawns on a back rank and a scrambled first rank are both positions ordinary
/// play cannot reach, so this asks the real engine rather than assuming it
/// copes. It joins `StockfishEngineTests` rather than forming a second suite:
/// two suites are serialized within themselves but still run against each
/// other, and there is only one engine process to go round.
extension StockfishEngineTests {
    @Test func stockfishSearchesTheAwkwardBoards() async throws {
        let opponent = await OpponentProvider.shared()
        guard opponent is StockfishOpponent else { return }

        let pawnFish = PawnFishRule().startingPosition(playerColor: .white)
        let firstWhiteMove = try #require(ChessEngine.legalMoves(in: pawnFish).first)
        let pawnFishToMove = try #require(ChessEngine.apply(firstWhiteMove, to: pawnFish))

        let boards = [
            pawnFish,
            // Black to move, which is what exercises pawns pushing off rank 8.
            pawnFishToMove,
            PawnFishRule().startingPosition(playerColor: .black),
            ShuffleFishRule().startingPosition(playerColor: .white, seed: 12_345)
        ]

        for board in boards {
            let allowed = ChessEngine.legalMoves(in: board)
            #expect(!allowed.isEmpty)
            let move = await opponent.bestMove(for: OpponentRequest(
                position: board,
                allowedMoves: allowed,
                rating: OpponentPreset.sharp.rating
            ))
            let chosen = try #require(move, "the engine returned nothing for \(board.fen)")
            #expect(allowed.contains(chosen))
        }
    }
}
