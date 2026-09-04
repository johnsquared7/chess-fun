import Foundation

/// A White-oriented board coordinate. `a1` is `(file: 0, rank: 0)`.
nonisolated struct Square: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    let file: Int
    let rank: Int

    init(file: Int, rank: Int) {
        precondition((0..<8).contains(file) && (0..<8).contains(rank), "A square must be on the board")
        self.file = file
        self.rank = rank
    }

    init?(_ algebraic: String) {
        let characters = Array(algebraic.lowercased())
        guard characters.count == 2,
              let file = "abcdefgh".firstIndex(of: characters[0]),
              let rank = characters[1].wholeNumberValue,
              (1...8).contains(rank) else { return nil }
        self.init(file: "abcdefgh".distance(from: "abcdefgh".startIndex, to: file), rank: rank - 1)
    }

    var algebraic: String {
        let files = Array("abcdefgh")
        return "\(files[file])\(rank + 1)"
    }

    var description: String { algebraic }
    var index: Int { rank * 8 + file }

    func offset(file deltaFile: Int, rank deltaRank: Int) -> Square? {
        let targetFile = file + deltaFile
        let targetRank = rank + deltaRank
        guard (0..<8).contains(targetFile), (0..<8).contains(targetRank) else { return nil }
        return Square(file: targetFile, rank: targetRank)
    }

    static func < (lhs: Square, rhs: Square) -> Bool { lhs.index < rhs.index }
}

nonisolated enum PieceColor: String, Codable, CaseIterable, Hashable, Sendable {
    case white
    case black

    var opponent: PieceColor { self == .white ? .black : .white }
    var pawnDirection: Int { self == .white ? 1 : -1 }
    var pawnHomeRank: Int { self == .white ? 1 : 6 }
    var kingHomeRank: Int { self == .white ? 0 : 7 }
    var fenCharacter: Character { self == .white ? "w" : "b" }
}

nonisolated enum PieceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case king, queen, rook, bishop, knight, pawn

    var fenCharacter: Character {
        switch self {
        case .king: "k"
        case .queen: "q"
        case .rook: "r"
        case .bishop: "b"
        case .knight: "n"
        case .pawn: "p"
        }
    }

    /// Whole-pawn values are sufficient for the live material readout. Kings
    /// are deliberately zero: losing one is an outcome, not a material swing.
    var materialValue: Int {
        switch self {
        case .queen: 9
        case .rook: 5
        case .bishop, .knight: 3
        case .pawn: 1
        case .king: 0
        }
    }

    static func fromFEN(_ character: Character) -> PieceKind? {
        switch character.lowercased() {
        case "k": .king
        case "q": .queen
        case "r": .rook
        case "b": .bishop
        case "n": .knight
        case "p": .pawn
        default: nil
        }
    }
}

nonisolated struct Piece: Codable, Hashable, Sendable {
    let color: PieceColor
    let kind: PieceKind

    var fenCharacter: Character {
        let character = kind.fenCharacter
        return color == .white ? Character(character.uppercased()) : character
    }
}

nonisolated struct MoveFlags: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    init(rawValue: UInt8) { self.rawValue = rawValue }

    static let capture = MoveFlags(rawValue: 1 << 0)
    static let enPassant = MoveFlags(rawValue: 1 << 1)
    static let castleKingside = MoveFlags(rawValue: 1 << 2)
    static let castleQueenside = MoveFlags(rawValue: 1 << 3)
    static let doublePawnPush = MoveFlags(rawValue: 1 << 4)
}

nonisolated struct Move: Codable, Hashable, Sendable, Comparable {
    let from: Square
    let to: Square
    let promotion: PieceKind?
    let flags: MoveFlags

    init(from: Square, to: Square, promotion: PieceKind? = nil, flags: MoveFlags = []) {
        self.from = from
        self.to = to
        self.promotion = promotion
        self.flags = flags
    }

    var isCapture: Bool { flags.contains(.capture) }
    var isCastle: Bool { flags.contains(.castleKingside) || flags.contains(.castleQueenside) }

    static func < (lhs: Move, rhs: Move) -> Bool {
        (lhs.from.index, lhs.to.index, lhs.promotion?.rawValue ?? "") < (rhs.from.index, rhs.to.index, rhs.promotion?.rawValue ?? "")
    }
}

nonisolated struct CastlingRights: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt8

    init(rawValue: UInt8 = 0) { self.rawValue = rawValue }

    static let whiteKingside = CastlingRights(rawValue: 1 << 0)
    static let whiteQueenside = CastlingRights(rawValue: 1 << 1)
    static let blackKingside = CastlingRights(rawValue: 1 << 2)
    static let blackQueenside = CastlingRights(rawValue: 1 << 3)

    static let initial: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]
}

nonisolated enum DrawReason: String, Codable, Hashable, Sendable {
    case threefoldRepetition
    case fiftyMoveRule
    case insufficientMaterial
}

nonisolated enum GameOutcome: Codable, Hashable, Sendable {
    case ongoing
    case checkmate(winner: PieceColor)
    case stalemate
    case draw(reason: DrawReason)

    var isTerminal: Bool {
        if case .ongoing = self { return false }
        return true
    }
}
