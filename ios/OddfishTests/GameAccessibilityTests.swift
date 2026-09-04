import Testing
@testable import Oddfish

struct GameAccessibilityTests {
    @Test func ordinaryPlayerMovesDoNotRepeatTheActivatedSquare() {
        let event = MoveEvent(
            move: Move(from: Square("e2")!, to: Square("e4")!),
            side: .white,
            pieceKind: .pawn,
            capturedKind: nil,
            givesCheck: false,
            ply: 1,
            isPlayerMove: true
        )

        #expect(GameAccessibilityCopy.move(event, opponentName: "Stockfish", isBonusMove: false) == nil)
    }

    @Test func opponentReplyNamesMoveCaptureAndCheck() {
        let event = MoveEvent(
            move: Move(
                from: Square("g4")!,
                to: Square("e2")!,
                flags: [.capture]
            ),
            side: .black,
            pieceKind: .bishop,
            capturedKind: .pawn,
            givesCheck: true,
            ply: 8,
            isPlayerMove: false
        )

        #expect(
            GameAccessibilityCopy.move(event, opponentName: "Stockfish", isBonusMove: false)
                == "Stockfish moved bishop from g 4 to e 2, capturing your pawn. Your king is in check."
        )
    }

    @Test func playerOnlyHearsExceptionalTurnUpdates() {
        let event = MoveEvent(
            move: Move(from: Square("d1")!, to: Square("h5")!),
            side: .white,
            pieceKind: .queen,
            capturedKind: nil,
            givesCheck: true,
            ply: 3,
            isPlayerMove: true
        )

        #expect(
            GameAccessibilityCopy.move(event, opponentName: "Stockfish", isBonusMove: true)
                == "Check. Bonus move. You move again."
        )
    }

    @Test func castlingUsesNaturalSpeech() {
        let event = MoveEvent(
            move: Move(
                from: Square("e8")!,
                to: Square("g8")!,
                flags: [.castleKingside]
            ),
            side: .black,
            pieceKind: .king,
            capturedKind: nil,
            givesCheck: false,
            ply: 12,
            isPlayerMove: false
        )

        #expect(
            GameAccessibilityCopy.move(event, opponentName: "Stockfish", isBonusMove: false)
                == "Stockfish castled kingside. Your move."
        )
    }
}
