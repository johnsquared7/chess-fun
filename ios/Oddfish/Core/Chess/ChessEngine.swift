import Foundation

/// Stateless, deterministic orthodox chess rules. Variant rules deliberately sit above this type.
nonisolated enum ChessEngine {
    static func pseudoLegalMoves(in position: Position) -> [Move] {
        // Walks board indices rather than `position.squares()`, and reserves
        // room once. This is the hottest function in the app — the search calls
        // it for every candidate move at every node — so a 64-element array
        // allocated here, and again for the queen's directions below, was being
        // paid tens of thousands of times per bot move.
        var moves: [Move] = []
        moves.reserveCapacity(48)
        for index in 0..<64 {
            let square = Square(file: index % 8, rank: index / 8)
            guard let piece = position.piece(at: square), piece.color == position.sideToMove else { continue }
            switch piece.kind {
            case .pawn: appendPawnMoves(from: square, piece: piece, position: position, into: &moves)
            case .knight: appendLeaperMoves(from: square, piece: piece, offsets: knightOffsets, position: position, into: &moves)
            case .bishop: appendSliderMoves(from: square, piece: piece, directions: bishopDirections, position: position, into: &moves)
            case .rook: appendSliderMoves(from: square, piece: piece, directions: rookDirections, position: position, into: &moves)
            case .queen: appendSliderMoves(from: square, piece: piece, directions: queenDirections, position: position, into: &moves)
            case .king:
                appendLeaperMoves(from: square, piece: piece, offsets: kingOffsets, position: position, into: &moves)
                appendCastles(from: square, piece: piece, position: position, into: &moves)
            }
        }
        return moves
    }

    static func legalMoves(in position: Position) -> [Move] {
        pseudoLegalMoves(in: position).filter { isLegal($0, in: position) }
    }

    static func legalMoves(from square: Square, in position: Position) -> [Move] {
        legalMoves(in: position).filter { $0.from == square }
    }

    /// Whether the side to move has any legal move at all.
    ///
    /// Stops at the first one instead of validating every pseudo-legal move,
    /// which is all `outcome` needs to tell a live position from a mate or a
    /// stalemate. The search asks this at every leaf, where building and
    /// validating a full move list was the single most expensive thing it did.
    static func hasLegalMove(in position: Position) -> Bool {
        pseudoLegalMoves(in: position).contains { isLegal($0, in: position) }
    }

    /// The single legality test behind both `legalMoves` and `hasLegalMove`,
    /// so the list and the emptiness check can never disagree about what is
    /// legal.
    private static func isLegal(_ move: Move, in position: Position) -> Bool {
        guard isCastlePathSafe(move, in: position), let next = applyUnchecked(move, to: position) else { return false }
        return !isInCheck(position.sideToMove, in: next)
    }

    static func isInCheck(_ color: PieceColor, in position: Position) -> Bool {
        guard let king = position.kingSquare(of: color) else {
            // This only occurs for malformed analysis positions. It should not make a move legal.
            return true
        }
        return isSquareAttacked(king, by: color.opponent, in: position)
    }

    static func isSquareAttacked(_ target: Square, by attacker: PieceColor, in position: Position) -> Bool {
        // Pawns are directional and are easier to evaluate in reverse from the target square.
        let pawnSourceRank = target.rank - attacker.pawnDirection
        if (0..<8).contains(pawnSourceRank) {
            for file in [target.file - 1, target.file + 1] where (0..<8).contains(file) {
                if position.piece(at: Square(file: file, rank: pawnSourceRank)) == Piece(color: attacker, kind: .pawn) { return true }
            }
        }

        for (df, dr) in knightOffsets {
            if let source = target.offset(file: df, rank: dr), position.piece(at: source) == Piece(color: attacker, kind: .knight) { return true }
        }
        for (df, dr) in kingOffsets {
            if let source = target.offset(file: df, rank: dr), position.piece(at: source) == Piece(color: attacker, kind: .king) { return true }
        }
        if attackedBySlider(target, attacker: attacker, directions: bishopDirections, kinds: [.bishop, .queen], position: position) { return true }
        return attackedBySlider(target, attacker: attacker, directions: rookDirections, kinds: [.rook, .queen], position: position)
    }

    /// Validates an intent and returns its resulting immutable position. An intent without a
    /// promotion chooses a queen only when it is otherwise unambiguous for programmatic callers.
    static func apply(_ intent: Move, to position: Position) -> Position? {
        let matchingMoves = legalMoves(in: position).filter {
            $0.from == intent.from && $0.to == intent.to && (intent.flags.isEmpty || $0.flags == intent.flags)
        }
        guard !matchingMoves.isEmpty else { return nil }
        let move: Move
        if let promotion = intent.promotion {
            guard let selected = matchingMoves.first(where: { $0.promotion == promotion }) else { return nil }
            move = selected
        } else if let nonPromotion = matchingMoves.first(where: { $0.promotion == nil }) {
            move = nonPromotion
        } else if let queenPromotion = matchingMoves.first(where: { $0.promotion == .queen }) {
            move = queenPromotion
        } else {
            return nil
        }
        return applyUnchecked(move, to: position)
    }

    /// Applies a move already known to be legal in this position (for example,
    /// one drawn from `legalMoves(in:)`), skipping the validation scan `apply`
    /// performs. Callers passing anything else get nil, not a corrupt board.
    static func applyKnownLegal(_ move: Move, to position: Position) -> Position? {
        applyUnchecked(move, to: position)
    }

    static func outcome(for position: Position, history: [Position] = []) -> GameOutcome {
        if position.halfmoveClock >= 100 { return .draw(reason: .fiftyMoveRule) }
        if isInsufficientMaterial(position) { return .draw(reason: .insufficientMaterial) }

        // `history` contains preceding positions, not the current position.
        let repetitions = history.reduce(into: 1) { count, prior in
            if prior.repetitionKey == position.repetitionKey { count += 1 }
        }
        if repetitions >= 3 { return .draw(reason: .threefoldRepetition) }

        if hasLegalMove(in: position) { return .ongoing }
        return isInCheck(position.sideToMove, in: position) ? .checkmate(winner: position.sideToMove.opponent) : .stalemate
    }

    static func isInsufficientMaterial(_ position: Position) -> Bool {
        var nonKings: [(Square, Piece)] = []
        nonKings.reserveCapacity(8)
        for index in 0..<64 {
            let square = Square(file: index % 8, rank: index / 8)
            guard let piece = position.piece(at: square), piece.kind != .king else { continue }
            nonKings.append((square, piece))
        }
        if nonKings.isEmpty { return true }
        if nonKings.count == 1 { return nonKings[0].1.kind == .bishop || nonKings[0].1.kind == .knight }

        // A bare king cannot be checkmated by one or two knights (a knight
        // belonging to the defender could, however, block an escape square).
        if nonKings.count == 2,
           nonKings.allSatisfy({ $0.1.kind == .knight }),
           nonKings[0].1.color == nonKings[1].1.color { return true }

        // Bishops on a single colour complex can never force mate without another piece.
        if nonKings.allSatisfy({ $0.1.kind == .bishop }) {
            let colors = Set(nonKings.map { ($0.0.file + $0.0.rank) % 2 })
            return colors.count == 1
        }
        return false
    }

    private static let knightOffsets = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingOffsets = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)]
    private static let bishopDirections = [(1, 1), (1, -1), (-1, -1), (-1, 1)]
    private static let rookDirections = [(0, 1), (1, 0), (0, -1), (-1, 0)]
    private static let queenDirections = bishopDirections + rookDirections

    private static func appendPawnMoves(from square: Square, piece: Piece, position: Position, into moves: inout [Move]) {
        let direction = piece.color.pawnDirection
        if let oneStep = square.offset(file: 0, rank: direction), position.piece(at: oneStep) == nil {
            appendPawnMove(from: square, to: oneStep, flags: [], color: piece.color, into: &moves)
            if square.rank == piece.color.pawnHomeRank,
               let twoStep = square.offset(file: 0, rank: 2 * direction), position.piece(at: twoStep) == nil {
                moves.append(Move(from: square, to: twoStep, flags: .doublePawnPush))
            }
        }
        for deltaFile in [-1, 1] {
            guard let target = square.offset(file: deltaFile, rank: direction) else { continue }
            if let targetPiece = position.piece(at: target), targetPiece.color != piece.color, targetPiece.kind != .king {
                appendPawnMove(from: square, to: target, flags: .capture, color: piece.color, into: &moves)
            } else if target == position.enPassantTarget,
                      let capturedSquare = target.offset(file: 0, rank: -direction),
                      position.piece(at: capturedSquare) == Piece(color: piece.color.opponent, kind: .pawn) {
                moves.append(Move(from: square, to: target, flags: [.capture, .enPassant]))
            }
        }
    }

    private static func appendPawnMove(from: Square, to: Square, flags: MoveFlags, color: PieceColor, into moves: inout [Move]) {
        if to.rank == (color == .white ? 7 : 0) {
            for promotion in [PieceKind.queen, .rook, .bishop, .knight] {
                moves.append(Move(from: from, to: to, promotion: promotion, flags: flags))
            }
        } else {
            moves.append(Move(from: from, to: to, flags: flags))
        }
    }

    private static func appendLeaperMoves(from square: Square, piece: Piece, offsets: [(Int, Int)], position: Position, into moves: inout [Move]) {
        for (df, dr) in offsets {
            guard let target = square.offset(file: df, rank: dr) else { continue }
            guard let occupant = position.piece(at: target) else {
                moves.append(Move(from: square, to: target))
                continue
            }
            if occupant.color != piece.color, occupant.kind != .king {
                moves.append(Move(from: square, to: target, flags: .capture))
            }
        }
    }

    private static func appendSliderMoves(from square: Square, piece: Piece, directions: [(Int, Int)], position: Position, into moves: inout [Move]) {
        for (df, dr) in directions {
            var target = square.offset(file: df, rank: dr)
            while let current = target {
                if let occupant = position.piece(at: current) {
                    if occupant.color != piece.color, occupant.kind != .king {
                        moves.append(Move(from: square, to: current, flags: .capture))
                    }
                    break
                }
                moves.append(Move(from: square, to: current))
                target = current.offset(file: df, rank: dr)
            }
        }
    }

    private static func appendCastles(from square: Square, piece: Piece, position: Position, into moves: inout [Move]) {
        guard square.file == 4, square.rank == piece.color.kingHomeRank else { return }
        let rank = square.rank
        let kingsideRight: CastlingRights = piece.color == .white ? .whiteKingside : .blackKingside
        let queensideRight: CastlingRights = piece.color == .white ? .whiteQueenside : .blackQueenside
        if position.castlingRights.contains(kingsideRight),
           position.piece(at: Square(file: 7, rank: rank)) == Piece(color: piece.color, kind: .rook),
           position.piece(at: Square(file: 5, rank: rank)) == nil,
           position.piece(at: Square(file: 6, rank: rank)) == nil {
            moves.append(Move(from: square, to: Square(file: 6, rank: rank), flags: .castleKingside))
        }
        if position.castlingRights.contains(queensideRight),
           position.piece(at: Square(file: 0, rank: rank)) == Piece(color: piece.color, kind: .rook),
           position.piece(at: Square(file: 1, rank: rank)) == nil,
           position.piece(at: Square(file: 2, rank: rank)) == nil,
           position.piece(at: Square(file: 3, rank: rank)) == nil {
            moves.append(Move(from: square, to: Square(file: 2, rank: rank), flags: .castleQueenside))
        }
    }

    private static func attackedBySlider(_ target: Square, attacker: PieceColor, directions: [(Int, Int)], kinds: Set<PieceKind>, position: Position) -> Bool {
        for (df, dr) in directions {
            var source = target.offset(file: df, rank: dr)
            while let current = source {
                if let piece = position.piece(at: current) {
                    if piece.color == attacker, kinds.contains(piece.kind) { return true }
                    break
                }
                source = current.offset(file: df, rank: dr)
            }
        }
        return false
    }

    private static func isCastlePathSafe(_ move: Move, in position: Position) -> Bool {
        guard move.isCastle else { return true }
        let direction = move.flags.contains(.castleKingside) ? 1 : -1
        guard let middle = move.from.offset(file: direction, rank: 0) else { return false }
        let attacker = position.sideToMove.opponent
        return !isSquareAttacked(move.from, by: attacker, in: position)
            && !isSquareAttacked(middle, by: attacker, in: position)
            && !isSquareAttacked(move.to, by: attacker, in: position)
    }

    private static func applyUnchecked(_ move: Move, to position: Position) -> Position? {
        guard let movingPiece = position.piece(at: move.from), movingPiece.color == position.sideToMove else { return nil }
        var board = position.board
        board[move.from.index] = nil
        let capturedSquare: Square? = move.flags.contains(.enPassant)
            ? move.to.offset(file: 0, rank: -movingPiece.color.pawnDirection)
            : move.to
        let capturedPiece = capturedSquare.flatMap { board[$0.index] }
        if let capturedSquare { board[capturedSquare.index] = nil }

        var pieceAtDestination = movingPiece
        if let promotion = move.promotion { pieceAtDestination = Piece(color: movingPiece.color, kind: promotion) }
        board[move.to.index] = pieceAtDestination

        if move.flags.contains(.castleKingside) {
            let rookFrom = Square(file: 7, rank: move.from.rank)
            let rookTo = Square(file: 5, rank: move.from.rank)
            board[rookTo.index] = board[rookFrom.index]
            board[rookFrom.index] = nil
        } else if move.flags.contains(.castleQueenside) {
            let rookFrom = Square(file: 0, rank: move.from.rank)
            let rookTo = Square(file: 3, rank: move.from.rank)
            board[rookTo.index] = board[rookFrom.index]
            board[rookFrom.index] = nil
        }

        var rights = position.castlingRights
        removeCastlingRight(for: movingPiece, from: move.from, rights: &rights)
        if let capturedPiece, let capturedSquare { removeCastlingRight(for: capturedPiece, from: capturedSquare, rights: &rights) }
        let enPassant = move.flags.contains(.doublePawnPush)
            ? move.from.offset(file: 0, rank: movingPiece.color.pawnDirection)
            : nil
        let halfmove = (movingPiece.kind == .pawn || capturedPiece != nil) ? 0 : position.halfmoveClock + 1
        return Position(
            board: board,
            sideToMove: position.sideToMove.opponent,
            castlingRights: rights,
            enPassantTarget: enPassant,
            halfmoveClock: halfmove,
            fullmoveNumber: position.fullmoveNumber + (position.sideToMove == .black ? 1 : 0)
        )
    }

    private static func removeCastlingRight(for piece: Piece, from square: Square, rights: inout CastlingRights) {
        if piece.kind == .king {
            if piece.color == .white { rights.remove([.whiteKingside, .whiteQueenside]) }
            else { rights.remove([.blackKingside, .blackQueenside]) }
        } else if piece.kind == .rook {
            switch (piece.color, square.file, square.rank) {
            case (.white, 0, 0): rights.remove(.whiteQueenside)
            case (.white, 7, 0): rights.remove(.whiteKingside)
            case (.black, 0, 7): rights.remove(.blackQueenside)
            case (.black, 7, 7): rights.remove(.blackKingside)
            default: break
            }
        }
    }
}
