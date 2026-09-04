import Foundation
import Testing
@testable import Oddfish

/// The SAN layer is the contract between the move tape, every completed game
/// record, PGN export, and replay: `san(for:)` writes it, `move(matching:)`
/// reads it back. Disambiguation is where generation and parsing drift apart —
/// a wrongly disambiguated SAN exports a corrupt PGN, and a parse that guesses
/// among equal pieces replays the wrong board. None of that was covered before.
struct ChessNotationTests {

    @Test func enPassantCaptureUsesTheSourceFileAndParsesBack() throws {
        // King off the e-file: the e8 rook must not pin the capturing pawn,
        // or the engine would (correctly) refuse the capture as illegal.
        let position = try #require(Position(fen: "k3r3/8/8/3pP3/8/8/8/6K1 w - d6 0 1"))
        let legal = ChessEngine.legalMoves(in: position)
        let enPassant = try #require(legal.first { $0.flags.contains(.enPassant) })

        #expect(ChessNotation.san(for: enPassant, in: position, legalMoves: legal) == "exd6")
        #expect(ChessNotation.move(matching: "exd6", in: position, legalMoves: legal) == enPassant)
    }

    @Test func capturePromotionWithCheckIsGeneratedAndParsed() throws {
        let position = try #require(Position(fen: "2r4k/1P6/8/8/8/8/8/4K3 w - - 0 1"))
        let legal = ChessEngine.legalMoves(in: position)
        let capturingPromotion = try #require(legal.first {
            $0.to == Square("c8")! && $0.promotion == .queen
        })

        #expect(ChessNotation.san(for: capturingPromotion, in: position, legalMoves: legal) == "bxc8=Q+")
        #expect(ChessNotation.move(matching: "bxc8=Q+", in: position, legalMoves: legal) == capturingPromotion)
        #expect(ChessNotation.move(matching: "bxc8=Q", in: position, legalMoves: legal) == capturingPromotion)
        #expect(ChessNotation.move(matching: "c8=Q", in: position, legalMoves: legal) == nil,
                "Omitting the pawn's source file must not be guessed")
    }

    @Test func castlingAcceptsBothLetterAndDigitZero() throws {
        let position = try #require(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let legal = ChessEngine.legalMoves(in: position)
        let kingside = try #require(legal.first { $0.flags.contains(.castleKingside) })
        let queenside = try #require(legal.first { $0.flags.contains(.castleQueenside) })

        #expect(ChessNotation.san(for: kingside, in: position, legalMoves: legal) == "O-O")
        #expect(ChessNotation.move(matching: "O-O", in: position, legalMoves: legal) == kingside)
        #expect(ChessNotation.move(matching: "0-0", in: position, legalMoves: legal) == kingside)
        #expect(ChessNotation.move(matching: "0-0-0", in: position, legalMoves: legal) == queenside)
    }

    @Test func knightsOnOneFileDisambiguateByRank() throws {
        // Knights on e4 and e6 both attack c5; the file alone cannot tell them apart.
        let position = try #require(Position(fen: "k7/8/4N3/8/4N3/8/8/6K1 w - - 0 1"))
        let legal = ChessEngine.legalMoves(in: position)
        let fromE4 = try #require(legal.first { $0.from == Square("e4")! && $0.to == Square("c5")! })
        let fromE6 = try #require(legal.first { $0.from == Square("e6")! && $0.to == Square("c5")! })

        #expect(ChessNotation.san(for: fromE4, in: position, legalMoves: legal) == "N4c5")
        #expect(ChessNotation.san(for: fromE6, in: position, legalMoves: legal) == "N6c5")
        #expect(ChessNotation.move(matching: "N4c5", in: position, legalMoves: legal) == fromE4)
        #expect(ChessNotation.move(matching: "N6c5", in: position, legalMoves: legal) == fromE6)
        #expect(ChessNotation.move(matching: "Nc5", in: position, legalMoves: legal) == nil,
                "An ambiguous SAN must be refused, never resolved by luck")
    }

    @Test func rooksOnOneRankDisambiguateByFile() throws {
        let position = try #require(Position(fen: "7k/8/8/8/8/8/8/R3R2K w - - 0 1"))
        let legal = ChessEngine.legalMoves(in: position)
        let fromA1 = try #require(legal.first { $0.from == Square("a1")! && $0.to == Square("c1")! })
        let fromE1 = try #require(legal.first { $0.from == Square("e1")! && $0.to == Square("c1")! })

        #expect(ChessNotation.san(for: fromA1, in: position, legalMoves: legal) == "Rac1")
        #expect(ChessNotation.san(for: fromE1, in: position, legalMoves: legal) == "Rec1")
        #expect(ChessNotation.move(matching: "Rac1", in: position, legalMoves: legal) == fromA1)
        #expect(ChessNotation.move(matching: "Rec1", in: position, legalMoves: legal) == fromE1)
        #expect(ChessNotation.move(matching: "Rc1", in: position, legalMoves: legal) == nil)
    }

    @Test func threeAttackingKnightsDisambiguateByFullOrigin() throws {
        // Knights on b5, b3 and f5 all attack d4. b5 shares its file with b3 and
        // its rank with f5, so either disambiguator alone stays ambiguous.
        let position = try #require(Position(fen: "k7/8/8/1N3N2/8/1N6/8/6K1 w - - 0 1"))
        let legal = ChessEngine.legalMoves(in: position)
        let fromB5 = try #require(legal.first { $0.from == Square("b5")! && $0.to == Square("d4")! })
        let fromB3 = try #require(legal.first { $0.from == Square("b3")! && $0.to == Square("d4")! })
        let fromF5 = try #require(legal.first { $0.from == Square("f5")! && $0.to == Square("d4")! })

        #expect(ChessNotation.san(for: fromB5, in: position, legalMoves: legal) == "Nb5d4")
        #expect(ChessNotation.san(for: fromB3, in: position, legalMoves: legal) == "N3d4")
        #expect(ChessNotation.san(for: fromF5, in: position, legalMoves: legal) == "Nfd4")
        #expect(ChessNotation.move(matching: "Nb5d4", in: position, legalMoves: legal) == fromB5)
        #expect(ChessNotation.move(matching: "N3d4", in: position, legalMoves: legal) == fromB3)
        #expect(ChessNotation.move(matching: "Nfd4", in: position, legalMoves: legal) == fromF5)
        #expect(ChessNotation.move(matching: "Nd4", in: position, legalMoves: legal) == nil)
    }

    @Test func disambiguationSurvivesTheWholeRecordPipeline() throws {
        // The recorded notation is generated from UCI coordinates and later
        // parsed back for PGN export and replay. Getting the same move list
        // out of both ends is the contract a history entry depends on.
        let moves: [Move] = [
            Move(from: Square("b1")!, to: Square("c3")!),
            Move(from: Square("h7")!, to: Square("h6")!),
            Move(from: Square("c3")!, to: Square("e4")!),
            Move(from: Square("h6")!, to: Square("h5")!),
            Move(from: Square("e4")!, to: Square("g5")!),
            Move(from: Square("h5")!, to: Square("h4")!),
            Move(from: Square("g1")!, to: Square("f3")!),
        ]
        // Knights on g1 and g5 both attack f3; with no file difference the
        // rank decides, and only that exact SAN may parse back.
        let notation = ChessNotation.notation(
            for: moves,
            startingPosition: .starting,
            mode: .classic,
            playerColor: .white,
            parameters: .init()
        )
        #expect(notation == "Nc3 h6 Ne4 h5 Ng5 h4 N1f3")

        let replay = try GameReplay(
            notation: notation,
            startingPosition: .starting,
            mode: .classic,
            playerColor: .white,
            parameters: .init()
        )
        #expect(replay.plies.map(\.move) == moves)
        #expect(replay.plies.map(\.san) == ["Nc3", "h6", "Ne4", "h5", "Ng5", "h4", "N1f3"])
    }
}
