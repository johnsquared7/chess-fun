import Foundation

nonisolated struct Position: Codable, Hashable, Sendable {
    private(set) var board: [Piece?]
    let sideToMove: PieceColor
    let castlingRights: CastlingRights
    let enPassantTarget: Square?
    let halfmoveClock: Int
    let fullmoveNumber: Int

    init(
        board: [Piece?],
        sideToMove: PieceColor = .white,
        castlingRights: CastlingRights = .initial,
        enPassantTarget: Square? = nil,
        halfmoveClock: Int = 0,
        fullmoveNumber: Int = 1
    ) {
        precondition(board.count == 64, "A chess board contains exactly 64 squares")
        self.board = board
        self.sideToMove = sideToMove
        self.castlingRights = castlingRights
        self.enPassantTarget = enPassantTarget
        self.halfmoveClock = halfmoveClock
        self.fullmoveNumber = fullmoveNumber
    }

    init(
        pieces: [Square: Piece],
        sideToMove: PieceColor = .white,
        castlingRights: CastlingRights = [],
        enPassantTarget: Square? = nil,
        halfmoveClock: Int = 0,
        fullmoveNumber: Int = 1
    ) {
        var board = Array<Piece?>(repeating: nil, count: 64)
        for (square, piece) in pieces { board[square.index] = piece }
        self.init(board: board, sideToMove: sideToMove, castlingRights: castlingRights, enPassantTarget: enPassantTarget, halfmoveClock: halfmoveClock, fullmoveNumber: fullmoveNumber)
    }

    static let starting = Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")!

    subscript(square: Square) -> Piece? { board[square.index] }

    func piece(at square: Square) -> Piece? { board[square.index] }

    func squares() -> [Square] {
        (0..<64).map { Square(file: $0 % 8, rank: $0 / 8) }
    }

    /// The square holding `color`'s king, if it is on the board.
    ///
    /// Reads board storage directly rather than going through `squares()`,
    /// which allocates a 64-element array on every call. Check detection runs
    /// this for every candidate move during move generation, and the board view
    /// runs it while it draws, so the allocation was showing up in both.
    func kingSquare(of color: PieceColor) -> Square? {
        for index in board.indices {
            guard let piece = board[index], piece.kind == .king, piece.color == color else { continue }
            return Square(file: index % 8, rank: index / 8)
        }
        return nil
    }

    func materialValue(for color: PieceColor) -> Int {
        // One pass. The `compactMap`/`filter`/`reduce` chain this replaces
        // built two throwaway arrays per call, and the game screen calls it
        // four times over on every change.
        var total = 0
        for piece in board {
            guard let piece, piece.color == color else { continue }
            total += piece.kind.materialValue
        }
        return total
    }

    /// Signed from `viewer`'s perspective: positive means the viewer is ahead.
    func materialBalance(for viewer: PieceColor) -> Int {
        materialValue(for: viewer) - materialValue(for: viewer.opponent)
    }

    init?(fen: String) {
        let parts = fen.split(separator: " ")
        guard parts.count == 6 else { return nil }
        let ranks = parts[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8,
              let color = parts[1] == "w" ? PieceColor.white : (parts[1] == "b" ? .black : nil),
              let halfmove = Int(parts[4]), halfmove >= 0,
              let fullmove = Int(parts[5]), fullmove >= 1 else { return nil }

        var board = Array<Piece?>(repeating: nil, count: 64)
        for (fenRank, rankText) in ranks.enumerated() {
            var file = 0
            for character in rankText {
                if let count = character.wholeNumberValue {
                    guard (1...8).contains(count) else { return nil }
                    file += count
                } else {
                    guard file < 8, let kind = PieceKind.fromFEN(character) else { return nil }
                    let color: PieceColor = character.isUppercase ? .white : .black
                    board[(7 - fenRank) * 8 + file] = Piece(color: color, kind: kind)
                    file += 1
                }
            }
            guard file == 8 else { return nil }
        }

        var rights: CastlingRights = []
        if parts[2] != "-" {
            for character in parts[2] {
                switch character {
                case "K": rights.insert(.whiteKingside)
                case "Q": rights.insert(.whiteQueenside)
                case "k": rights.insert(.blackKingside)
                case "q": rights.insert(.blackQueenside)
                default: return nil
                }
            }
        }
        let enPassant: Square?
        if parts[3] == "-" { enPassant = nil }
        else {
            guard let square = Square(String(parts[3])) else { return nil }
            enPassant = square
        }
        self.init(board: board, sideToMove: color, castlingRights: rights, enPassantTarget: enPassant, halfmoveClock: halfmove, fullmoveNumber: fullmove)
    }

    var fen: String {
        var rankStrings: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var emptyCount = 0
            var value = ""
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if emptyCount > 0 { value += String(emptyCount); emptyCount = 0 }
                    value.append(piece.fenCharacter)
                } else {
                    emptyCount += 1
                }
            }
            if emptyCount > 0 { value += String(emptyCount) }
            rankStrings.append(value)
        }
        let castle = fenCastlingRights
        return "\(rankStrings.joined(separator: "/")) \(sideToMove.fenCharacter) \(castle) \(enPassantTarget?.algebraic ?? "-") \(halfmoveClock) \(fullmoveNumber)"
    }

    /// The FIDE-relevant state used when counting repeated positions.
    var repetitionKey: String {
        let parts = fen.split(separator: " ")
        return parts.prefix(4).joined(separator: " ")
    }

    /// Used by TempoFish for its consecutive player move. En-passant belongs to
    /// the side that would ordinarily reply, so it is cleared when that reply
    /// is skipped.
    func replacingSideToMove(_ color: PieceColor, clearEnPassant: Bool = false) -> Position {
        Position(
            board: board,
            sideToMove: color,
            castlingRights: castlingRights,
            enPassantTarget: clearEnPassant ? nil : enPassantTarget,
            halfmoveClock: halfmoveClock,
            fullmoveNumber: fullmoveNumber
        )
    }

    private var fenCastlingRights: String {
        var value = ""
        if castlingRights.contains(.whiteKingside) { value += "K" }
        if castlingRights.contains(.whiteQueenside) { value += "Q" }
        if castlingRights.contains(.blackKingside) { value += "k" }
        if castlingRights.contains(.blackQueenside) { value += "q" }
        return value.isEmpty ? "-" : value
    }
}
